# 频域接收机与 MATLAB 对照实现

本文对应 MATLAB `+cofdm/rx.m`、`ltf_process.m` 和 FPGA 的 XFFT 后处理。

## 处理顺序

```text
CP 去除
  → XFFT 256（自然顺序）
  → 双 LTF 频域处理
       Y1/T1、Y2/T2
       H=(H1+H2)/2
       sum(Y2·conj(Y1)·T1·conj(T2)) → 精频偏
  → Header 频域符号
       导频相位/斜率跟踪
       BPSK 匹配滤波 LLR
       LDPC 解码 + CRC
  → 数据符号
       导频跟踪
       QPSK 匹配滤波 LLR
       解交织 → LDPC → 解扰 → CRC
```

MATLAB 的有效子载波是 `-100:-1,1:100`，共 200 个；导频为
`[-91 -65 -39 -13 13 39 65 91]`，DC、保护带不参与信道估计和解调。
MATLAB 的自然 FFT bin 索引为 `mod(k,256)+1`，RTL 使用 0～255 的同一自然
顺序，不能在此处交换正负频率或使用 `fftshift`。

## 已实现的 RTL

- `cofdm_ltf_freq_rom.sv`：由 `training.m` 的两个 ZC 根生成的 256×四路
  Q1.15 频域训练 ROM。200 个有效 bin 有值，其余 bin 为 0。
- `cofdm_ltf_channel_estimator.sv`：接收两个 XFFT 频域帧，按
  `Y*conj(T)` 完成 LTF LS 信道估计，并输出
  `H=(H1+H2)/2`。复乘使用 DSP，信道小数位由 `H_FRAC_BITS` 参数确定；默认
  兼容旧链路的 Q?.15，生产配置可设为 MATLAB `compact_fixed` 的 Q?.14。
  同时计算 `mean(|H1-H2|^2)/2`，以 Q0.`2*H_FRAC_BITS` 输出
  `noise_variance`。均值使用有效载波数的编译期倒数乘法，不综合运行时除法器。
- `cofdm_ltf_channel_chain.sv`：把 `cofdm_ltf_fft_stream_adapter` 和初始
  信道估计串接起来，适合放在 `cofdm_fft_stream_frontend` 后面；同时输出
  `noise_variance`、`noise_valid` 和有效载波计数。
- `cofdm_ltf_rot_rom.sv`：按自然 FFT bin 提供 `T1*conj(T2)`，供双 LTF
  残余 CFO 累加器使用。此前测试中使用的常数 `rot=1` 仅是简化单元测试，
  不能用于两个不同 ZC 根的真实 LTF。

这里的 RTL 信道估计对应 MATLAB 的：

```matlab
H1 = Y1 ./ t.ltf(:,1);
H2 = Y2 ./ t.ltf(:,2);
H  = (H1 + H2)/2;
```

因为 LTF 的幅度为 1，`1/T = conj(T)`，所以 FPGA 不需要除法器或逐 bin
倒数。双 LTF 残余 CFO 则必须先分别去除两个不同的 ZC 序列，再计算
`sum(H2*conj(H1))`；`cofdm_ltf_rot_rom.sv` 正是这一项的定点实现。后续应在此基础上增加 LS 噪声方差估计、FIR/时延投影等低复杂度去噪
模式；第一版先使用 LS，便于 bit-exact 对拍。

## 定点和 XFFT 缩放

XFFT 的缩放表必须同时用于 MATLAB golden model 和 FPGA。`xfft_model.m` 的
MATLAB 引擎执行与 XFFT 相同的 stage scaling 和输出量化；不能把未缩放
`fft()` 的结果直接与 XFFT 输出比较。信道估计的两个输入必须来自相同缩放
的 Y1/Y2，公共缩放会在后续 matched-filter LLR 中抵消或统一纳入 LLR scale。

当前建议的第一版定点链：

| 信号 | 位宽 | 约定 |
|---|---:|---|
| XFFT I/Q | 16 | 有符号 Q1.15 |
| LTF ROM | 16 | 有符号 Q1.15 |
| 复乘积 | 32 | 两个 Q1.15 相乘 |
| 复加结果 | 33 | 防止实部/虚部相加溢出 |
| 初始 H | 18 | 有符号；`H_FRAC_BITS=14` 时为 MATLAB Q18.14 |
| LTF 差分功率 | 38 | `|H1-H2|²`，小数位 `2*H_FRAC_BITS` |
| 噪声方差 | 48 | 有效载波平均值，Q0.`2*H_FRAC_BITS` |
| LTF 累加 | 64 | 与已有 `cofdm_ltf_fine_cfo_accum` 一致 |

`cofdm_ltf_channel_estimator` 的 `H_FRAC_BITS` 参数控制信道输出的小数位。
默认值 15 保持早期单元测试兼容；Vivado 参考工程
`matlab/vivado/cofdm_ltf_channel_ref/` 使用 `H_FRAC_BITS=14`，与
`cofdm.receiver_config(...,'compact_fixed')` 一致。该工程已经在
`xc7z020clg400-2` 上以 8.138 ns 时钟综合通过：WNS `+0.426 ns`、6 个 DSP48E1、
2 个 RAMB18、944 个 LUT。

噪声方差不是在每个载波上做除法。RTL 先锁存 `H1/H2`，再计算
`(H2-H1)_I²+(H2-H1)_Q²`，最后用有效载波数的编译期倒数和一个 DSP 完成平均；
输出为 Q0.`2*H_FRAC_BITS`。这与 MATLAB `rx.m` 中
`mean(abs(H1-H2).^2)/2` 的统计定义一致，后续 LLR 可以直接使用该值。

## 验证

```bash
cd matlab/rtl
./run_checks.sh
```

当前新增测试使用相同频域 ROM 作为理想 LTF 输入，连续送入两个 256 点帧，
检查 200 个有效子载波的估计信道接近 `1+j0`：

```text
PASS dual-LTF channel estimate
PASS all COFDM RTL checks
```

MATLAB 侧的对应参考为：

```matlab
c = cofdm.config();
t = cofdm.training(c);
Y1 = fft(x1)/sqrt(c.nfft);
Y2 = fft(x2)/sqrt(c.nfft);
H1 = Y1(c.activeBins)./t.ltf(:,1);
H2 = Y2(c.activeBins)./t.ltf(:,2);
H = (H1+H2)/2;
```

## 后续实现顺序

1. 将 `cofdm_ltf_channel_chain` 接到实际 XFFT 输出，定义 XFFT 的
   `TLAST`/自然 bin 顺序和一拍流水延迟；当前 pre-FFT 顶层仍未连接
   `fft_out_*`，不能把独立模块通过误认为整机已经闭环。
2. 导出 MATLAB 的 XFFT 定点 Y1/Y2 和 `H`，增加逐 bin、逐位宽对拍，而不只
  检查理想信道。
3. 使用 `noise_variance` 作为 LLR 分母，并增加 `H` 的低复杂度 FIR7/时延投影模式。
4. 实现导频相位估计：先做 8 个导频的共享复累加，再用已有 CORDIC 或相位
   NCO 旋转整帧；斜率搜索可先固定为 9 个 ROM 候选。
5. 实现 matched-filter LLR。QPSK 不必先求 `Y/H`，直接计算
   `conj(H)·Y`，避免每个子载波的除法器；LLR 的分母使用噪声方差和信道误差
   的限幅近似。
6. 最后接入解交织、LDPC QC 层译码和 CRC，并以 MATLAB `rx.m` 输出的
   `codedLLR` 做 RTL bit-exact 对拍。

## 资源策略

XC7Z020 上不建议为 200 个载波复制 200 个除法器。推荐每拍一个频域 bin，
共享 2～4 个 DSP 复乘器；H 存 BRAM，导频/训练系数放 ROM。均衡阶段优先
使用 matched-filter LLR，只有在需要输出软均衡复数时才增加倒数 LUT 或
Newton-Raphson 迭代器。LDPC 使用 QC-Z=27 的分层最小和结构，和频域流水
分时复用，避免把频域后处理和译码同时展开到满并行。
