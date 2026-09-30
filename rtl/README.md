# MID 信道融合 RTL 原型

这些文件是 PHY 接收机的第一个可综合内核，不是完整 FPGA 工程。接口按“一路每拍一个有效载波”设计，便于后续替换为 BRAM 和 AXI-Stream。

## 模块

- `cofdm_quadrant_select.sv`：根据复相关的实部/虚部绝对值选择四象限旋转，输出 `0:+1, 1:-j, 2:-1, 3:+j`。
- `cofdm_fusion_lane.sv`：单个载波的旋转、差分、`1/4` 算术右移或快速更新、饱和和一级寄存器输出。
- `cofdm_mid_fusion_ctrl.sv`：200 个载波流式缓存，标记导频相关，计算创新门限，完成旋转选择，然后输出200个融合载波。
- `cofdm_mid_fusion_ctrl_bram.sv`：Vivado/XC7Z020 版本。使用 XPM Block RAM，
  并将导频计算、累加和 BRAM 输出融合拆成流水级；状态机包含 `FLUSH` 和
  `FUSE_PREP`，用于处理流水尾项和 BRAM 同步读延迟。
- `cofdm_mid_fusion_ref_top.sv`：BRAM 融合控制器和 XPM Block FIFO 的参考 top。
- `cofdm_stf_sync_frontend.sv`：STF 16 点延迟、64 点滑动复相关/平方能量、
  归一化门限和多级流水检测前端；已接入独立的前端 Vivado 参考 top。
- `cofdm_ltf_time_matcher_tdm.sv`：LTF 精同步的低资源时分复用匹配器；配合
  `cofdm_ltf_sample_buffer.sv` 的显式 RAMB36E1 缓存，采用 L1 相关幅度和
  乘法/MAC 分级流水，面向 XC7Z020 的默认实现。
- `cofdm_ltf_template_rom_xilinx.sv`：Vivado `blk_mem_gen` ROM 封装。模板由
  `vivado/cofdm_ltf_sync_ref/cofdm_ltf_template.coe` 初始化，综合时通过
  `COFDM_XILINX_ROM` 宏启用，行为级仿真仍使用 `cofdm_ltf_template_rom.sv`。
- `cofdm_cfo_nco_rotator.sv`：Q0.32 相位增量输入、四象限小 ROM 和流式复数
  旋转；已在前端 Vivado 参考 top 综合。
- `cofdm_cfo_angle_estimator.sv`：共享 16 轮 CORDIC 矢量旋转，输出 STF 相关
  角度和对应的 Q0.32 频偏补偿增量。
- `cofdm_capture_ctrl.sv`：分级捕获状态机。STF 仅作为候选；LTF 合法位置和
  相关峰值、细频偏完成、PHY Header CRC 正确后才锁定；超时和错误候选进入
  `HOLDOFF`，并由 `false_alarm_count` 统计。
- `cofdm_capture_ref_top.sv`：将 STF/CFO 前端与捕获控制器连接的参考 top。
- `cofdm_nco_ltf_sync_bridge.sv`：把粗频偏 NCO 的固定流水延迟与 STF
  候选事件对齐，再启动 LTF 搜索。
- `cofdm_sync_ltf_cfo_top.sv`：STF 粗频偏、NCO、LTF 捕获和 capture FSM
  的闭环入口；`ENABLE_FINE_CHAIN=1` 时还会把双 LTF 精频偏链直接回写
  到 CFO 控制器。
- `cofdm_fft_stream_frontend.sv`：32 点 CP 去除、XFFT 256 AXI4-Stream
  配置和握手外围；XFFT IP 由 `vivado/cofdm_fft_ref/create_project.tcl`
  自动生成。
- `cofdm_ltf_freq_rom.sv`：两个 ZC LTF 的频域 Q1.15 系数 ROM，200 个有效
  子载波与 MATLAB `training.m` 的 `activeBins` 一一对应。
- `cofdm_ltf_channel_estimator.sv` / `cofdm_ltf_channel_chain.sv`：双 LTF
  频域 LS 信道估计及 XFFT 输出串接，执行 `Y*conj(T)` 和双 LTF 平均。
- `cofdm_pilot_phase_accum.sv`：8 导频复相关和一次/符号 CORDIC 公共相位估计；
  输入侧有一级寄存器，避免 BRAM 读延迟进入 DSP 累加关键路径。
- `cofdm_phase_lut.sv` / `cofdm_common_phase_rotator.sv`：256 分辨率公共相位
  LUT 和流水复数旋转器；相位 LUT 只取相位高 8 位，适合共享一个旋转通路。
- `cofdm_matched_llr.sv`：三级流水 `conj(H)*Y`、逆噪声乘法、LLR 算术右移和
  饱和，支持 Header BPSK 与数据 QPSK。
- `cofdm_pre_ldpc_symbol.sv`：XFFT 后到 LDPC 前的符号缓存参考核。缓存 H 和
  256 点 Y，完成导频公共相位、逐数据载波旋转和 192 路 LLR 输出；不包含解交织、
  解扰、CRC 或 LDPC。
- `cofdm_pilot_prbs.sv` / `cofdm_symbol_pilots.sv`：使用与 MATLAB 相同的
  x^7+x^4+1 PRBS，自动产生每个符号的 8 个导频符号并完成自然 bin 映射。
- `cofdm_llr_packetizer.sv`：缓存一个 OFDM 符号，重排到负频率优先的 MATLAB
  载波顺序，串化 I/Q LLR，产生 Header、符号末尾和 648 位码字边界标记。
- `cofdm_header_descrambler.sv`：Header LLR 的 Q7 PRBS 符号翻转，包含最小负数
  饱和保护。
- `cofdm_llr_fifo.sv`：有限深度软信息 FIFO；定义 `COFDM_XILINX_FIFO` 时使用
  Vivado XPM Block FIFO，仿真路径保持相同 ready/valid 行为。
- `cofdm_pre_ldpc_stream.sv`：将符号核、导频、载波重排、Header/数据装帧和软
  FIFO 连接起来的参考入口，输出仍是 LDPC 译码器的软比特接口。
- `cofdm_v2_header_decoder.sv`：v2 Header 的 64 状态、54 步软判决 Viterbi，
  支持已知零初始/终止状态、CRC16、版本/MCS/长度/种子/Midamble 字段校验。
  每拍一个 trellis step，只有 64×54 bit survivor RAM，不使用 DSP。
- `cofdm_v2_rx_header_path.sv`：Header 判决门控。Header `header_ok` 之前不
  释放 Payload LLR，避免错误长度进入后级缓存。
- `cofdm_pre_fft_replay_mem.sv` / `cofdm_pre_fft_replay.sv`：用 RAMB36E1
  组成同步后的 IQ 回放缓存。LTF 匹配结果晚于训练符号到达时，重新输出
  LTF1、LTF2 和数据符号，并在每个 CP 首样点给出 `out_symbol_start`。
- `cofdm_pre_fft_stream_replay.sv`：面向超长帧的有限深度环形回放器。
  `replay_symbol_count` 是运行时计数，不会把整帧长度展开成 RAM；只要
  输入连续、输出不长期阻塞，同一块 BRAM 可以流式输出任意长度帧。
  `replay_extend_valid` 可在 Header 解码后扩展输出长度；超过 255 个符号时
  将 `SYMBOL_INDEX_W`（及长帧入口对应参数）设为 16，避免索引元数据回绕。
- `cofdm_sync_pre_fft_frontend.sv`：把 STF、粗 CFO/NCO、LTF 搜索、回放
  缓存统一为 XFFT 前的时域接收入口。
- `cofdm_sync_pre_fft_stream_frontend.sv`：长帧版本，使用运行时的
  `replay_symbol_count` 驱动环形回放，不按最大帧长分配 RAM。

## 频域到 LDPC 的实际顺序

```text
XFFT natural bins
  -> 200 active bins / 8 pilots -> BRAM symbol buffer
  -> pilot common phase + shared complex rotator -> data LLR
  -> negative-frequency-first rank reorder -> I/Q serial stream
  -> Header PRBS31 descramble -> Header decoder/CRC
  -> inverse interleave -> bounded LDPC input FIFO -> LDPC
  -> payload PRBS descramble -> payload CRC32
```

MATLAB 的 `c.interleaver = mod(13*(0:383),384)+1` 是 TX 的写地址；接收端写入
后必须按 `13^-1 mod 384 = 325` 的地址序列读出。该地址与 FFT bin 顺序无关，
不能直接把 FFT 输出 bin 号作为 LDPC 地址。导频 PRBS 每个 Header/Data 符号消耗
8 bit，LTF/Midamble 由控制器推进符号状态。

运行频域到 LDPC 前的 MATLAB/RTL 对拍：

```bash
/opt/Polyspace/R2020b/bin/matlab -batch \
  "addpath('matlab'); export_pre_ldpc_stream_vectors"
bash matlab/tests/run_pre_ldpc_stream_checks.sh
```

该回归覆盖 ready/valid 停顿、负频率重排、Header 解扰、648 位码字边界、连续
码字和末尾 padding。Vivado 入口为
`matlab/vivado/cofdm_pre_ldpc_stream_ref/run_synth.tcl`，XC7Z020-2、122.88 MHz
综合结果为 2287 LUT、697 FF、16 DSP48E1、3 个 Block RAM Tile，WNS +0.683 ns、
TNS 0；这些资源只覆盖 LDPC 前软信息链，不包括 LDPC 译码器本身。

## 控制器时序

```text
IDLE --start--> CAPTURE(最多200拍) --> DECIDE(1拍)
                                      --> OUTPUT(200拍) --> IDLE
```

`sample_last` 可以提前结束捕获，但正常帧应严格输入 `N_ACTIVE=200` 个载波。`out_last` 标记第200个输出，`done` 与最后一个输出同一时钟周期有效。Vivado 版本显式使用 XPM 双口 BRAM，并在 122.88 MHz 综合级时序下达到 WNS=+0.733 ns、TNS=0。

导频相关目前在控制器中使用四个全精度乘积表达式，综合时可以复用一个复乘器并把导频累加展开到8拍；全带宽融合只需符号交换、减法、移位和加法。

## 验证

统一 pre-FFT 链路检查：

```bash
./run_checks.sh
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_sync_ref/run_sim_pre_fft.tcl
```

完整同步/频偏检查（包含端到端闭环）:

```bash
cd matlab/rtl
./run_checks.sh
```

XFFT 后至 LDPC 前参考核的 XC7Z020 综合：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_pre_ldpc_ref/run_synth.tcl
```

Vivado 2022.2 的 COE ROM、XSim 和综合入口位于
`matlab/vivado/cofdm_ltf_sync_ref/`；闭环仿真命令为:

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_sync_ref/run_sim_closed_loop.tcl
```

```bash
iverilog -g2012 -o /tmp/cofdm_fusion_tb \
  rtl/cofdm_fusion_lane.sv rtl/tb/tb_fusion_kernel.sv && vvp /tmp/cofdm_fusion_tb
iverilog -g2012 -o /tmp/cofdm_quad_tb \
  rtl/cofdm_quadrant_select.sv rtl/tb/tb_quadrant.sv && vvp /tmp/cofdm_quad_tb
iverilog -g2012 -o /tmp/cofdm_mid_tb \
  rtl/cofdm_mid_fusion_ctrl.sv rtl/tb/tb_mid_fusion_ctrl.sv && vvp /tmp/cofdm_mid_tb
iverilog -g2012 -o /tmp/cofdm_capture_tb \
  rtl/cofdm_capture_ctrl.sv rtl/tb/tb_capture_ctrl.sv && vvp /tmp/cofdm_capture_tb
verilator --lint-only -Wall --top-module cofdm_quadrant_select rtl/cofdm_quadrant_select.sv
verilator --lint-only -Wall --top-module cofdm_fusion_lane rtl/cofdm_fusion_lane.sv
verilator --lint-only -Wall --top-module cofdm_mid_fusion_ctrl rtl/cofdm_mid_fusion_ctrl.sv
verilator --lint-only -Wall --top-module cofdm_capture_ctrl rtl/cofdm_capture_ctrl.sv
```

MATLAB 导出四组 200 载波向量，独立 Python 整数参考检查：

```bash
/opt/Polyspace/R2020b/bin/matlab -batch "addpath('matlab'); export_fusion_vectors()"
python3 matlab/tests/verify_fusion_vectors.py
```

同步阶段的统一 MATLAB 回归和 FPGA 对拍向量：

```bash
/opt/Polyspace/R2020b/bin/matlab -batch \
  "addpath('matlab'); addpath('matlab/tests'); \
   run_sync_regression('matlab/results/sync_regression')"
```

该命令覆盖无噪声、AWGN+CFO、多径、低 SNR、噪声-only 和周期性伪信号，
统计 STF 检测率、LTF 捕获率、最终锁定率、CP 窗口内率、粗/精/最终 CFO
误差、位置误差和误接受率，并生成：

- `sync_regression.csv`：适合持续集成和灵敏度曲线；
- `sync_golden.mat`：MATLAB 原生复数 IQ 与事件真值；
- `sync_golden_iq.csv` / `sync_golden_expected.csv`：适合 XSim/iverilog
  测试平台逐点回放。

`cofdm.synchronize` 的 `stfDetected`、`ltfDetected`、`stfStart`、
`ltfPeakStart`、`coarseCfoHz`、`fineCfoHz` 和 `cfoHz` 字段与 RTL 捕获
控制器的事件顺序对应。这样同步阶段可以先在 MATLAB 做算法回归，再用同一
黄金输入检查 RTL 的事件和定点误差；MATLAB 的成功只证明算法模型，不能替代
XSim 和上板测试。

向量规则固定了相关乘积、四象限、Verilog 算术右移和18位饱和。下一步是把
Header decoder/CRC 和 QC-LDPC 输入 FIFO 接入这个已经通过对拍的边界。

## v2 Header FPGA 验证

MATLAB 生成 1、257、2048 字节三种边界长度，以及一个非法全零 Header：

```bash
/opt/Polyspace/R2020b/bin/matlab -batch \
  "addpath('matlab'); export_v2_header_vectors"
cd matlab/rtl && ./run_checks.sh
```

已验证：Viterbi 软判决、CRC16、版本=2、MCS=0、长度范围 1–2048、非零
Scrambler Seed、Midamble Code 0–2，以及 Header 正确前的 Payload 门控。
Header 本身只携带 48 个信息比特、54 个 trellis step、108 个编码比特，
所以该结构比 QC-LDPC 译码器简单很多；但最终误包判定仍必须依赖 CRC 和字段
校验，不能只看 Viterbi 的路径度量。
# 统一 v2 接收入口

`cofdm_phy_rx_v2_top.sv` 是带 XFFT IP 的 XC7Z020 参考壳体；`cofdm_phy_rx_v2_freq_top.sv` 是不含 XFFT 的频域闭环，便于用记录的 XFFT bin 做 RTL 对拍。两者均在 `matlab/docs/同步到V2头部统一接收链路.md` 中说明。

Vivado 2022.2 综合/仿真脚本：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_v2_header_ref/run_synth_full_top.tcl
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_v2_header_ref/run_sim_full_top.tcl
```

仿真脚本同时使用 XFFT、XPM FIFO 和 RAMB36E1 配置；回放溢出、Header 延迟续接和 Payload LLR 门控均有独立测试。

## V2 统一接收入口

`cofdm_phy_rx_v2_top.sv` 是带 XFFT IP 的 XC7Z020 参考壳体；`cofdm_phy_rx_v2_freq_top.sv` 是不含 XFFT 的频域闭环，便于用记录的 XFFT bin 做 RTL 对拍。完整说明和验证结果见 `matlab/docs/同步到V2头部统一接收链路.md`。

Vivado 2022.2：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_v2_header_ref/run_synth_full_top.tcl
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_v2_header_ref/run_sim_full_top.tcl
```

仿真脚本使用真实 XFFT、XPM FIFO 和 RAMB36E1 配置；行为回放、头部延迟续接和覆盖报错也有独立测试。
