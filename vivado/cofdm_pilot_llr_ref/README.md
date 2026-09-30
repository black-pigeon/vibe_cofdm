# 导频相位与 matched-filter LLR 参考综合

运行：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_pilot_llr_ref/run_synth.tcl
```

该脚本分别综合 `cofdm_pilot_phase_accum` 和 `cofdm_matched_llr`，用于检查
XC7Z020 上的 DSP 数量和 122.88 MHz 时序。两者是 LDPC 前的共享运算内核，
尚未接入完整符号 BRAM 回放控制器。
