# Out-of-context synthesis for the BRAM-backed 9-way QC-LDPC decoder.
# This is the implementation-oriented counterpart of run_synth_qcldpc_qc9.tcl:
# all large state arrays are synchronous RAM banks and should map to BRAM18/36.
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set report_dir [file join $script_dir reports_qcldpc_qc9_bram]
file mkdir $report_dir

read_verilog -sv [file join $rtl_dir cofdm_qcldpc_qc_base_rom.sv]
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_sync_ram.sv]
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_qc9_bram_decoder.sv]
read_xdc [file join $script_dir parallel_clock.xdc]

synth_design -mode out_of_context -top cofdm_qcldpc_qc9_bram_decoder \
  -part xc7z020clg400-2 -generic "MAX_ITERS=12"
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_timing_summary -max_paths 20 -file [file join $report_dir timing.rpt]
report_power -file [file join $report_dir power.rpt]
puts "BRAM-backed QC9 synthesis complete"
