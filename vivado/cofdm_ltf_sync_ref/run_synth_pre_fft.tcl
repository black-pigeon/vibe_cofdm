set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
set report_dir [file normalize [file join $script_dir reports]]
file mkdir $report_dir
if {![file exists [file join $proj_dir cofdm_ltf_sync_ref.xpr]]} { source [file join $script_dir create_project.tcl] }
open_project [file join $proj_dir cofdm_ltf_sync_ref.xpr]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
foreach f {cofdm_ltf_freq_rom.sv cofdm_ltf_rot_rom.sv cofdm_ltf_channel_estimator.sv} {
  set fp [file join $rtl_dir $f]
  if {[llength [get_files -quiet $fp]] == 0} { add_files -fileset sources_1 $fp }
}
set_property top cofdm_sync_pre_fft_frontend [get_filesets sources_1]
set_property verilog_define {COFDM_XILINX_RAMB COFDM_XILINX_ROM} [get_filesets sources_1]
set_property generic {CANDIDATES=17 BUFFER_DEPTH=8192 TRAINING_SYMBOLS=2 DATA_SYMBOLS=1} [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "unified pre-FFT synthesis failed" }
open_run synth_1
report_utilization -file [file join $report_dir pre_fft_utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 -file [file join $report_dir pre_fft_timing_summary.rpt]
report_power -file [file join $report_dir pre_fft_power.rpt]
report_drc -file [file join $report_dir pre_fft_drc.rpt]
close_project
puts "COFDM unified pre-FFT synthesis reports written"
