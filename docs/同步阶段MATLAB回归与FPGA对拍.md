# 同步阶段 MATLAB 回归与 FPGA 对拍

当前同步模型 `+cofdm/synchronize.m` 的处理顺序是：

1. 以 16 点 STF 周期计算 64 点滑动复相关和归一化能量；连续 24 点超过门限才产生候选。
2. 在候选附近用已知 LTF 时域模板搜索峰值，避免把 STF 周期性结构直接当成帧锁定。
3. 对两个 LTF 做 FFT，在频域计算相邻 LTF 的相位差得到精频偏，并与粗频偏相加。
4. 由 LTF 位置、STF 长度和 CP 长度推导首个有效 FFT 窗，输出校正后的 IQ。

`run_sync_regression` 将模型事件映射为 FPGA 可观测事件：

| MATLAB 字段 | FPGA 对应事件 |
| --- | --- |
| `stfDetected`, `stfStart` | `stf_candidate`, `stf_index` |
| `coarseCfoHz` | 粗频偏估计/NCO 相位增量 |
| `ltfDetected`, `ltfPeakStart`, `peak` | `ltf_peak_valid`, `ltf_peak_index`, `ltf_peak_score` |
| `fineCfoHz` | 双 LTF 精频偏完成 |
| `cfoHz`, `frameStart` | 最终 CFO 和 `frame_valid` 前的帧起点 |

运行：

```bash
/opt/Polyspace/R2020b/bin/matlab -batch \
  "addpath('matlab'); addpath('matlab/tests'); \
   run_sync_regression('matlab/results/sync_regression')"
```

脚本会输出四种有效信号场景和两种无效输入场景的统计，并生成
`sync_golden.mat`、`sync_golden_iq.csv`、`sync_golden_expected.csv`。RTL 对拍应
先比较事件顺序和采样位置，再比较 Q 格式的粗/精频偏增量；允许的误差应由
量化位宽和 CORDIC/LUT 延迟明确写入测试平台，不能用“最终能解码”替代逐点检查。

当前一次 20 次/场景的回归结果如下（固定随机种子）：

| 场景 | STF | LTF | 最终锁定 | CFO 最终 RMSE |
| --- | ---: | ---: | ---: | ---: |
| noiseless | 1.000 | 1.000 | 1.000 | 0 Hz |
| AWGN + 135 kHz CFO | 1.000 | 1.000 | 1.000 | 41.4 Hz |
| 多径 + −220 kHz CFO | 1.000 | 1.000 | 1.000 | 68.9 Hz |
| 低 SNR 8 dB | 1.000 | 1.000 | 1.000 | 187.6 Hz |

噪声-only 和周期性单音在该回归中均为 0 次误接受（各 100 次）。这些数值是
模型回归基线，不是射频灵敏度或连续流误警率认证；改变同步门限、定点格式、
信道模型或 XFFT 缩放后应重新生成并保存报告。
