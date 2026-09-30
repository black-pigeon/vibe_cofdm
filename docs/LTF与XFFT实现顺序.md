# LTF 与 XFFT 的实现顺序

XFFT 不是对 LTF 的替代，而是 LTF 频域处理所需的运算内核。完整流程应分成两段：

```text
STF候选/粗CFO
  ↓
LTF时域匹配相关，搜索精确起点
  ↓
LTF1、LTF2去CP
  ↓
XFFT 256
  ↓
双LTF频域累加
  ├─ 精频偏
  └─ 初始信道
```

MATLAB 的 [synchronize.m](../+cofdm/synchronize.m) 已实现这个算法；FPGA 当前只实现了 STF、粗 CFO、捕获控制器事件接口，以及独立验证的 XFFT CP 外围。

## MATLAB 对照层

- `cofdm.xfft_model`：MATLAB FFT参考和 Xilinx bit-accurate C model 两种引擎。
- `cofdm.ltf_process`：双 LTF FFT、信道估计、精频偏和 NCO 相位增量参考。
- `tests/run_xfft_matlab_compare.m`：随机定点输入的 MATLAB/XFFT 对拍。
- `tests/run_ltf_xfft_reference.m`：注入频偏的双 LTF 对照。

运行：

```bash
/opt/Polyspace/R2020b/bin/matlab -batch "addpath('matlab'); addpath('matlab/tools'); run('matlab/tests/run_xfft_matlab_compare.m')"
/opt/Polyspace/R2020b/bin/matlab -batch "addpath('matlab'); addpath('matlab/tools'); run('matlab/tests/run_ltf_xfft_reference.m')"
```

## FPGA 后续模块

1. LTF 候选窗口缓存和时域匹配相关：低并行度复乘累加，输出峰值、位置和归一化分数。
2. 双 LTF 调度器：收到合法峰值后，按 CP32/FFT256 的边界向 XFFT 送入两个符号。
3. 双 LTF 频域处理器：只处理 200 个有效载波，计算 `H1/H2` 和 `sum(H2*conj(H1))`。
4. 精 CFO 锁存与 NCO 更新：`phase_inc_fine = round(-f_fine/fs*2^32)`，新帧重新清零。
5. 将 `ltf_peak_*` 和 `fine_cfo_valid` 接入 `cofdm_capture_ctrl`，再允许 Header 解调开始。
