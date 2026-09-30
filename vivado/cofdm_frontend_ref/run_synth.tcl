set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
file mkdir [file join $script_dir reports]
if {![file exists [file join $proj_dir cofdm_frontend_ref.xpr]]} { source [file join $script_dir create_project.tcl] }
open_project [file join $proj_dir cofdm_frontend_ref.xpr]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
if {[llength [get_files -quiet *cofdm_cfo_angle_estimator.sv]] == 0} {
  add_files -fileset sources_1 [file join $rtl_dir cofdm_cfo_angle_estimator.sv]
}
set_property top cofdm_sync_frontend_ref_top [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "front-end synthesis failed" }
open_run synth_1
report_utilization -file [file join $script_dir reports utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 -file [file join $script_dir reports timing_summary.rpt]
report_power -file [file join $script_dir reports power.rpt]
report_drc -file [file join $script_dir reports drc.rpt]
close_project
puts "COFDM front-end synthesis reports written"
