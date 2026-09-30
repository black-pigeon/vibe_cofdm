# COFDM 256 点 XFFT 参考工程

工程目标器件为 `xc7z020clg400-2`，使用 Vivado 2022.2 自带 `xfft` 9.1 IP。

```text
输入复数采样
  └─ in_symbol_start：一个 OFDM 符号 CP 的第一个采样
       ↓
丢弃 32 点 CP
       ↓
送入 XFFT 256（AXI4-Stream）
       ↓
输出 256 个频域点，TLAST 标记符号结束
```

当前 XFFT 参数：定点、I/Q 16 bit、单通道、流水流式、Block RAM、自然序输出、正向 FFT。缩放配置为 `16'h0157`：bit0 为正向，bits `[8:1]` 为默认缩放表 `11,10,10,10`。

运行仿真和综合：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch -source run_sim.tcl
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch -source run_synth.tcl
```

XSim 测试使用 32 个 CP 加 256 个有效样点，验证输出 256 点、单次 TLAST、无 FFT overflow。XFFT 采用 `nonrealtime` 流控，输出可能出现气泡，后级必须按 `m_axis_data_tvalid/m_axis_data_tready` 计数，不能假设固定延迟或每拍连续输出。

综合报告位于 `reports/`。当前参考结果为 LUT 2343、FF 4037、RAMB18 2、DSP48E1 9，122.88 MHz 约束下 WNS +1.559 ns、TNS 0 ns。这个结果只包含 XFFT 和 CP/AXI 外围。
