# v2 PHY Header FPGA 解码设计

v2 Header 不是 LDPC。当前 MATLAB 定义为：

```text
48 bit 信息字段
  -> CRC16，得到 64 bit
  -> K=7、生成多项式 [171,133] 八进制、R=1/2 卷积码
  -> 6 bit 零尾，54 个 trellis step，108 个编码 bit
  -> 补零到 192 bit（一个 BPSK OFDM 符号）
  -> PRBS x^7+x^4+1，seed=31
```

48 个信息 bit 的字段顺序是：`version[4]`、`mcs/profile[4]`、
`payload_bytes[12]`、`scrambler_seed[7]`、`midamble_code[2]`、保留[3]。
接收端必须先去 Header PRBS，再进行软判决 Viterbi，最后检查 CRC16 和字段
边界。Viterbi 找到一条路径并不代表 Header 合法。

实现文件：

- [`cofdm_v2_header_decoder.sv`](../rtl/cofdm_v2_header_decoder.sv:1)：64 状态、54 步 ACS 和 traceback；
- [`cofdm_v2_header_frontend.sv`](../rtl/cofdm_v2_header_frontend.sv:1)：单个 Header 符号入口；
- [`cofdm_v2_rx_header_path.sv`](../rtl/cofdm_v2_rx_header_path.sv:1)：Header 正确后才释放 Payload LLR。
- [`cofdm_v2_header_decoder_tdm.sv`](../rtl/cofdm_v2_header_decoder_tdm.sv:1)：低资源时分复用版本。

完全展开参考版本综合为 0 DSP、0 BRAM、10969 LUT、5255 FF，122.88 MHz 下
WNS +0.625 ns、TNS 0。最终建议使用 TDM 版本：每拍只更新一个目标状态，并把
ACS 拆为候选计算/比较写回两个时钟阶段，54 步共 6912 个时钟，Header 译码约
56.3 us；TDM 版本综合为 1877 LUT、3225 FF、0 DSP、0 BRAM，WNS +1.375 ns、
TNS 0。它把组合 ACS 换成时分复用，满足 7020 的资源和时序约束。

TDM 版本当前仍把 54×64 bit survivor 作为寄存器数组，后续可显式映射到
RAMB18，进一步减少 FF；完全展开版本保留为 bit-exact 参考模型，不应与 LDPC
译码器同时作为最终实现。

由于 TDM Header 译码需要约 56 us，而后续 OFDM 数据符号会继续到达，不能把
它直接串在实时 LLR 流上而不做控制。实际接入采用两种方式之一：

1. 同步回放器先缓存时域帧，只回放 Header；等待 `header_ok` 后再回放 Payload；
2. 在频域边界加入至少覆盖 56 us 的有界软信息 FIFO，并由 `header_ok` 开闸。

当前工程优先采用第一种方式，因为已有 `cofdm_pre_fft_stream_replay`，不需要为
最大片长增加无限 RAM。Header 解码器的 `payload_bytes`、`scrambler_seed` 和
`midamble_code` 必须在闸门打开前锁存，并经过范围校验。

资源预算集成顶层为 [`cofdm_pre_ldpc_v2_decode_top.sv`](../rtl/cofdm_pre_ldpc_v2_decode_top.sv:1)。Vivado 实测占用 4268 LUT、3926 FF、16 DSP、3 个 BRAM Tile，122.88 MHz 下 WNS +0.683 ns、TNS 0。该数字包含预 LDPC 符号链、XPM FIFO 和 TDM Header 门控，可作为后续接入 QC-LDPC 前的资源基线。

验证命令：

```bash
/opt/Polyspace/R2020b/bin/matlab -batch \
  "addpath('matlab'); export_v2_header_vectors"
cd matlab/rtl && ./run_checks.sh
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_v2_header_ref/run_synth.tcl
```

已经覆盖合法长度 1、257、2048 字节、seed 1/93/127、Midamble 0/1/2、
非法 Header、Payload 门控和 MATLAB `run_variable_tests` 的 2048 字节上限检查。
