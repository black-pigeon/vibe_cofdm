set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
file mkdir [file join $script_dir reports]
if {![file exists [file join $proj_dir cofdm_ltf_fine_cfo_ref.xpr]]} { source [file join $script_dir create_project.tcl] }
open_project [file join $proj_dir cofdm_ltf_fine_cfo_ref.xpr]
set_property top cofdm_ltf_fine_cfo_accum [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "dual-LTF accumulator synthesis failed" }
open_run synth_1
report_utilization -file [file join $script_dir reports utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 -file [file join $script_dir reports timing_summary.rpt]
report_power -file [file join $script_dir reports power.rpt]
report_drc -file [file join $script_dir reports drc.rpt]
close_project
puts "COFDM dual-LTF accumulator synthesis reports written"
