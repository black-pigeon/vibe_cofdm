# 完整链路测试与 LDPC 选型记录

## 测试范围

本轮测试覆盖两个层次：

1. `run_full_link_ldpc_comparison.m` 使用同一组随机 IQ，经过 MATLAB 的同步、粗/细频偏补偿、双 LTF 信道估计、导频跟踪、均衡和 LLR 生成，再用多个译码器重复译码。接收机没有获得发送端的定时、频偏或信道真值。这个结果可以比较译码器，但仍属于 MATLAB 前端，不是 FPGA 全链路 PER。
2. `tb_phy_rx_v2_payload_top.sv` 使用真实导出的 IQ，通过 Vivado XFFT、RTL 同步和 Payload 后端，检查输出字节、CRC、padding 和 LDPC 状态，并把每个 RTL LLR 写入 `rtl_llr.txt`。随后 `verify_full_link_llr.m` 可以使用与 RTL 相同的 Q2 译码规则复核 LLR。

复现实验：

```bash
/opt/Polyspace/R2020b/bin/matlab -singleCompThread -batch \
  "run_full_link_ldpc_comparison([36 257 2048],[4 5 6],100,'results/full_link_ldpc_100f.csv')"
/opt/Polyspace/R2020b/bin/matlab -singleCompThread -batch \
  "run_ldpc_family_screen(500,[1 2 3 4],'results/ldpc_family_awgn_500f.csv')"
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source vivado/cofdm_v2_header_ref/run_sim_payload_top.tcl \
  -tclargs /tmp/cofdm_link_clean
```

仿真输入由 `export_phy_rx_v2_vectors.m` 生成。每次只回放一个有界帧，长度上限仍是 2048 字节；这验证了当前实现的缓存和协议边界，不代表无限长度流式接收。

## 当前译码器的实测结论

`q2_nms12` 是当前 RTL 的对应模型：输入先执行 `round(4*LLR)` 并饱和到 ±63，再按 Q2 量化的归一化最小和译码，归一化因子为 3/4，最多 12 轮，满足校验后提前结束。旧的 `rtl7` 结果只把输入截成整数、内部仍用浮点，不能作为 FPGA 性能结果；新脚本已经修正这一点。

在完整 MATLAB 前端、相同 IQ 的 100 帧对比中：

| Payload/SNR | 浮点 NMS 12 | Q2 NMS 6 | Q2 NMS 12 | Q2 NMS 20 | Q2 alpha=1/2 12 |
|---|---:|---:|---:|---:|---:|
| 257 B / 6 dB | 0% | 0% | 0% | 0% | 13% |
| 2048 B / 4 dB | 13% | 48% | 15% | 10% | 100% |
| 2048 B / 5 dB | 0% | 2% | 0% | 0% | 100% |
| 2048 B / 6 dB | 0% | 0% | 0% | 0% | 50% |

长包在 4 dB 的结果说明 6 轮对 7020 过于激进；12 轮应作为当前最低可靠档，20 轮只在资源允许且低 SNR 目标明确时考虑。alpha=1/2 虽然可能简化乘法，误码明显恶化，不采用。20 轮的收益需要更多帧和真实综合后再决定，不能仅凭 100 帧宣称灵敏度提升。

## 码长和码率筛选

`run_ldpc_family_screen.m` 使用 MATLAB R2020b WLAN Toolbox 的标准 QC-LDPC 矩阵做编码层 AWGN 筛选，结果不等同当前自定义矩阵的 FPGA 对拍。500 帧结果显示：

* 当前 `(648,324)`、1/2 码在 Eb/N0=2 dB 时 NMS BLER 3.6%，3 dB 时 500 帧无块错；这是短包和低延迟的稳妥基线。
* 648、2/3 码率在 Eb/N0=2 dB 仍有 34.4% BLER，3 dB 才降到 0；它适合链路余量充足的高速档。
* 648、1/2 码的 layered BP/OMS 在 2 dB 比 NMS 低，但它们需要更多加法、比较或消息处理；7020 上先保留 NMS，只有实测灵敏度不够时才评估 OMS。
* `(1296,648)`、1/2 在 2 dB 为 1.2% BLER，3 dB 为 0；它的编码增益较好，但消息 RAM、地址 ROM 和译码时间约随码长增加，不能直接接入当前 648 专用 RTL。
* 1296、2/3 在 2 dB 为 22.2%，3 dB 为 0；1296、3/4 在 2 dB 为 86.0%，3 dB 约 1%。高码率方案需要自适应调制编码和更高 SNR，不应作为远距离默认档。
* 1944 长码在本次 1–4 dB 筛选中只显示高 SNR 区间，不能据此认为一定优于 648；它会显著增加 BRAM、缓存和时延，列为后续 MCS 研究项。

当前推荐顺序是：远距离默认使用 648、1/2、Q2 NMS、最大 12 轮和早停；链路余量足够时增加 648、2/3；只有完成 1296 的 QC 地址、BRAM 映射和时序综合后，才引入长码。码率切换必须放入 V2 Header 的 MCS 字段，并由译码器按帧配置，不能只修改 MATLAB 参数。

### 不估计 SNR 的提前退出

译码器不需要计算 SNR，也不需要设置“高 SNR 模式”。每轮完成后直接检查 324 个校验方程：syndrome 全零就立即进入输出状态；syndrome 非零且尚未达到 12 轮就继续；达到第 12 轮仍失败则输出 `decode_ok=0`，交由 Payload CRC 和上层重传处理。这样高 SNR 码字自然只消耗 1～2 轮，低 SNR 码字自动使用更多轮。

RTL 回归已经覆盖两种路径：无错误码字第一轮退出，以及故意不可收敛码字达到 12 轮后失败。测试还检查每次退出前确实完成全部 324 个校验行，没有使用 LLR 门限或 SNR 分支，因此控制逻辑和资源开销保持简单。

## 7020 的实现决策

现有标量译码器一轮约 23008 个 122.88 MHz 时钟，12 轮最坏约 258550 个时钟，而空口每个 648 bit 码字的到达间隔约 3888 个时钟。简单复制 3/9/27 个标量核心可以估算资源，但它们是独立码字复制，不是单码字 QC 并行；现有基线也没有调度器和跨 lane FIFO。因此不能把 27 路的综合数直接当作最终吞吐保证。

下一版 RTL 应保持一套 648 专用地址 ROM，采用 9 路 QC 子块并行作为第一候选：每路处理一个 Z=27 的循环子块，消息和后验使用 BRAM 双口存储，码字之间用 round-robin 调度；输入 FIFO 水位高时允许 PHY 丢弃或请求重传。27 路只在 9 路达不到目标吞吐时评估，因为完整 Payload 顶层已有 33 个 BRAM、79 个 DSP，布局布线和时钟拥塞比独立综合更关键。

当前已加入 `cofdm_qcldpc_codeword_scheduler` 作为过渡实现：它使用有界码字 FIFO，把连续输入的 648 bit 码字分配给空闲标量核心，并按输入顺序恢复输出。2 路仿真已连续处理 3 个码字并通过顺序、CRC 前比特和早停检查。该版本使用同步读口以便推断 BRAM，但多 lane 共享读口仍需在最终版本中改成 Xilinx FIFO/多 bank BRAM，再比较资源和时序。

对 9 路过渡调度器进行了 XC7Z020 综合：WNS 为 +0.538 ns，但 LUT 为 227757（器件的 428%），说明 RTL 数组多读口会生成巨大的选择网络，不能作为最终实现。BRAM 报告为 21 Tile，瓶颈在 LUT 和地址多路复用。下一步应使用 Xilinx XPM/FIFO 或每 lane 独立 BRAM bank，避免一个多读口数组被综合成大规模 mux；在资源修正前不把该调度器接入完整 PHY。

验收门槛应按以下顺序执行：无噪声 MATLAB/RTL 逐点对拍；实际 XFFT 回放的 Header、LLR 数量、CRC 和 payload 字节；4/5/6 dB、36/257/2048 字节各至少 1000 帧；最后才比较 3/9/27 路的实现后 Fmax、BRAM、LUT、功耗和持续吞吐。当前 CSV 的 100/500 帧结果用于方向筛选，不能代替最终灵敏度曲线。
