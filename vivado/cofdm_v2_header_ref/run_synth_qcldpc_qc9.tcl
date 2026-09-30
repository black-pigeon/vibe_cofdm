# Out-of-context synthesis for the first QC-subblock throughput core.
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set report_dir [file join $script_dir reports_qcldpc_qc9]
file mkdir $report_dir
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_qc_base_rom.sv]
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_qc9_decoder.sv]
read_xdc [file join $script_dir parallel_clock.xdc]
synth_design -mode out_of_context -top cofdm_qcldpc_qc9_decoder \
  -part xc7z020clg400-2 -generic "MAX_ITERS=12"
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing.rpt]
puts "QC9 throughput core synthesis complete"
