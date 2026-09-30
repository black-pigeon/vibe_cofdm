# 双 LTF 信道估计 Vivado 参考工程

目标器件为 `xc7z020clg400-2`，默认将信道字配置为 MATLAB `compact_fixed` 使用的
Q18.14（`H_FRAC_BITS=14`）。工程顶层是 `cofdm_ltf_channel_chain`，包含自然序
XFFT 元数据适配、双 LTF LS 信道估计、BRAM 信道存储和双 LTF 噪声方差估计。

运行综合：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source matlab/vivado/cofdm_ltf_channel_ref/run_synth.tcl
```

报告在 `reports/`。噪声方差使用有效载波数的编译期倒数乘法，综合不会生成
运行时除法器；`noise_variance` 为 Q0.`2*H_FRAC_BITS`。
