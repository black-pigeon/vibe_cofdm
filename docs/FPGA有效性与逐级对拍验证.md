# FPGA 接收机有效性与正确性验证

## 验证原则

FPGA 接收机不能用“仿真没有报错”作为正确性结论。验证必须同时回答四个问题：数值是否正确、时序是否正确、算法是否有效、硬件是否可实现。

## 当前已经具备的证据

### RTL 模块回归

```bash
cd matlab/rtl
./run_checks.sh
```

该回归覆盖 STF 检测、粗频偏角度、NCO、LTF 时域匹配、双 LTF 精频偏、回放缓存、
信道估计、稀疏有效载波和捕获状态机。它主要证明控制和边界条件，不能代替随机
信道的数值对拍。

### XFFT 参考一致性

`tests/run_xfft_matlab_compare.m` 对 MATLAB FFT 和 Xilinx bit-accurate C model 做
整数比较，允许的误差为量化造成的 2 个整数码。XFFT 的 stage scaling、输入/输出
位宽必须固定后，后级信道估计和 LLR 才有意义。

### MATLAB 到 RTL 的双 LTF 定点对拍

```bash
bash matlab/tests/run_ltf_channel_bitexact.sh
```

脚本用固定随机种子生成频域多径信道和两组独立 LTF 噪声，按 RTL 的整数复乘、算术
右移、Q18.14 平均和饱和规则生成期望文件，再逐 bin 比较 RTL 的 `H`、完成标志、
噪声方差和有效载波计数。

当前结果：

```text
PASS LTF channel bit-exact vector check bins=200
```

这已经验证了复数乘法符号、自然 FFT bin 顺序、负数算术右移、双 LTF 平均、保护带
结束判决以及噪声方差归一化。向量位于 `matlab/vectors/ltf_channel/`。

### Vivado 综合证据

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_channel_ref/run_synth.tcl
```

双 LTF 信道估计参考工程在 XC7Z020CLG400-2、122.88 MHz 下 WNS 为 `+0.426 ns`，
使用 6 个 DSP48E1、2 个 RAMB18 和约 944 个 LUT。该结果只覆盖双 LTF 频域模块。

### 导频、相位旋转和 LLR

```bash
bash matlab/tests/run_pilot_llr_bitexact.sh
```

该脚本用 MATLAB 生成 96 组带正负值和饱和边界的 `Y/H/invNoise`，并逐组比较
`conj(H)*Y`、算术右移、BPSK/QPSK 模式和饱和标志。当前结果为：

```text
PASS pilot/LLR bit-exact vectors=96
```

`cofdm_pre_ldpc_symbol` 是当前 XFFT 后的参考接收核：它把双 LTF 信道输出写入
256 点缓存，逐拍读取 8 个导频并由 CORDIC 求公共相位，随后用相位 LUT 复用旋转器，
输出自然载波顺序的 BPSK/QPSK LLR。`matlab/rtl/tb/tb_pre_ldpc_symbol.sv` 使用
平坦信道和 `+pi/2` 整符号旋转，已验证输出 192 个数据载波、相位回正和符号完成。

在 XC7Z020、122.88 MHz 约束下，参考核综合结果为 WNS `+0.683 ns`、TNS `0`，
约 2052 LUT、626 FF、16 DSP48E1、2 RAMB18（1 个 BRAM tile）。这是可复用内核
的资源基线；实际接入 XFFT、同步、反交织和 LDPC 后仍需重新综合和布线。

## 推荐的逐级验证链

```text
MATLAB浮点黄金模型
  → MATLAB定点模型
  → HEX/CSV
  → RTL模块逐拍仿真
  → Vivado XSim/综合网表仿真
  → FPGA数字回环
  → SDR有线衰减/无线测试
```

每一级都要保存输入、输出、版本、随机种子和失败原因。不能只比较最终 payload，
否则同步错一拍、FFT bin 交换、LLR 符号反转等问题会被 LDPC 的纠错能力掩盖。

## 到 LDPC 译码之前的验收项目

### 同步和频偏

MATLAB 和 RTL 使用同一段 IQ，扫描 CFO `0、±30 kHz、±135 kHz、±220 kHz`、初始
偏移、噪声和多径。比较 STF/LTF 位置、粗频偏增量、双 LTF 精频偏和精频偏切换后的
相位残差。无噪声位置误差应为 0；有噪声时必须落在 CP 允许窗口内。

### XFFT 和 CP 去除

检查每个符号的 `symbol_start`、CP 丢弃数量、XFFT `TLAST`、自然序 bin 和溢出标志。
用冲激、单一子载波、LTF 和随机复数输入测试。单一子载波测试最容易发现正负频率
交换和 `fftshift` 错误。

### 信道估计

当前已完成双 LTF LS 逐位对拍。后续增加 CP 内 0/3/9/31 点多径、深衰落、不同噪声
方差、XFFT 溢出和信道饱和测试，并统计最大误差、MSE、饱和计数和噪声方差误差。
FIR7 或时延投影启用前，必须证明其相对 LS 的 MSE/PER 改善并完成定点对拍。

### 导频跟踪

导出 MATLAB 的 8 个导频复乘和、公共相位 `phi`、相位斜率 `slope` 及旋转后的 200 个
有效载波，逐级与 RTL 比较。当前 RTL 核先实现公共相位；相位斜率仍由 MATLAB
参考保留，接入高速移动场景前必须增加斜率估计和定点对拍。测试相位跨越 `-pi/pi`、
固定相位、线性相位斜率和噪声。

### 匹配滤波和 LLR

QPSK 使用 `matched=conj(H)*Y`，再计算 I/Q LLR。MATLAB 与 RTL 必须统一 H、噪声方差、
LLR 缩放、饱和范围和正负号。验收 LLR 最大误差、符号错误率、量化后 LDPC FER/PER
差异，并检查深衰落子载波不会产生异常大 LLR。

### Header 解码前整链

用已知 Header BPSK 符号验证：

```text
同步 → CFO → FFT → H → 导频跟踪 → BPSK LLR → 解扰输入
```

只有 Header LLR 逐位与 MATLAB 一致，才进入 Header LDPC；否则应停在频域链路排查。

## 当前仍不能证明的内容

- `cofdm_sync_pre_fft_frontend` 仍没有把实际 XFFT 输出接入双 LTF 频域链；
- `cofdm_pre_ldpc_symbol` 已作为独立 XFFT 后参考核完成，但尚未接入统一同步 top，
  也尚未接收真实 XFFT IP 的 AXI 气泡和 TLAST；
- 还没有 FPGA 板上 ADC、异步时钟、射频增益和量化噪声验证；
- MATLAB 灵敏度结果不能直接等价为 FPGA 灵敏度；
- 模块仿真通过不能证明长帧回放、AXI 反压和 LDPC 最坏时延满足要求。

因此目前可以确认“双 LTF 频域信道估计模块在定点和综合层面正确”，还不能宣称
完整 FPGA 接收机已经验证完成。
