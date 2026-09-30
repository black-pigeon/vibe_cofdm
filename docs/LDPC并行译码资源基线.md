# QC-LDPC 并行译码资源基线

> 评估口径更正：本页历史 `rtl7` CSV 仅量化输入、内部仍使用浮点译码，不能代表 RTL 定点性能。接收机获知定时/CFO/长度，但信道仍由含噪 LTF 估计。修正后的 Q2 译码和完整 MATLAB 链路结果见[完整链路与 LDPC 评估](完整链路与LDPC评估.md)。历史 CSV 保留，复跑请使用新的输出文件名。


本次基线在 XC7Z020CLG400-2、Vivado 2022.2、122.88 MHz 约束下完成。`cofdm_qcldpc_parallel_bank` 复制现有标量分层 NMS 译码器，每个 lane 独立拥有消息 RAM、后验 RAM 和边地址 ROM；上游需要把完整 648 位码字分配给空闲 lane。该基线用于评估复制译码核心的资源和时序，不包含最终的码字调度器、跨 lane FIFO、Payload RAM 和完整 PHY。

运行：

```bash
vivado/cofdm_v2_header_ref/run_synth_qcldpc_parallel_all.sh
```

综合脚本和 RTL：

- `rtl/cofdm_qcldpc_parallel_bank.sv`
- `vivado/cofdm_v2_header_ref/run_synth_qcldpc_parallel.tcl`
- `vivado/cofdm_v2_header_ref/parallel_clock.xdc`

## 综合结果

以下为历史综合后结果；脚本当时未设置 out-of-context，顶层还包含大量 lane I/O。WNS 不是布局布线后的 Fmax，也未验证器件封装 I/O 和完整 PHY 的可实现性。

| 并行 lane | LUT | LUT 占 XC7Z020 | FF | BRAM Tile | BRAM 占用 | DSP48 | WNS | 估算总功耗* |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 3 | 747 | 1.40% | 285 | 7.5 | 5.36% | 0 | +1.802 ns | 0.147 W |
| 9 | 2165 | 4.07% | 855 | 21 | 15.00% | 0 | +1.711 ns | 0.244 W |
| 27 | 6496 | 12.21% | 2565 | 61.5 | 43.93% | 0 | +1.711 ns | 0.502 W |

\* 功耗为无活动向量的 Vivado vectorless 估算，只能用于档位比较，不能替代布局布线和板级功耗测量。

资源随 lane 数基本线性增长，当前 27 路译码器本身仍可通过综合时序，但加入现有 Payload 顶层基线后，粗略资源为：

| 方案 | Payload 顶层已有 | 叠加并行译码器 | 粗略合计 | 说明 |
|---|---:|---:|---:|---|
| 3 lane | 12415 LUT / 33 BRAM / 79 DSP | 747 LUT / 7.5 BRAM | 13162 LUT / 40.5 BRAM / 79 DSP | 资源最省，持续吞吐不足 |
| 9 lane | 12415 LUT / 33 BRAM / 79 DSP | 2165 LUT / 21 BRAM | 14580 LUT / 54 BRAM / 79 DSP | 高 SNR 接近目标档位 |
| 27 lane | 12415 LUT / 33 BRAM / 79 DSP | 6496 LUT / 61.5 BRAM | 18911 LUT / 94.5 BRAM / 79 DSP | 中等迭代次数下吞吐较好，需检查完整布局拥塞 |

合计只是把独立综合结果相加，完整顶层还会增加 lane 调度、输入缓存、输出仲裁和布线资源，不能直接当作最终实现结果。

## 吞吐决策

一个 648 bit 码字在当前空口映射中的平均到达间隔为 3888 个 122.88 MHz 时钟。标量译码器一轮约 23008 个时钟，12 轮最坏约 258550 个时钟。因此：

- 3 lane 适合验证接口和低资源功能闭环，不能持续跟上高 SNR 空口；
- 9 lane 是第一候选，适合平均 1～2 轮的高 SNR 场景，但不能覆盖低 SNR 的长迭代尾部；
- 27 lane 能覆盖更多中等迭代场景，但仍不能保证 12 轮最坏情况，且完整实现要重点检查 BRAM 布局和时钟拥塞。

下一步应先实现一个 round-robin 码字调度器和每 lane 一个小 FIFO，使用真实译码完成时间测量，而不是只依赖独立 bank 的理论复制比例。低 SNR 时应由输入队列水位触发 PHY 节流或丢包/重传策略。

## 2048 字节 Payload 的 1000 帧临界区扫测

文件：[payload_sweep_2048_1000f_345.csv](../results/payload_sweep_2048_1000f_345.csv)。这是已知同步和 CFO、由含噪 LTF 估计信道的历史输入量化/浮点内部译码对照，不包含捕获和 V2 Header 失败。

| SNR | PER | 95% 区间 | 平均迭代 | 需要 lane | Payload Goodput |
|---:|---:|---:|---:|---:|---:|
| 3 dB | 0.976 | 0.964–0.985 | 5.39 | 32 | 0.208 Mbps |
| 4 dB | 0.263 | 0.236–0.291 | 3.10 | 19 | 6.397 Mbps |
| 5 dB | 0.016 | 0.009–0.026 | 2.21 | 14 | 8.541 Mbps |

结果表明 2048 字节长包的 Payload-only 工作区间大约在 4～5 dB：5 dB 时已经接近理想空口速率，但仍有 1.6% 包错；3 dB 和 4 dB 分别受到大量 LDPC 失败影响。完整同步链路还会叠加 STF/LTF 捕获损失，因此不能把 5 dB 直接作为整机灵敏度指标。

## 2026-09-30：含 FIFO 调度器和 BRAM 复制的实测综合

本轮把码字 FIFO、输入顺序恢复和译码 lane 放在同一个 `cofdm_qcldpc_codeword_scheduler` 顶层中综合，FIFO 存储改为每个 lane 一份独立的同步双口 BRAM。这样每个译码 lane 可以独立读一个码字，避免共享数组产生的多路动态读 mux。脚本为 `vivado/cofdm_v2_header_ref/run_synth_qcldpc_scheduler.tcl`，报告位于 `vivado/cofdm_v2_header_ref/reports_qcldpc_scheduler/L*`。

| lane | LUT | LUT 占用 | FF | BRAM Tile | BRAM 占用 | DSP48 | WNS @122.88 MHz | 结论 |
|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 3 | 902 | 1.70% | 429 | 10.5 | 7.50% | 0 | +1.898 ns | 可作为低资源验证档 |
| 9 | 2673 | 5.02% | 1208 | 39 | 27.86% | 0 | +1.535 ns | 当前 7020 的推荐基线 |
| 27 | 58181 | 109.36% | 4045 | 162.5 | 116.07% | 28 | +0.730 ns | 不可实现，综合已退化为大量 LUT RAM |

这里的 27 路结果说明，完整调度器的 FIFO 复制成本随 lane 数增加得更快：每路不仅复制译码器，还复制整个码字缓存。它不能作为 XC7Z020 的量产方案。9 路在综合层面留有约 72% BRAM 和 95% LUT 余量给 XFFT、同步、均衡和协议接口，但最终仍需完整顶层布局布线后复核。

调度器回归已覆盖 8 个连续码字，并验证 FIFO 深度为 3 时的多次读写槽位回绕；非 2 的幂 FIFO 深度在 RTL 中使用显式 `FIFO_DEPTH-1` 回绕。当前码字输入、顺序输出、syndrome 提前退出和长包队列行为均通过 `bash rtl/run_checks.sh`。

下一步不再增加完整标量 lane，而是把 9 路作为性能基线，设计共享 BRAM 的 QC 子块并行译码器。目标是用 9/27 个变量节点或校验节点处理单元服务多个码字，同时保留有界 FIFO、顺序恢复和 syndrome 提前退出，从而把 BRAM 复制开销变成可控的 bank 化存储。
