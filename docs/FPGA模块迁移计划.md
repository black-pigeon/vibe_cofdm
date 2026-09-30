# MATLAB 到 XC7Z020 FPGA 的 PHY 迁移计划

本文把 MATLAB 接收机的处理顺序映射到可综合 RTL。每个模块先保留 MATLAB
作为 golden reference，再使用定点向量做逐拍对拍；通过后才加入 Vivado
完整工程。当前工程的 MID 融合参考 top 仍保持独立，避免未完成的前端模块
改变已有资源基线。

## 当前状态

| 链路模块 | MATLAB | 独立 RTL | Vivado 参考 top |
|---|---|---|---|
| STF 同步相关/检测 | `cofdm.synchronize` 中的 `P/E1/E2` | `cofdm_stf_sync_frontend.sv` 已完成平方能量、滑窗和多级流水 | 前端参考 top 已接入 |
| 粗频偏估计/补偿 | MATLAB 浮点 `angle(P)` 和复指数 | `cofdm_cfo_angle_estimator.sv` 16 轮 CORDIC + `cofdm_cfo_nco_rotator.sv` Q0.32 NCO | 前端参考 top 已接入 |
| LTF 精同步 | LTF 相关搜索 | 待实现滑窗相关/峰值搜索 | 未实现 |
| CFO 细估计 | 两个 LTF 的相位差 | 待实现 | 未实现 |
| CP/FFT | `rx.m` 中 FFT 截取 | 待接 Xilinx FFT IP 或定制 FFT | 未实现 |
| 信道估计 | `estimate_channel.m` | 待实现 LS/FIR 定点版 | 未实现 |
| 导频跟踪/均衡 | `track_pilots.m`、`rx.m` | 待实现 | 未实现 |
| 解调/解交织 | `rx.m` 中 LLR 和交织索引 | 待实现 | 未实现 |
| LDPC | MATLAB QC-LDPC | 待实现 QC/NMS RTL | 未实现 |
| MID 融合 | `fuse_channel.m` | 已完成 | 已仿真/综合 |

## 已完成的前端初版

`rtl/cofdm_stf_sync_frontend.sv` 实现了 MATLAB 同步器的流式核心：

```text
16 点延迟线
→ 64 点滑动复相关 P
→ 滑动 E1/E2
→ |P|²·100 > E1·E2·40
→ 连续命中计数
→ sync_hit 和相关值输出
```

该版本不使用除法器，适合 FPGA；相关值已经接入独立的 16 轮 CORDIC 估计粗频偏，
输出 Q0.32 相位增量驱动 NCO。当前模块使用 16 bit 输入、40 bit 累加器，参数可调整。Icarus
仿真和 Verilator lint 已通过：

```text
PASS STF streaming sync index=86 corr=30400000
```

## 定点接口建议

输入 ADC/IQ 建议先统一为有符号 Q1.15 或 Q2.14。同步相关的乘积为约 32 bit，
64 点累加使用 40 bit；进入 FFT 前统一缩放，避免不同模块各自改变小数位。
建议每个 RTL 模块的接口文档同时记录：

```text
数据宽度、二进制小数位、有效/帧边界、溢出策略、延迟、背压行为
```

## 后续实现顺序

1. 继续实现 LTF 峰值搜索和两个 LTF 的细 CFO。搜索范围限制在 MATLAB 的
   `nominal±96`，硬件采用滑窗相关峰值，不保存整段捕获数据。
3. 接入 Xilinx FFT IP，固定 256 点、流式架构、CP 去除由地址计数器完成。
4. 实现 LS 信道估计和 Q 格式复数均衡；先覆盖 `channelEstimator='ls'`，
   再加入 FIR5/FIR7 平滑。
5. 实现导频相位/斜率跟踪、QPSK 软解调和交织地址 ROM。
6. 最后实现 QC-LDPC。先综合 27 路校验节点并行的 NMS 基线，再根据
   XC7Z020 的 DSP/BRAM/Fmax 结果调整并行度。

前端参考工程 `vivado/cofdm_frontend_ref/` 已用 XC7Z020 实际综合：2017 LUT、
2004 FF、164 LUTRAM、29 DSP48E1，122.88 MHz 下 WNS=+2.324 ns、TNS=0。
该工程包含 STF 同步、16 轮共享 CORDIC 角度估计和 NCO 旋转，不能代表 FFT、
均衡或 LDPC 的资源。

## 集成原则

- 未完成模块先放在独立 testbench，不修改已通过的 MID Vivado 基线。
- MATLAB、Python 整数参考和 RTL 三者必须对同一组定点向量一致。
- 先保证一拍一个复采样的吞吐，再考虑减少延迟；长乘加路径优先流水化。
- 任何模块加入完整 top 前，记录 LUT、FF、BRAM、DSP、Fmax 和 FIFO 深度。
