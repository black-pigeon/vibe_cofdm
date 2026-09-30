# XFFT 后至 LDPC 前参考核

综合：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_pre_ldpc_ref/run_synth.tcl
```

`cofdm_pre_ldpc_symbol` 使用 256 点符号 BRAM 保存 XFFT 输出，在 8 个导频
上做复相关，调用一次 CORDIC 求公共相位，再用共享的 256 相位 LUT 对数据
载波逐个旋转，最后输出自然载波顺序的 BPSK/QPSK LLR。这个模块不包含
解交织、帧头解扰、CRC 或 LDPC；`llr_bin` 和 `llr_last` 是后级按 192/384
槽位装帧的边界。
