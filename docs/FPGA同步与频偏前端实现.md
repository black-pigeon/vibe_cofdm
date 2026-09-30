# FPGA 同步与频偏前端实现

本文档记录 XC7Z020CLG400-2、Vivado 2022.2 的当前实现基线。采样率为 15.36 MHz，PL 时钟为 122.88 MHz（8 倍采样时钟），LTF/FFT 长度为 256。

## 1. 数据路径

```text
ADC/IQ
  -> cofdm_stf_sync_frontend
  -> cofdm_cfo_angle_estimator
  -> cofdm_cfo_nco_rotator       (粗频偏补偿)
  -> cofdm_ltf_search_ctrl
  -> cofdm_ltf_time_matcher_tdm  (LTF 精同步，低资源基线)
  -> cofdm_pre_fft_replay       (BRAM 回放，恢复已过去的训练符号)
  -> CP 去除/XFFT
  -> cofdm_ltf_fine_cfo_chain    (双 LTF 精频偏，可选集成)
  -> cofdm_cfo_control            (粗、精 CFO 增量闭环)
```

STF 检测只产生候选事件，不能单独作为帧确认。LTF 匹配峰值、分数门限和后续 LTF 频域一致性共同作为捕获确认条件。`cofdm_ltf_sync_capture_frontend` 将 STF 命中、LTF 搜索调度和匹配结果连成一个接口，输出 `ltf_peak_valid/index/score`。

`cofdm_sync_ltf_cfo_top` 是当前闭环入口。默认 `ENABLE_FINE_CHAIN=0` 时，
`fine_valid/fine_phase_inc` 由后级提供；设置 `ENABLE_FINE_CHAIN=1` 后，
它直接接收 XFFT 的 `valid/last/IQ` 流和旋转参考，内部实例化
`cofdm_ltf_fine_cfo_chain`，把 `phase_inc_valid/phase_inc` 接回
`cofdm_cfo_control`。粗频偏和双 LTF 精频偏因此使用同一个 NCO。
`fft_out_ready` 在集成模式下恒为 1，XFFT 的气泡由 adapter 按
`valid&&ready` 计数，不以时钟数猜测 FFT bin。

## 2. 低资源 LTF 匹配器

`cofdm_ltf_time_matcher_tdm.sv` 采用两阶段 FSM：

1. `CAPTURE`：把 `NFFT+CANDIDATES-1` 个复采样写入短缓存；
2. `SCAN_REQ/SCAN_ACC/MAC_ADD`：逐候选、逐采样读取缓存，使用一个共享复乘器完成 `conj(template)*sample` 累加；乘法和 48 bit 累加分成两个时钟，满足时序；
3. `EVAL/EVAL2`：使用 `|Re|+|Im|` 的 L1 相关幅度近似，保存最大候选并给出峰值索引。

搜索调度器通过 `search_done` 接收 matcher 的峰值或超时事件，释放本次
事务占用。这样下一帧的 STF 候选可以重新进入 LTF 搜索；搜索进行期间
出现的 STF 相似峰只被忽略，不会把正在执行的匹配误判为调度错误。

默认 17 个候选窗口时，每个候选需要约 3×256 个 PL 时钟，完整扫描约 13.1k 个时钟，对于 122.88 MHz 时钟约为 107 us。匹配发生在帧级事件，不占用持续数据通路，因此用时换 DSP 是合适的 7020 基线。

匹配器的 `peak_score` 是 L1 相关幅度的移位定标值，不是严格的归一化相关系数。当前 `RAW_SCORE_SHIFT=18`，并关闭能量累加（`TRACK_ENERGY=0`）以消除采样率路径上的长进位链。正式产品应在低速评估阶段增加能量倒数 LUT，或在 MATLAB 中根据 AGC 误差重新标定 `SCORE_MIN`。

## 3. 定点约定

| 信号 | 格式 | 说明 |
|---|---|---|
| ADC/训练序列 IQ | signed Q1.15 | 输入和 LTF ROM |
| 单次复乘 | signed 32 bit | 两个 16×16 实乘结果 |
| 相关累加 | signed 48 bit | 覆盖 256 点累加和 |
| L1 相关幅度 | unsigned 49 bit | `abs(Re)+abs(Im)`，避免平方器 |
| `peak_score` | unsigned Q0.16 定标值 | 仅用于门限和诊断 |
| CFO NCO 增量 | signed 32 bit phase/sample | 与 `cofdm_cfo_control` 一致 |

精频偏链的符号约定为：MATLAB 中 `round(-fineCfoHz/fs*2^32)`，RTL 也输出负号修正量，然后叠加到粗 CFO 增量。

## 4. Vivado 参考综合结果

`matlab/vivado/cofdm_ltf_sync_ref/run_synth.tcl` 已切换为 `CANDIDATES=17 MATCHER_TDM=1`。并行 5 路旧实现综合结果为 122 个 DSP，且 WNS=-13.316 ns；它只作为快速参考，不能用于 7020 最终实现。

LTF 模板已经改为 Vivado `blk_mem_gen` ROM IP。COE 文件为 [cofdm_ltf_template.coe](../vivado/cofdm_ltf_sync_ref/cofdm_ltf_template.coe)，每个 32 位字为 `{Re[15:0], Im[15:0]}`。工程脚本会自动创建 `cofdm_ltf_template_rom_ip`，设置 256×32、单口 ROM、初始化文件和 1 拍读延迟。

低资源版本综合后约 575 LUT、695 FF、4 DSP、1 个 RAMB36 和 1 个 RAMB18，122.88 MHz 下 WNS=+0.561 ns，约束已满足。样本缓存使用显式 `RAMB36E1`，LTF 模板由 ROM IP 实现；`verify_ltf_coe.py` 会检查 COE 与行为级 RTL 的 256 个字逐项一致。

## 5. 验证方法

```bash
matlab/rtl/run_checks.sh
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_sync_ref/run_sim.tcl
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_sync_ref/run_sim_tdm.tcl
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_sync_ref/run_sim_closed_loop.tcl
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_sync_ref/run_sim_pre_fft.tcl
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_sync_ref/run_synth.tcl
```

`run_sim_tdm.tcl` 会使用 COE 初始化的 ROM IP 对 TDM 匹配器做 XSim 验证，当前得到 `idx=110, score=51199`。当前 RTL 对拍覆盖：STF 流式检测、粗 CFO、NCO、LTF 调度、并行/时分复用 LTF 匹配、双 LTF 精 CFO、CFO 自动控制以及 XFFT 前端接口。下一步应把 MATLAB 生成的真实多径、CFO、AWGN 波形导出为定点文件，逐样点对拍 `peak_index`、峰值分数和精 CFO。

`run_sim_closed_loop.tcl` 使用 `tb_sync_ltf_cfo_top`，在 Vivado XSim 中
跑通 `STF candidate -> coarse CFO -> NCO -> LTF peak -> fine CFO event
-> header CRC -> frame_valid`。当前简化训练波形得到 LTF `score=27443`
和帧起点 `103`；这项测试用于检查模块连线和事件时序，不能替代带多径、
CFO 与 AWGN 的灵敏度曲线。

## 6. 后续必须完成的工程化工作

1. 在板级工程中保留 RAMB36E1 和 ROM IP 的复位、读写时序约束，并确认实现报告与综合报告一致；
2. `cofdm_ltf_search_ctrl` 已在 matcher 峰值/超时后释放事务锁存，下一帧可重新捕获；仍需把 `abort` 接入该清除路径；
3. 由 LTF 峰值和双 LTF 频域一致性共同确认帧，避免 STF 噪声峰误触发；
4. 对 `SCORE_MIN` 做 AGC 偏差、频偏、多径和低 SNR 扫描；
5. 在 XFFT 输出后接 LTF 信道估计、Header 解调和 CRC，再进行全链路误包率测试；
6. 约束 AXI-Stream 的 `tvalid/tready` 和采样时钟域，避免当前参考工程中“每 8 个 PL 时钟一个采样”的假设泄漏到产品接口。

统一 pre-FFT 顶层为 `cofdm_sync_pre_fft_frontend.sv`。它把同步顶层、
NCO、LTF matcher、回放 BRAM 和 XFFT 输入前的符号接口连成一个模块。
在 XC7Z020 综合基线中，LUT 2906、FF 2656、DSP48E1 33、RAMB36E1 9、
RAMB18E1 1，122.88 MHz 下 WNS `+0.561 ns`、TNS `0`。当前报告中的
约束警告来自参考 XDC 对顶层端口使用 `set_input_delay`，并非数据路径
时序失败；板级工程应按实际 ADC/AXI 时钟重新约束。
由于 TDM LTF 搜索需要约 107 us，峰值结果产生时原始训练符号已经经过。
`cofdm_pre_fft_replay` 用环形 BRAM 保存校正后的 IQ，收到合法 LTF 峰值后
回放 `LTF1 CP+256`、`LTF2 CP+256` 和配置的数据符号。输出
`fft_symbol_start` 标记 CP 首样点，`fft_symbol_index/kind` 携带符号元数据，
可以直接接 `cofdm_fft_stream_frontend` 的 `in_*` 端口。默认 8192 深度、
32-bit IQ 存储使用 8 个 RAMB36E1，避免综合成巨大 LUT 阵列。

对于数据长度远大于 8192 个采样点，不能继续把 `DATA_SYMBOLS` 作为回放
缓存的静态容量。`cofdm_pre_fft_stream_replay` 已提供有限深度环形方案：
`replay_symbol_count` 只决定输出持续时间，BRAM 深度仍只由“捕获判决延迟
+训练前导长度+下游停顿裕量”决定。15.36 MS/s 下，107 μs 的 TDM 搜索约
占 1644 个采样，再加 576 个双 LTF 样点和余量，4096 或 8192 深度足够作为
前端历史缓存；1500 个 OFDM 符号不会要求 1500 倍 RAM。长帧应在 Header
解出长度后装载 `replay_symbol_count`，或者由帧尾事件终止输出。

长帧统一入口为 `cofdm_sync_pre_fft_stream_frontend`。它与固定短帧入口
使用相同的同步链路，但把运行时 `replay_symbol_count` 传给环形回放器，
并输出同样的 XFFT 前 AXI-Stream 接口。固定入口仍保留用于训练和短帧回归。

环形方案有一个必要条件：XFFT 输入不能无限期反压。如果 `out_ready` 长时
为 0，写指针会追上读指针并覆盖尚未输出的数据。工程实现应让 XFFT 前端
保持可接收，或在两者之间增加 AXI FIFO，并按最长停顿重新计算 BRAM 深度。
CLOSED_LOOP_PREFFT：`run_sim_pre_fft.tcl` 进一步验证同步结果到 BRAM 回放
的统一链路，输出 864 个样点（3 个 288 样点符号）和 3 个符号起始标记。

### 超长帧的实际使用约束

`cofdm_pre_fft_replay` 仍是固定短帧回归模块：`DATA_SYMBOLS` 在综合时决定
总输出长度，若把它用于超长帧，缓存容量会随帧长增长。产品入口应使用
`cofdm_sync_pre_fft_stream_frontend`，其 `replay_symbol_count` 是运行时的
符号数，`replay_extend_valid` 可以在 Header 解码完成后把初始的
“LTF+Header”长度扩展为完整 PHY 长度。例如：

```text
捕获启动：replay_symbol_count = 3
Header CRC 正确：replay_symbol_count = 3 + payload_symbols,
                 replay_extend_valid = 1（一个时钟脉冲）
```

环形缓存的安全深度按样点计算，而不是按整帧计算：

```text
BUFFER_DEPTH >= ceil((捕获判决延迟 + 前导长度 + 最大反压停顿) / 采样周期)
```

本工程 15.36 MS/s、TDM LTF 搜索的基线约为 1644 个样点历史窗口，双 LTF
占 576 个样点，因此 4096 是可工作的起点，8192 给搜索抖动和 FIFO 停顿留出
余量。`out_ready` 长时间为 0 会使写指针覆盖待读数据；需要保证 XFFT 持续
取数，或在回放器后增加 AXI FIFO，并将 FIFO 可容忍的停顿计入上式。

`SYMBOL_INDEX_W` 默认保持 8 位以兼容旧接口。超过 255 个 OFDM 符号的产品
配置应将其设为 16（通常与 `SYMBOL_COUNT_W` 相同），否则样点仍可正确输出，
但符号索引元数据会回绕。计数器使用 32 位样点索引，需在系统级规定帧长和
计数器回绕处理。

当前回归用 2048 深度环形缓存输出 1000 个符号（10000 个样点），并先用
3 个符号启动、再动态扩展到 1000 个符号，结果为：

```text
PASS bounded stream replay symbols=1000 samples=10000
```
