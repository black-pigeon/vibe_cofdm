# FPGA 双 LTF 精同步后处理链路

本文记录 XC7Z020CLG400-2 上从 XFFT 输出到精频偏 NCO 控制量的当前实现。该链路对应 MATLAB `cofdm.ltf_process` 的 `Y1/Y2 → finePhaseRad → finePhaseInc`，输入已经经过 STF 粗捕获、粗频偏补偿、LTF 时域精同步和 CP 去除。

## 数据流

```text
XFFT AXI-Stream（自然序、可能有 valid 气泡）
        │
        ▼
cofdm_ltf_fft_stream_adapter
  计数 bin、识别 TLAST、标记 LTF1/LTF2、应用 active mask
        │
        ▼
cofdm_ltf_fine_cfo_accum
  LTF1 BRAM/LUTRAM 缓存
  Y2·conj(Y1)·T1·conj(T2) 逐载波累加
        │  3 级流水
        ▼
cofdm_cordic_atan2
  16 次迭代、共享加法器，输出 Q3.29 弧度
        │
        ▼
cofdm_fine_cfo_phase_to_inc
  输出负号修正量 Q0.32，直接接 NCO phase_inc
```

适配器只在 `valid && ready` 时递增 bin，因此 XFFT 的输出气泡不会造成频点错位。当前 `ready` 固定为 1，后续如果在 CORDIC 前增加 FIFO，可以把它改成真正的反压接口。

## 定点约定

- XFFT I/Q：有符号 16 bit；
- LTF 旋转系数：Q1.15；
- 累加器：有符号 64 bit；
- CORDIC 相位：Q3.29，`pi = 0x6487ED51`；
- NCO 相位增量：有符号 Q0.32，正 CFO 对应负修正量；
- 256 点 FFT、32 点 CP 时，增量换算常数为 `74172 / 2^24`。更改 FFT/CP 后应重新计算该常数，不能继续使用旧值。

## 流水和资源结果

`cofdm_ltf_fine_cfo_accum` 已从单周期复数乘加改为三段流水。此前 `rot_re/rot_im`
常数输入只适合单元测试中的 `rot=1` 简化情况；现在生产路径启用
`cofdm_ltf_rot_rom.sv`，按自然 FFT bin 读取 MATLAB 两个 ZC LTF 的
`T1*conj(T2)` 复系数，再与 `Y2*conj(Y1)` 相乘。这样才与
`ltf_process.m` 的 `H2.*conj(H1)` 完全等价：

1. 四个 `Y2` 与 `conj(Y1)` 乘积；
2. 实部/虚部交叉加减；
3. 乘以训练序列旋转系数并累加。

Vivado 2022.2 对 `xc7z020clg400-2` 的综合结果（`cofdm_ltf_chain_ref`）：

| 资源 | 使用量 | 器件总量 |
|---|---:|---:|
| LUT | 1256 | 53200 |
| FF | 477 | 106400 |
| DSP48E1 | 12 | 220 |
| RAMB18 | 0 | 280 |

时钟约束为 8.138 ns（122.88 MHz），流水版本 WNS `+0.208 ns`、TNS `0 ns`；旧单周期版本 WNS 为 `-8.668 ns`。当前两路 256×16 LTF 缓存被 Vivado 推断为分布式 RAM（128 LUT），原因是读端是异步组合读。要节省 LUT 并使用 BRAM，需要把存储器改成同步读并为计算链再增加一拍，或者显式实例化两块 `RAMB18E1`。

## 仿真和综合

```bash
bash matlab/rtl/run_checks.sh

/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_chain_ref/run_sim.tcl

/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_chain_ref/run_synth.tcl
```

RTL 和 Vivado XSim 都用 LTF1=`1000+j0`、LTF2=`0+j1000` 的确定性向量验证，预期相位约 `pi/2`，输出修正增量约 `-3.73e6`。实际系统中旋转系数由 ZC LTF 已知序列生成并放入 ROM，不能使用测试向量中的常数 32767。

## 尚未闭合的 FPGA 工作

1. **LTF 时域精同步**：当前链路假设上游已经提供正确的 LTF1 起点；仍需实现滑动匹配相关、峰值门限、保护窗和候选确认，并把真实 `ltf_peak_*` 接入 `cofdm_capture_ctrl`。
2. **精频偏自动回写**：将 `phase_inc_valid/phase_inc` 锁存到 NCO 控制寄存器，在 Header 首个有效样点前切换；需要定义跨模块握手和清相位时刻。
3. **信道估计**：`cofdm_ltf_channel_chain.sv` 已实现双 LTF 的 `H1/H2` 平均和
   BRAM 存储，并已加入 `noise_variance = mean(|H1-H2|^2)/2` 的定点统计输出。
   `H_FRAC_BITS` 可配置为 MATLAB `compact_fixed` 的 14 位小数。独立参考工程
   的 XC7Z020 综合结果为 WNS `+0.426 ns`、6 个 DSP48E1、2 个 RAMB18、944 个
   LUT；仍需加入 MATLAB `estimate_channel.m` 的 FIR7/时延投影选项、幅相限幅
   和数据符号导频跟踪。
4. **BRAM 化**：同步读 RAM 会增加一拍，但可以释放约 128 LUT；应在完整链路上重新跑时序，避免为省 LUT 引入新的关键路径。
5. **主链路接入**：当前 `cofdm_sync_pre_fft_frontend` 仍将
   `cofdm_sync_ltf_cfo_top` 的 `fft_out_*` 接成常量，独立的双 LTF 频域链还没有
   接入 XFFT 输出；必须在此处加入 XFFT 前端、TLAST/bin 元数据和
   `cofdm_ltf_channel_chain`，再将 `noise_valid` 与 `fine_phase_inc` 送入后级。
6. **异常帧处理**：需要对缺失 TLAST、LTF1/LTF2 间隔错误、CORDIC 忙和超时增加丢帧/重捕获事件。
