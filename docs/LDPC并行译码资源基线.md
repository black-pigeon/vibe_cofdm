# QC-LDPC 并行译码资源基线

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

文件：[payload_sweep_2048_1000f_345.csv](../results/payload_sweep_2048_1000f_345.csv)。这是已知同步、CFO 和信道条件下的 RTL 7 位 LLR 对照，不包含捕获和 V2 Header 失败。

| SNR | PER | 95% 区间 | 平均迭代 | 需要 lane | Payload Goodput |
|---:|---:|---:|---:|---:|---:|
| 3 dB | 0.976 | 0.964–0.985 | 5.39 | 32 | 0.208 Mbps |
| 4 dB | 0.263 | 0.236–0.291 | 3.10 | 19 | 6.397 Mbps |
| 5 dB | 0.016 | 0.009–0.026 | 2.21 | 14 | 8.541 Mbps |

结果表明 2048 字节长包的 Payload-only 工作区间大约在 4～5 dB：5 dB 时已经接近理想空口速率，但仍有 1.6% 包错；3 dB 和 4 dB 分别受到大量 LDPC 失败影响。完整同步链路还会叠加 STF/LTF 捕获损失，因此不能把 5 dB 直接作为整机灵敏度指标。
