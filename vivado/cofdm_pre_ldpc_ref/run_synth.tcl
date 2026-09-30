set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set report_dir [file normalize [file join $script_dir reports]]
file mkdir $report_dir
set xdc [file join $script_dir reference.xdc]
set f [open $xdc w]
puts $f {create_clock -name cofdm_clk -period 8.138 [get_ports clk]}
close $f
create_project cofdm_pre_ldpc_ref [file join $script_dir project] -part xc7z020clg400-2 -force
add_files [list [file join $rtl_dir cofdm_phase_lut.sv] \
  [file join $rtl_dir cofdm_common_phase_rotator.sv] \
  [file join $rtl_dir cofdm_cordic_atan2.sv] \
  [file join $rtl_dir cofdm_pilot_phase_accum.sv] \
  [file join $rtl_dir cofdm_matched_llr.sv] \
  [file join $rtl_dir cofdm_pre_ldpc_symbol.sv]]
set_property file_type SystemVerilog [get_files *.sv]
add_files -fileset constrs_1 $xdc
synth_design -top cofdm_pre_ldpc_symbol -part xc7z020clg400-2
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 -file [file join $report_dir timing.rpt]
close_project
puts "COFDM pre-LDPC synthesis reports written"
