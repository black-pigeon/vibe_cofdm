# XC7Z020 COFDM MID 融合参考工程

这是当前 PHY 接收机的第一个 Vivado 参考工程，器件固定为
`xc7z020clg400-2`，Vivado 版本为 2022.2。工程只覆盖已经在 MATLAB/RTL
中验证过的 MID 信道融合内核，不代表完整的 FFT、解调、LDPC 和射频接口
已经完成。

## 数据路径

```text
200 路 old/fresh 复信道
       │ 每拍一个载波
       ▼
XPM simple-dual-port BRAM（200×72 bit）
       │ BRAM 同步读，增加一个 READ_REQ 周期
       ▼
四象限旋转 + α=1/4 或 α=1 融合
       │ 每拍一个结果
       ▼
XPM synchronous Block FIFO（256×37 bit）
       │ result_ready 握手
       ▼
下游均衡器/AXI-Stream 适配层
```

`cofdm_mid_fusion_ctrl_bram.sv` 使用 `xpm_memory_sdpram`，明确指定
`MEMORY_PRIMITIVE("block")`；`cofdm_mid_fusion_ref_top.sv` 使用
`xpm_fifo_sync`，明确指定 `FIFO_MEMORY_TYPE("block")`。因此综合报告中的
RAMB36 不是算法级容量估算，而是 Vivado 对实际 Xilinx 资源的映射结果。

## 运行

```bash
cd /path/to/vibe_cofdm
vivado/cofdm_mid_fusion_ref/run_all.sh
```

也可以分开执行：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source vivado/cofdm_mid_fusion_ref/run_sim.tcl
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch \
  -source vivado/cofdm_mid_fusion_ref/run_synth.tcl
```

仿真 testbench 向内核输入 200 个载波、4 个导频，检查 XPM BRAM 读延迟、
融合输出数量、`out_last` 标记和 FIFO 排空。通过标志为：

```text
PASS Vivado BRAM/FIFO reference, outputs=200
```

## 当前 Vivado 实测结果

报告位于 `reports/`。综合结果（`xc7z020clg400-2`，未做实现布局布线）为：

| 资源 | 使用量 | 器件总量 | 使用率 |
|---|---:|---:|---:|
| LUT | 1142 | 53200 | 2.15% |
| FF | 617 | 106400 | 0.58% |
| RAMB36 | 2 | 140 | 1.43% |
| DSP48E1 | 6 | 220 | 2.73% |

在 `reference.xdc` 的 122.88 MHz（8.138 ns）虚拟时钟下：

```text
WNS = +0.733 ns
TNS = 0 ns
0 个路径违反 setup
```

当前最差路径已经位于 FIFO/输出接口，导频乘法和创新累加不再是关键路径。
该参考内核在综合级别满足 122.88 MHz；完整 PHY 集成后的 implementation
阶段仍需重新检查布局布线时序。

## 下一步闭合时序的方向

1. 当前版本已经将导频相关/创新计算与 48 bit 累加分开，并在 BRAM 输出后
   增加 `FUSE_PREP` 流水级；后续仍可用导频位置计数器只在 8 个导频周期启动计算。
2. 复用一个或两个 DSP48E1 完成导频复乘，代价是 CAPTURE/DECIDE 增加少量
   状态和 8～16 个周期；这不会影响后面的 200 路一拍一载波输出。
3. 继续评估 BRAM 可选输出寄存器和 DSP 时分复用，避免完整 PHY 集成后重新
   出现长组合路径。
4. 完整 PHY 集成后再进行实现布局布线。当前参考 top 暴露了调试用全部端口，
   没有绑定具体载板管脚，不能把本工程直接下载到板卡；实际板级 top 应通过
   AXI-Stream/FIFO 与 ADC、FFT、LDPC 模块连接。

## 当前工程边界

当前 Vivado 工程只有 MID 信道融合内核，输入必须是已经得到的 old/fresh
复信道估计值。以下模块还没有进入 XC7Z020 数据通路：

```text
同步/包检测、粗细频偏估计与补偿、采样频偏跟踪
FFT/IFFT、CP 去除/插入、完整导频信道估计
均衡、软解调、LLR 定标、解交织
QC-LDPC 编译码、PHY 包头、可变长度协议接口
ADC/射频接口、AXI-DMA、Zynq PS 软件和板级管脚约束
```

MATLAB 模型或独立 RTL 检查通过，不等于这些模块已经集成进当前 FPGA 工程。

## 文件说明

- `create_project.tcl`：创建 XC7Z020 工程并加入 RTL、XDC、testbench。
- `run_sim.tcl`：调用 Vivado XSim 编译、展开和运行仿真。
- `run_synth.tcl`：综合并生成 utilization、timing、power、DRC 报告。
- `constraints/reference.xdc`：122.88 MHz 虚拟时钟；没有板卡 pin 约束。
- `project/`：Vivado 生成的工程目录。
- `reports/`：仿真日志和综合报告。
