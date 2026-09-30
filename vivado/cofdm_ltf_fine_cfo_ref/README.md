# 双 LTF 精频偏累加器参考工程

`cofdm_ltf_fine_cfo_accum.sv` 对两个自然序 XFFT 帧进行处理。第一帧缓存为 LTF1；第二帧在 200 个有效载波上计算：

```text
Y2 * conj(Y1) * T1 * conj(T2)
```

其中 `rot_re/rot_im` 是预存的 Q1.15 旋转系数。输出 `fine_sum_re/im` 交给 CORDIC `atan2`，再按照 MATLAB 参考公式转换为精频偏。

当前模块不负责 LTF 时域精同步，也不负责 XFFT 本身；它是 XFFT 后级的低资源可综合内核。
