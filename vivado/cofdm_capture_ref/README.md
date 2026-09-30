# COFDM 分级捕获参考工程

该工程把前端捕获分成五级：

1. STF 滑动相关只报告 `stf_candidate`，同时触发粗频偏估计；
2. 外部 LTF 相关器在合法窗口内报告 `ltf_peak_valid/score/index`；
3. 细频偏估计完成后报告 `fine_cfo_valid`；
4. PHY Header 解调器报告 `header_crc_valid/header_crc_ok`；
5. 控制器在包头 CRC 正确时才报告 `frame_valid` 和 `capture_locked`。

`cofdm_capture_ctrl.sv` 是可综合的低资源状态机，不做 256 点 LTF 复乘；
LTF 相关器、FFT、细频偏和包头译码作为后续可替换模块接入。无效 LTF、
超时、错误包头都会增加 `false_alarm_count` 并进入 `HOLDOFF`，避免同一
个突发重复触发。

运行：

```bash
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch -source run_sim.tcl
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch -source run_synth.tcl
```
