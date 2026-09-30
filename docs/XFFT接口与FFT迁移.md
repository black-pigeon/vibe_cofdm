# 256 点 XFFT 接口与 FPGA 迁移说明

## 当前配置

工程使用 Vivado 2022.2 的 `xfft` 9.1 IP，器件为 `xc7z020clg400-2`：

| 项目 | 配置 |
|---|---|
| 点数 | 256 |
| 通道 | SISO |
| 数据格式 | 定点，输入/输出 I、Q 各 16 bit |
| 架构 | Pipelined Streaming I/O |
| 输出顺序 | Natural order |
| 存储 | Block RAM |
| 缩放 | Scaled，默认 schedule `11,10,10,10` |
| 采样时钟 | 122.88 MHz 约束；ADC 采样率 15.36 MHz 时可用时钟使能或 8 倍并行时钟域设计 |

XFFT 配置通道为 16 bit：bit 0 置 1 表示正向 FFT；bits `[8:1]` 为四级缩放字段。当前常量为 `16'h0157`，对应 `0xAB` 的默认缩放表。后续若修改缩放表，MATLAB golden model 必须同步右移和饱和规则。

## MATLAB 与 XFFT 的对照方式

Vivado 已在生成的 IP 目录中提供 `xfft_v9_1_bitacc_cmodel_lin64.zip`。其中包含 Xilinx 的 bit-accurate C model 和 MATLAB MEX 源码。本工程的 `matlab/tools/setup_xfft_bitacc.m` 会自动解压并编译 MEX，`cofdm.xfft_model` 提供两个引擎：

```matlab
[y0,m0] = cofdm.xfft_model(x,'Engine','matlab');
setup_xfft_bitacc();
[y1,m1] = cofdm.xfft_model(x,'Engine','xilinx');
```

输入 `x` 是与 RTL 相同的有符号 Q1.15 整数采样。`Engine='matlab'` 使用 MATLAB `fft` 加上 XFFT 缩放和量化参考；`Engine='xilinx'` 调用 Xilinx bit-accurate C model，包含 XFFT 的固定点舍入、缩放、旋转因子位宽和溢出行为。两者的差异应作为定点误差预算，而不能直接把未缩放 MATLAB `fft` 与 XFFT 输出比较。

`cofdm.ltf_process` 已使用这两个引擎对双 LTF 做 FFT、信道估计和精频偏计算。当前 MATLAB 对照测试在 12.5 kHz 注入频偏下得到约 12.55 kHz 的估计；FPGA 已有双 LTF 精 CFO 链，并新增双 LTF 初始信道 LS 估计链，后续仍需接入数据符号的导频跟踪和均衡。

## 数据通路

```text
ADC/频偏校正复数采样
        │ in_valid + in_symbol_start
        ▼
CP 去除计数器（32 点丢弃）
        │ 256 点 AXI-Stream
        ▼
XFFT 256
        │ m_axis_data_tvalid/tlast
        ▼
频域缓存 / LTF 相关 / 均衡
```

`cofdm_fft_stream_frontend.sv` 负责 CP 去除、XFFT 配置握手、输入 `TREADY` 反压和输出端口映射。输入复数按 `{imag,real}` 打包。不能按固定延迟或每拍输出假设 FFT 结果；必须在 `m_axis_data_tvalid` 下计数，并用 `m_axis_data_tlast` 标记一个 256 点符号结束。

## 仿真与综合结果

已知测试波形包含 32 点 CP 和 256 点有效数据，XSim 验证：

```text
输入 FFT 样点     256
输出 FFT 样点     256
TLAST 次数        1
FFT overflow      0
```

XC7Z020 综合资源：

```text
LUT       2343
FF        4037
RAMB18    2（1 个 Block RAM tile）
DSP48E1   9
WNS       +1.559 ns @ 122.88 MHz
TNS       0 ns
```

该结果只包含 XFFT 和 CP/AXI 外围；新增的双 LTF 信道估计 RTL 已完成独立仿真，尚未并入该 XFFT top 的端到端数据符号均衡、软解调和 LDPC。

## 接入后级时的注意事项

1. XFFT 的输出可能存在气泡，后级 FIFO 必须按 `valid/ready` 工作。
2. `TLAST` 是唯一可靠的符号边界，不能用固定拍数替代。
3. `m_axis_data_tuser` 当前保留为 IP 输出，后续可用于传递 XK 索引或符号号。
4. FFT 缩放会改变 LTF、导频和数据的绝对幅度；信道估计与 LLR 应采用相同定点比例，或在 FFT 后增加统一的幂次缩放。
5. 当前 XFFT 使用 122.88 MHz 时钟约束。若 ADC 仍以 15.36 MHz 单流输入，可以在 AXI 外围使用 `sample_enable`；如果后续需要满速连续吞吐，建议以 122.88 MHz 作为 PHY 内部时钟。

## 与 LTF/细频偏的关系和当前完成状态

XFFT 是后续 LTF 处理的基础。当前工程已经完成 CP 去除/XFFT 外围、双 LTF 细频偏链以及独立的双 LTF 初始信道 LS 估计；数据符号的导频跟踪、软解调和 LDPC 仍未接入统一 top。当前捕获控制器中的 `ltf_peak_valid/score/index`、`fine_cfo_valid` 仍然是外部事件输入。

正确的接收顺序是：

1. STF 相关产生候选并估计粗 CFO；
2. 粗 CFO NCO 校正后的候选窗口进行 LTF 精定时/相关确认；
3. 从已确认的 LTF1、LTF2 分别去 CP 后进入 XFFT；
4. 用两个 LTF 频域结果估计细 CFO 和初始信道；
5. 锁存细 CFO 并更新 NCO，再处理 Header 和数据符号。

下一步是在现有 `cofdm_ltf_channel_chain` 后加入 200 个有效子载波的导频相位跟踪、匹配滤波 LLR 和 Header 解码，再把 `ltf_peak_*`、`fine_cfo_valid` 接到统一捕获控制器。双 LTF 频域累加器已经由 `cofdm_ltf_fine_cfo_chain` 完成。
