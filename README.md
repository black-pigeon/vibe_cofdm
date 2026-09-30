# 自有 COFDM 建模工程 · v1基线 / v2实验

**整体架构入口：** [链路结构与模块职责](docs/整体链路架构.md) · [Word版](docs/整体链路架构.docx)。包含总览、收发结构图、帧内数据流、源码接口，以及当前PHY与未来FPGA/自组网协议的边界。

本目录是独立的 COFDM 建模与 FPGA 参考工程。系统参数为：15.36 MS/s、256 点 FFT、32 点 CP、短训练、两个 ZC 长训练、数据导频、中间训练和 LDPC；FPGA 目标为 Zynq-7020。

## 已完成的模型

新增v2短头/变长分支：`run_variable_demo(1500)`；显式配置 `cofdm.config_v2()`，支持1个BPSK头符号、1～2048字节载荷。头采用卷积码，载荷保留QPSK/LDPC，接收端从头恢复长度。`config()`仍默认v1，两版本不自动互通。设计见 [IP承载与可变长度帧](docs/IP承载与可变长度帧设计.md)，结果见 [v2验证](results/VARIABLE_PHY.md)，灵敏度评估见 [SENSITIVITY](results/SENSITIVITY.md)。MAC/IP与TUN/TAP尚未实现。

- 不依赖 Communications Toolbox 的 MATLAB 浮点收发链；MATLAB R2020b 为主要验证环境，兼容 GNU Octave。
- STF 包检测/粗 CFO、双 ZC LTF 定时与细 CFO、LS 信道估计、导频公共相位/线性相位斜率补偿。
- QPSK、单抽头 MMSE 形式均衡、可靠性加权 LLR。
- 648/324、Z=27 的 QC-LDPC 编码和分层归一化最小和译码；可选消息量化实验。
- 编码帧头、CRC、扰码、交织；v1固定3个MID，v2按长度和头部配置计算MID。
- AWGN、整数采样偏移、静态多径、CFO；端到端扫描和 FPGA 对拍向量导出。

**目前未实现**：16/64QAM、其他 LDPC 码率、闭环 ACM/ARQ、SFO 重采样、Doppler 时变信道、PA 非线性、FPGA RTL、完整定点 FFT/NCO。设计文档中这些明确列为后续阶段。模型通过不等于链路距离或 FPGA 时序通过。

## 算法深化实验

新增可选接收分支：时延子空间信道去噪、信道误差感知 LLR、圆周导频相位/斜率估计，以及面向 FPGA 的 MID 信道融合/导频时间跟踪。通过 `c=cofdm.receiver_config(cofdm.config(),'proposed')` 或 `config_v2('compact_fused')`、`config_v2('compact_tracked')` 启用；默认仍是原基线。详细设计见 [算法深化设计](docs/算法深化设计.md) 和 [低复杂度改进](docs/接收机低复杂度改进.md)，配对测试结果见 [接收算法验证](results/RECEIVER_ALGORITHMS.md)。当前实验仅覆盖有限静态/受控时变信道，不代表已完成移动链路优化。

在 MATLAB 中 `addpath('matlab'); addpath('matlab/tests');` 后运行：

```matlab
run_receiver_tests();
run_receiver_comparison([4 6 8],20,'matlab/results/receiver_comparison.csv');
```

面向 7020 的下一轮低复杂度候选使用 `c=cofdm.receiver_config(cofdm.config(),'compact')`：能量簇 FFT 窗口、7 抽头信道 FIR、9 点导频斜率搜索。设计与运算预算见 [低复杂度接收机设计](docs/低复杂度接收机设计.md)，结果见 [低复杂度验证](results/COMPACT_RECEIVER.md)。

```matlab
run_demo('compact');
run_compact_tests();
run_compact_comparison([4 6],40,'matlab/results/compact_holdout.csv',20260929);
receiver_budget();
```

## 运行

最新可选研究分支 `compact_fixed` 加入估计安全区间居中的FFT窗、信道FIR逐级定点及导频ROM量化。它仍是单链路PHY，尚非完整自组网协议或全链定点。详见 [局部定点与窗口优化](docs/局部定点与窗口优化.md) 和 [验证记录](results/FIXED_RECEIVER.md)。在本目录运行 `run_demo('compact_fixed')`；`export_receiver_vectors()` 导出新增模块对拍向量。

在 MATLAB 中：

```matlab
cd('/path/to/vibe_cofdm')
run_demo();
addpath('tests'); run_tests();
run_snr_sweep([0 2 4 6 8 12], 20, 'results/snr_smoke.csv');
run_acquisition_sweep('results/acquisition_smoke.csv');
export_vectors();
plan_budget();
link_budget(); % 明确标注为假设的自由空间预算示例
```

命令行验证：

```bash
/opt/Polyspace/R2020b/bin/matlab -batch "addpath('matlab'); run_demo(); addpath('matlab/tests'); run_tests();"
octave --no-gui --quiet --eval "addpath('matlab'); run_demo(); addpath('matlab/tests'); run_tests();"
```

无图形界面也可运行；返回结构体可自行绘制星座、信道和结果。随机种子固定，但 MATLAB/Octave 随机序列可能不同；RTL 对拍以导出的确定性文件为准。

## 文件导航

| 文件 | 用途 |
|---|---|
| `docs/PHY设计.md` | 帧结构、比特顺序、载波映射、训练、同步/均衡、设计限制 |
| `docs/IP承载与可变长度帧设计.md` | v2短头、变长载荷、软件MAC/IP分层及有界缓存 |
| `run_variable_demo.m`, `tests/run_variable_tests.m` | v2演示、头保护、长度和截断边界验证 |
| `docs/FPGA实现规划.md` | 7020 模块、处理周期、存储、位宽、接口和实施路线 |
| `docs/远距离与高速设计.md` | 链路预算、MCS、功放、导频与可靠性取舍 |
| `docs/验证计划.md` | 仿真矩阵、指标定义、硬件验证门槛 |
| `docs/算法深化设计.md` | 实现损失、算法消融、定时/估计/编码/帧开销研究顺序 |
| `run_receiver_comparison.m` | 四种接收分支在同一 IQ 上的配对 PER/吞吐对照 |
| `results/RECEIVER_ALGORITHMS.md` | 改进接收机实测结果与适用边界 |
| `docs/低复杂度接收机设计.md` | FFT 窗口、FIR 去噪、9 点搜索及 7020 运算/ROM 预算 |
| `run_compact_comparison.m` | 五种信道下对比上一轮与本轮算法，输出配对退化/恢复及 FFT 窗诊断 |
| `run_tracking_comparison.m` | compact、MID信道融合、导频时间跟踪的共享IQ对照 |
| `run_llr_comparison.m` | 低复杂度 LLR 缩放筛查；浮点结果未观察到收益 |
| `results/window_comparison.csv`、`results/llr_comparison.csv` | FFT窗门限与LLR缩放的负结果/筛查数据 |
| `receiver_budget.m` | 可复算的算法运算量；不代表综合资源 |
| `docs/局部定点与窗口优化.md` | 新窗口策略、FIR逐级位宽、舍入/饱和及硬件映射约束 |
| `docs/接收机低复杂度改进.md` | MID信道融合、导频时间跟踪及7020资源/时序设计 |
| `rtl/cofdm_quadrant_select.sv`、`rtl/cofdm_fusion_lane.sv` | 四象限选择和单载波移位融合 RTL 内核初版 |
| `rtl/cofdm_mid_fusion_ctrl.sv`、`rtl/README.md` | 200载波MID控制器、接口时序和RTL检查命令 |
| `export_fusion_vectors.m`、`tests/verify_fusion_vectors.py` | MATLAB/独立Python整数对拍向量 |
| `run_fixed_comparison.m` | 原compact/居中窗口/局部定点的共享IQ比较 |
| `run_fixed_precision.m` | 配对位宽扫描，误差相对浮点FIR输出 |
| `export_receiver_vectors.m` | FIR输入输出及旋转/归一化/导频ROM整数向量 |
| `+cofdm/config.m` | v0.1 唯一参数入口；当前仅固定 profile 1 可运行 |
| `+cofdm/tx.m`, `rx.m`, `synchronize.m` | 收发与同步 |
| `+cofdm/ldpc_*.m` | QC 矩阵、XOR 编码、分层 NMS 译码 |
| `run_snr_sweep.m` | 包含同步和帧头失败的 PER；条件 BER 单独报告 |
| `export_vectors.m` | IQ、码字、矩阵移位、交织与 LTF 参考向量 |
| `results/VALIDATION.md` | 本次实际运行记录，区别于后续验收目标 |
| `THIRD_PARTY_NOTICES.md` | QC 矩阵来源、校验散列与许可 |

基线：200 有效载波（192 数据 + 8 导频）；每帧 27 个数据符号、16 个载荷 LDPC 码字；644 字节净载荷；帧槽 687.5 μs；无误码、无重传、无 TDD 换向时约 7.494 Mbit/s。48/60 kHz 等其他子载波间隔不是当前 profile 的可切换选项。
