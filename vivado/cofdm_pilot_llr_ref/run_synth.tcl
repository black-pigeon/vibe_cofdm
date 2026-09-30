set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set report_dir [file normalize [file join $script_dir reports]]
file mkdir $report_dir
set xdc [file join $script_dir reference.xdc]
set f [open $xdc w]
puts $f {create_clock -name cofdm_clk -period 8.138 [get_ports clk]}
close $f

# Vivado 2022.2 has no reset_design command for a synthesized in-memory
# design.  Build each reference top in a fresh project so that the resource
# reports are independent and the script also works in batch mode.
foreach top {cofdm_pilot_phase_accum cofdm_matched_llr} {
  set project_dir [file join $script_dir project_$top]
  create_project cofdm_${top}_ref $project_dir -part xc7z020clg400-2 -force
  add_files [list [file join $rtl_dir cofdm_cordic_atan2.sv] \
    [file join $rtl_dir cofdm_pilot_phase_accum.sv] \
    [file join $rtl_dir cofdm_matched_llr.sv]]
  set_property file_type SystemVerilog [get_files *.sv]
  add_files -fileset constrs_1 $xdc
  synth_design -top $top -part xc7z020clg400-2
  report_utilization -file [file join $report_dir ${top}_utilization.rpt]
  report_timing_summary -delay_type max -max_paths 10 -file [file join $report_dir ${top}_timing.rpt]
  close_project
}
puts "COFDM pilot/LLR synthesis reports written"
