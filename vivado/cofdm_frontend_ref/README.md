# XC7Z020 接收前端参考工程

该工程覆盖当前 PHY 迁移的第一段：STF 流式同步检测和 CFO NCO 复数旋转。
`phase_inc` 为 Q0.32 的 turns/sample，粗频偏估计模块完成后可直接驱动 NCO。
当前仍未包含 LTF 精同步、FFT、信道估计、均衡和 LDPC。

```bash
matlab/vivado/cofdm_frontend_ref/run_all.sh
```

工程使用 `xc7z020clg400-2` 和 Vivado 2022.2；报告位于 `reports/`。该 top
没有绑定开发板管脚，只用于仿真、综合和算法迁移阶段的资源/时序基线。

最近一次综合结果（122.88 MHz 虚拟时钟）：

| 资源 | 使用量 |
|---|---:|
| LUT | 2017 |
| FF | 2004 |
| LUTRAM | 164 |
| DSP48E1 | 29 |
| RAMB36 | 0 |

WNS=`+2.324 ns`，TNS=`0`。同步器使用平方能量和流水化交叉乘法，历史窗口
由分布式 RAM 实现；NCO 使用 256 相位 bin 的四象限 Q1.15 正弦 ROM 和三级
流水；CFO 角度估计使用 16 轮共享 CORDIC。该结果是前端子系统的综合级数据，
尚未包含 FFT 和 LTF 细同步。
