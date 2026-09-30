# Payload 译码阶段与 XC7Z020 基线

当前频域链路的 `cofdm_llr_packetizer` 已完成有效载波重排、QPSK I/Q 展开、符号内反交织和 648 位码字边界标记。它输出的是连续码字顺序的 Payload LLR，后面不能再次串接同一个 384 位反交织器。

本阶段新增：

```text
payload LLR
  -> cofdm_payload_codeword_bridge
       （一次只接收一个648位码字，反压前端）
  -> cofdm_qcldpc_648_decoder
       （QC-Z=27，分层 normalized min-sum）
  -> 324个信息位
  -> cofdm_payload_postprocess
       （解扰、CRC32、信息填充检查、字节缓存）
  -> payload byte valid/ready
```

`cofdm_qcldpc_edge_rom.sv` 是由 `tools/generate_qcldpc_rom.py` 根据
`+cofdm/ldpc_code.m` 生成的边地址 ROM。每个校验行最多 8 条边，ROM 记录变量节点地址和行尾标志；这样译码器不在运行时实现 12×24 基矩阵的乘法和取模。

译码器采用单个校验行时分复用：

1. 同步读取一条校验行的边，计算所有外信息的符号、最小值和次小值；
2. 再次读取同一行，写回归一化最小和消息及后验 LLR；
3. 完成 324 个校验行后计算 syndrome；
4. syndrome 为零时提前结束，否则最多 12 轮；
5. 输出前 324 个信息位。

输入接口为 7 位有符号量化 LLR。当前 `cofdm_matched_llr` 已输出整数 LLR，
因此集成路径 `cofdm_payload_rx` 的默认 `INPUT_SHIFT=0`，直接饱和到 ±63；
`INPUT_SHIFT` 仍可作为参数用于 SNR 扫描，但不能未经对拍就右移 6 位。独立
`cofdm_payload_codeword_bridge` 保留 16 位输入时的默认右移 4 位，直接接 7
位量化输入时必须显式设为 0。

## 与现有接收链的连接

`cofdm_phy_rx_v2_payload_top.sv` 是当前的集成边界。它实例化已有的
`cofdm_phy_rx_v2_top`，保留同步、粗/精频偏、XFFT、双 LTF 信道估计、导频
跟踪、Header Viterbi/CRC 和 Payload LLR 输出；Header 通过后，使用
`payload_bytes` 和 `scrambler_seed` 启动 `cofdm_payload_rx`。数据通路如下：

```text
cofdm_phy_rx_v2_top
  payload_llr + cw_first/cw_last
      -> cofdm_payload_rx（有界 33048 x 7 bit LLR RAM）
          -> QC-LDPC(648,324)
          -> 解扰 + CRC32 + padding
          -> payload_byte_valid/data/last
```

该封装同时保留 `payload_llr_*` 和 `phy_frame_done`，便于先逐 LLR 对拍，再
逐字节对拍。`payload_frame_done` 只在最后一个字节被下游
`payload_byte_ready` 接受后产生；任何 LDPC、padding 或 CRC 错误都会阻止字节
输出并产生 `payload_frame_error`。Payload 缓存是单帧有界资源，最大 2048
字节，不会按随机 IP 包长度无限增长。

## 验证结果

RTL 回归：

```bash
bash matlab/rtl/run_checks.sh
```

已覆盖全零码字单软错误、MATLAB 生成的随机非零码字、码字边界和桥接反压。当前参考仿真通过，单码字在强输入下通常一轮结束；最坏 12 轮的周期仍需用随机低 SNR 向量测量。

独立 XC7Z020CLG400-2 综合脚本：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_v2_header_ref/run_synth_qcldpc.tcl
```

当前独立 LDPC/bridge 综合报告（增加最小值流水级后）：

| 资源 | 使用量 |
| --- | ---: |
| LUT | 约 819 |
| FF | 136 |
| BRAM Tile | 2.5 |
| DSP48 | 0 |
| WNS @122.88 MHz | +1.285 ns |
| TNS | 0 |

该结果满足 122.88 MHz 的独立模块约束，但不等于整机已经满足时序；完整
同步/XFFT/频域基线仍需在同一工程中重新综合。

已增加完整封装的综合脚本：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_v2_header_ref/run_synth_payload_top.tcl
```

该脚本以 `cofdm_phy_rx_v2_payload_top` 为顶层，使用真实 XFFT 9.1 IP
黑盒/综合网表，并将结果写入 `reports_payload_top`。本次 XC7Z020 综合结果为：

| 资源 | Payload 顶层 | 现有 PHY 顶层基线 |
| --- | ---: | ---: |
| LUT | 12,415（23.34%） | 11,789 |
| FF | 11,965（11.25%） | 11,553 |
| BRAM Tile | 33（23.57%） | 15.5 |
| DSP48 | 79（35.91%） | 79 |
| WNS @122.88 MHz | +0.208 ns | +0.208 ns |

其中 Payload 新增的主要 BRAM 是：约 14 个 RAMB36 用于 33048 个 7 位
LLR 有界缓存、1 个 RAMB36 用于 LDPC 消息、1 个 RAMB18 用于后验、1 个
RAMB18 用于 2048 字节缓存。综合报告同时提示部分浅 RAM 被映射为 LUTRAM；
后续可根据布局拥塞和功耗决定是否改成显式 RAMB18/RAMB36 原语。

这里的 WNS 是综合后 `report_timing_summary` 结果，XFFT 本体以 Vivado
IP 综合网表参与；完成布局布线、IO 约束和实际板级时钟树后仍需重新检查。

## 必须继续做的工作

- 用 MATLAB `quantizedDecoder` 导出的多 SNR、随机非零码字对拍，冻结 LLR
  缩放、饱和、舍入和 syndrome 提前结束策略；
- 对 36、257、2048 字节真实 IQ 继续做 Vivado XSim 逐字节回归，并记录
  标量 LDPC 延迟和最大缓存水位；
- 综合 1/3/9/27 路 QC 并行版本，按 7020 的 LUT、BRAM、Fmax 和每码字周期
  选择最终吞吐档位；
- 对完整设计做布局布线和板级时钟约束检查，确认综合阶段的 +0.208 ns WNS
  在实现后仍然成立。

`matlab/rtl/tb/tb_payload_rx.sv` 已覆盖 1、36、37、257、2048 字节，多码字、
CRC/padding 错误、显式中止、错误码字边界和输出反压；当前回归命令最后会
执行该测试。当前尚未宣称持续满速接收：单标量 LDPC 最坏 12 轮约 258k
时钟，持续空口吞吐仍需 3/9/27 路并行或前端分段节流。

多种 SNR 与 Payload 长度的完整链路及 7 位 LLR 对照结果见
[多 SNR、多 Payload 性能评估](多SNR多Payload性能评估.md)。该报告同时给出
100 帧置信区间、端到端同步损失和单标量 LDPC 的服务吞吐估算。

使用 MATLAB 生成的 1 字节真实 IQ（含 25 kHz CFO）运行 Vivado XSim，已通过
`Header OK -> 648 位 LLR -> 1 个 QC-LDPC 码字 -> CRC32 -> 1 字节`，并在
Payload 输出端加入 ready/valid 反压。2048 字节真实 IQ 需要 51 个标量码字，
仿真时间很长；其可变长度、错误注入和反压已由 RTL Payload 回归覆盖，后续
再用它评估整帧延迟和缓存占用。
