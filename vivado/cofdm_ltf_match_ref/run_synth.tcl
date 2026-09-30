set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
set report_dir [file normalize [file join $script_dir reports]]
file mkdir $report_dir
if {![file exists [file join $proj_dir cofdm_ltf_match_ref.xpr]]} { source [file join $script_dir create_project.tcl] }
open_project [file join $proj_dir cofdm_ltf_match_ref.xpr]
set_property top cofdm_ltf_time_matcher [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "LTF matcher synthesis failed" }
open_run synth_1
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 -file [file join $report_dir timing_summary.rpt]
report_power -file [file join $report_dir power.rpt]
report_drc -file [file join $report_dir drc.rpt]
close_project
puts "COFDM LTF time matcher synthesis reports written"
