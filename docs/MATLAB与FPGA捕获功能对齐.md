# MATLAB 与 FPGA 捕获功能对齐

## 当前实际状态

| 功能 | MATLAB 参考 | FPGA RTL |
|---|---|---|
| STF 周期相关 | `synchronize.m` 已实现 | `cofdm_stf_sync_frontend.sv` 已实现 |
| 粗频偏估计 | STF 相关相位 | `cofdm_cfo_angle_estimator.sv` 已实现 |
| 粗频偏补偿 | 复指数旋转 | `cofdm_cfo_nco_rotator.sv` 已实现，但 `phase_inc` 仍由外部输入 |
| LTF 精同步 | 已实现 256 点时域匹配搜索 | `cofdm_ltf_time_matcher_tdm.sv` 已实现 |
| LTF 相关门限 | 已实现归一化相关系数 | L1 相关分数和捕获事件已实现 |
| LTF1/LTF2 FFT | `rx.m` / `ltf_process.m` 已实现 | XFFT 外围及双帧适配器已实现 |
| 双 LTF 精 CFO | 已实现 `angle(sum(H2.*conj(H1)))` | `cofdm_ltf_fine_cfo_chain.sv` 已实现 |
| 精 CFO NCO 更新 | MATLAB 最终校正已实现 | 已有独立链路和 NCO 控制接口，统一闭环仍需接入 |
| LTF 信道估计 | 已实现 LS/融合前输入 | `cofdm_ltf_channel_chain.sv` 已实现初始 LS |

## MATLAB 中对应的位置

`synchronize.m` 首先用 STF 得到候选，然后执行：

```matlab
ref = t.ltfTime(:,1);
score(k) = abs(ref' * a)^2 / ...
    (sum(abs(ref).^2)*sum(abs(a).^2));
```

这一步确定 LTF1 的精确起点。随后对两个 LTF 有效部分 FFT：

```matlab
A = fft(v(first:first+c.nfft-1))/sqrt(c.nfft);
B = fft(v(second:second+c.nfft-1))/sqrt(c.nfft);
H1 = A(c.activeBins)./t.ltf(:,1);
H2 = B(c.activeBins)./t.ltf(:,2);
fineCfoHz = angle(sum(H2.*conj(H1))) * ...
    c.fs/(2*pi*(c.nfft+c.ncp));
```

`cofdm.ltf_process` 已把同一流程扩展为 MATLAB FFT 和 Xilinx bit-accurate XFFT 两个引擎。

## FPGA 应实现的对应接口

### 1. LTF 精同步模块

输入：

```text
sample_valid
coarse_corrected_re/im
candidate_valid
candidate_index
```

输出：

```text
ltf_peak_valid
ltf_peak_score       Q0.16
ltf_peak_index       采样索引
ltf_search_timeout
```

实现建议：先把候选窗口写入 BRAM，再用 4/8 路复乘累加搜索 256 点模板。不要直接展开 193 个候选位置 × 256 个复乘器。第一版可以把搜索范围从 STF 估计位置附近缩到 ±32 或 ±48，待 MATLAB 误检/漏检扫描后再确定窗口。

### 2. 双 LTF FFT/精 CFO 模块

`ltf_peak_index` 确认后，按 `CP=32`、`NFFT=256` 送入 XFFT 两个连续符号。两个 FFT 输出按 `TLAST` 分帧，在 200 个有效载波上累加：

```text
cross = Y2 * conj(Y1) * T1 * conj(T2)
fine_phase = atan2(sum(cross_im), sum(cross_re))
fine_cfo = fine_phase * Fs / (2π * (NFFT+CP))
```

`T1`、`T2` 是已知 ZC LTF 系数。由于 ZC 系数单位模，可以将 `T1*conj(T2)` 预存为一个 18 bit 旋转系数 ROM，避免除法器。

### 3. 精频偏反馈

锁存精 CFO 后产生：

```text
phase_inc_fine = round(-fine_cfo / Fs * 2^32)
```

NCO 应在 `fine_cfo_valid` 后切换到 `phase_inc_coarse + phase_inc_fine`，新帧开始时清零并重新锁存，不能继续使用旧帧的频偏。

## 当前结论

XFFT 工程的完成不等于完整数据接收。当前同步、LTF 精同步、双 LTF 精 CFO 和初始 LS 信道估计已经有独立 RTL；下一步是把 `cofdm_fft_stream_frontend`、`cofdm_ltf_channel_chain` 和统一捕获控制器连接起来，然后实现导频跟踪、匹配滤波 LLR、Header/LDPC 和可变长度数据帧处理。
