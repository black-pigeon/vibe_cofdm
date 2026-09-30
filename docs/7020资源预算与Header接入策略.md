# XC7Z020 资源预算与 Header 接入策略

XC7Z020 只有约 53.2k LUT、106.4k FF、220 个 DSP48E1 和 140 个 36k BRAM
等效块。不能把“能仿真”直接当成“能放进最终设计”。当前资源基线如下：

| 模块 | LUT | FF | DSP | BRAM | 说明 |
| --- | ---: | ---: | ---: | ---: | --- |
| 预 LDPC 符号链 | 2287 | 697 | 16 | 3 | XFFT 后信道/导频/LLR |
| v2 Header 完全展开 Viterbi | 10969 | 5255 | 0 | 0 | 只作黄金参考 |
| v2 Header TDM Viterbi | 1877 | 3225 | 0 | 0 | 推荐实现，WNS +1.375 ns |
| v2 Header TDM + 预 LDPC | 4164 | 3922 | 16 | 3 | 未含 LDPC |
| Vivado 集成顶层实测 | 4268 | 3926 | 16 | 3 | WNS +0.683 ns |

TDM Viterbi 的代价是约 6912 个时钟，也就是 56.3 μs（122.88 MHz）。这段
延迟必须在接收架构中显式处理。推荐的控制顺序是：

```text
时域环形缓存持续接收
  -> 回放 STF/LTF/Header
  -> XFFT + 预 LDPC 输出 Header LLR
  -> TDM Viterbi/CRC/字段检查
  -> 锁存 payload_bytes / seed / midamble_code
  -> 依据 Header 重新定位回放指针
  -> 回放 Payload，进入导频跟踪、LLR、解交织和 LDPC
```

这样 Header 解码延迟不会要求 ADC 停止，也不会为最大 Payload 分配巨大软信息
RAM。若未来要完全连续地从 XFFT 输出 Payload，则需要在 Header 后增加有界 FIFO，
FIFO 深度按 `译码延迟 × LLR到达率` 计算，而不是使用无限缓存。

资源分配原则：

- DSP 优先留给 FFT 外围、复数均衡和 LDPC；Header Viterbi 不使用 DSP。
- Header survivor 和 LLR 存储优先使用 BRAM，避免扩大 LUT/FF。
- LDPC 先采用单/少量 QC 层并行度，综合后再决定是否提高吞吐。
- 所有新增模块必须有独立 Vivado utilization/timing 报告，并把资源预算纳入
  集成门禁。
