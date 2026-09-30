# XC7Z020 的 QC-LDPC 并行译码器设计

## 结论

可以实现。当前工程使用的是一个 `12 × 24` 的 QC 基矩阵，循环因子 `Z=27`，因此码字为 `(648,324)`，共有 324 个校验方程和 2376 条实际边。现有 `cofdm_qcldpc_648_decoder.sv` 已经实现了分层归一化最小和译码、7 bit 消息量化、12 轮上限和 syndrome 提前退出；它的问题是每次只处理一个校验方程中的一条边，主要用于 bit-exact 参考和功能验证。

QC 并行化不会改变编码矩阵，也不会自动提高纠错灵敏度。它首先减少译码周期、提高长包持续吞吐；灵敏度仍由 LLR 标定、信道估计、量化位宽、NMS 参数和迭代上限决定。这样可以把吞吐优化和灵敏度优化分别验证，避免把两种收益混在一起。

## 两种“9 路”必须区分

当前已经综合过的 9 路是 **9 个完整标量译码器**。它们同时服务 9 个不同码字，单个码字仍然需要约 23008 个时钟完成一轮。该方案高 SNR 时可满足连续输入，但消息 RAM、后验 RAM 和码字缓存都被复制。

后续要实现的是 **一个 QC 译码器内的 9 个子块处理单元**。它按 9 个循环位置并行处理同一个 QC 层，多个码字通过输入 FIFO 轮转进入同一个共享处理阵列。它同时降低单码字延迟和存储复制量，是 7020 上更有价值的结构。

## 推荐第一版：9 个处理单元、3 个位置组

每个 QC 校验层包含 27 个实际校验方程。第一版使用 9 个处理单元，每个时钟组处理 9 个循环位置，因此一个 QC 层分为 3 个位置组：

```text
for layer = 0..11                 // 12 个基矩阵行
  for group = 0..2                // 每组 9 个循环位置
    for edge = 0..degree(layer)-1 // 每行 7 或 8 条基矩阵边
      读取 9 个 q = LLR/post - old_message
      并行更新 9 组 sign、min1、min2
    for edge = 0..degree(layer)-1
      并行计算 9 个新 message
      并行回写 9 个 post 和 9 个 message
```

第一遍保留当前标量 RTL 的 `q`、符号、最小值和次小值逻辑；第二遍保持 `alpha=3/4`、最近舍入、7 bit message 饱和及 9 bit posterior 饱和规则。这样 MATLAB、现有标量 RTL 和 QC RTL 可以使用完全相同的算术参考。

## BRAM 银行组织

不能把 648 个 posterior 放成一个多读口数组，否则 Vivado 会生成大规模 LUT mux。推荐按循环位置模 9 建立 9 个银行：

```text
bank       = variable_position mod 9
bank_addr  = variable_block * 3 + floor(variable_position / 9)
```

一个 9 位置组对任意循环移位 `s` 都会在 9 个银行各产生一次访问，因为 `(i+s) mod 9` 是排列。这样每个 edge 只需要每个 bank 一次读和一次写，移位由固定连线/小型交换网络完成，不需要运行时多读口 mux。

消息 RAM 也采用相同的 9 银行布局：每个基矩阵边保存 27 个 message，按 `check_position mod 9` 分成 9 个银行，地址为 `base_edge_index*3 + group`。基矩阵只需保存 12×8 项的 `{valid, variable_block, shift}`，不再为 2592 个检查位置保存完整地址。

输入码字先写入共享的 posterior 银行；译码过程中不复制完整码字到每个 lane。输出阶段按 324 个信息位顺序读出，交由现有 payload CRC/帧状态机处理。

## 时序和吞吐目标

当前空口每个 648 bit 码字的到达间隔约为 3888 个 122.88 MHz 时钟。QC9 第一版的目标不是宣称固定周期，而是通过综合和仿真确认以下门槛：

| 项目 | 第一版门槛 |
|---|---:|
| 时钟 | 122.88 MHz |
| 一轮译码 | 小于 1500 个时钟，包含 BRAM 读写流水线 |
| 12 轮最坏 | 小于 18000 个时钟，仍保留失败输出 |
| 高 SNR 1～2 轮 | 持续吞吐达到或超过 8.68 Mbps 空口目标 |
| syndrome | 每轮完整检查 324 个方程，不能只检查抽样方程 |
| 译码结果 | 与现有标量 RTL 逐个 posterior、message 和 decode status 对拍 |

如果一轮实际周期接近 1000～1500 个时钟，1～2 轮的平均服务能力会明显高于当前 9 个标量核的长包基线；低 SNR 的 12 轮尾部仍需要 FIFO 水位、PHY 节流或 ARQ 处理，不能假设任何并行结构都能覆盖最坏情况。

## 资源目标

当前 9 路标量调度器单独综合为 2673 LUT、1208 FF、39 BRAM Tile，WNS 为 +1.535 ns，但它复制了 9 份码字缓存。QC9 的目标是把额外资源控制在完整 PHY 可接受范围内：

- 不复制 9 份完整码字 RAM；
- 不使用 27 路完整标量译码器；
- 处理单元和交换网络优先使用 LUT/CARRY，不占用 DSP48；
- 消息、posterior、边参数优先映射到 BRAM；
- 第一版综合目标为额外 LUT 小于 15k、BRAM 小于 45 Tile，并在完整 PHY 中保留时序余量。

这些是工程门槛，不是已经得到的综合结果；最终数值必须由 Vivado 综合、布局布线和功耗报告确认。

## RTL 实施顺序

1. 从 `+cofdm/ldpc_code.m` 自动生成 12×8 基边 ROM，保留当前 2592 项 edge ROM 作为参考。
2. 实现 9-bank posterior/message RAM，并单独验证每个 QC shift 的地址排列无冲突。
3. 实现 9 个 PE 的第一遍 min/sign 累积和第二遍 NMS 更新。
4. 加入 12 层控制、位置组控制、同步 BRAM 延迟补偿和边界饱和。
5. 加入每轮完整 syndrome 扫描及现有 SNR 无关提前退出。
6. 使用 MATLAB 导出的 8 个既有 QC 向量，逐个比较 648 个 posterior 和 324 个 syndrome。
7. 做随机 LLR、单 bit 错误、多 bit 错误、不可收敛码字和随机反压测试。
8. 接入 `cofdm_qcldpc_codeword_scheduler` 的有界 FIFO，测量混合迭代次数下的最大水位和持续吞吐。
9. 最后才接入 `cofdm_payload_codeword_bridge` 和完整 PHY 顶层。

## 灵敏度验证边界

QC 并行 RTL 必须先用与标量译码器相同的 7 bit LLR 和 NMS 参数对拍，确认并行化没有引入误码。随后再单独比较：

- 7 bit、8 bit LLR 的 FER/PER；
- `alpha=3/4` 与 offset min-sum；
- 6、8、12 轮上限；
- 双 LTF 平均信道估计和导频跟踪开关；
- 4、5、6 dB，36、257、2048 字节，至少 1000 帧。

只有在相同 LLR 输入下 QC RTL 与标量译码结果一致，才能把后续性能差异归因于吞吐结构或接收机算法，而不是 RTL 地址错误。

## 2026-09-30：同步 BRAM QC9 实现结果

实现文件为 `rtl/cofdm_qcldpc_qc9_bram_decoder.sv`，RAM 模板为
`rtl/cofdm_qcldpc_sync_ram.sv`。该版本保留 9 个 QC 位置处理单元，但把
posterior 和 message 分别拆成 9 个同步读写 bank；Q 计算、最小值搜索、写回和
syndrome 访问之间增加了地址/算术流水级，避免大数组异步读被综合成 LUT mux。
地址计算还将固定的 `/9`、`%9` 改为有界比较和预计算 bank 表。

在 8 组 MATLAB 导出向量上，BRAM 版本逐比特输出、译码状态和迭代次数均通过：

| 条件 | 一轮提前退出 | 12 轮上限 |
|---|---:|---:|
| BRAM QC9 时钟数 | 4789 | 39637 |
| 标量参考时钟数 | 约 23316 | 约 258550 |
| 单码字周期改善 | 约 4.9 倍 | 约 6.5 倍 |

这组周期包含同步 BRAM 延迟补偿、完整 12 层 syndrome 扫描和输出读出，因此比纯
异步 QC9 参考核心（1573/8173 周期）更保守，但可以用于真实 FPGA 资源评估。
按 122.88 MHz 计算，译码器服务能力约为 25.7 kcodeword/s（1 轮）或
3.1 kcodeword/s（12 轮），对应 324 bit 信息位约 8.3 Mbps 或 1.0 Mbps；长包
持续吞吐还要扣除输入装帧、空口到达间隔以及低信噪比的迭代尾部。

Vivado 2022.2 对 `xc7z020clg400-2` 的 out-of-context 综合结果如下，报告由
`vivado/cofdm_v2_header_ref/run_synth_qcldpc_qc9_bram.tcl` 生成：

| 资源/时序 | 结果 |
|---|---:|
| LUT | 3713（约 7.0%） |
| FF | 2426（约 2.3%） |
| RAMB18 | 18（约 6.4%） |
| DSP48 | 0 |
| WNS @122.88 MHz | +0.624 ns |

因此该 QC9 版本已经满足当前时钟约束的综合级门槛，并且没有把大状态数组退化
成 LUT RAM。这里的 WNS 仍是综合后的 out-of-context 结果，完整 PHY 顶层布局布线
后还需要重新检查。后续若要继续提升吞吐，应优先复用这套 bank 和流水结构，增加
处理单元或采用双码字交错；不要重新复制 9 份完整标量译码器。

## 实际链路解码性能验证

使用 R2020b MATLAB 完整 PHY 链路，以量化 `q2_nms12` 作为 QC9 的算法对应项，
对 36、257、2048 字节 payload，在 4、5、6 dB 各运行 50 帧。原始结果见
[full_link_ldpc_qc9_validation_50f.csv](../results/full_link_ldpc_qc9_validation_50f.csv)，
按 RTL 实测周期换算后的结果见
[qc9_decode_performance_50f.csv](../results/qc9_decode_performance_50f.csv)。

RTL 测试得到的周期关系为：
`cycles_per_codeword = 1621 + 3168 × iterations`。因此平均迭代次数可以直接
换算为 QC9 的服务吞吐；这个换算包含 BRAM 译码和输出固定开销，但不包含完整 PHY
顶层的排队延迟。

| Payload | SNR | PER | 平均迭代 | QC9 信息服务率 | MATLAB 空口有效率 | 单 QC9 是否跟得上 |
|---:|---:|---:|---:|---:|---:|:---:|
| 36 B | 4 dB | 0 | 2.44 | 4.26 Mbps | 2.71 Mbps | 是 |
| 257 B | 4 dB | 6% | 2.75 | 3.85 Mbps | 6.18 Mbps | 否 |
| 257 B | 6 dB | 0 | 1.59 | 5.97 Mbps | 6.58 Mbps | 否 |
| 2048 B | 4 dB | 14% | 2.93 | 3.65 Mbps | 7.47 Mbps | 否 |
| 2048 B | 5 dB | 0 | 2.14 | 4.73 Mbps | 8.68 Mbps | 否 |
| 2048 B | 6 dB | 0 | 1.69 | 5.72 Mbps | 8.68 Mbps | 否 |

这说明当前单个 QC9 核虽然比标量核快很多，但对于高速率长包仍然是吞吐瓶颈，
即使 SNR 提高到 6 dB 也不能持续跟上 8.68 Mbps 空口速率。短包因为空口到达率
较低可以满足。下一步应优先验证两个 QC9 处理实例的交错调度，或把同一 bank 结构
扩展到 18/27 个处理单元；同时加入有界输入 FIFO，测量实际队列水位，而不能只看
单码字平均迭代次数。
