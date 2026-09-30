set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
if {![file exists [file join $proj_dir cofdm_mid_fusion_ref.xpr]]} {
  source [file join $script_dir create_project.tcl]
}
open_project [file join $proj_dir cofdm_mid_fusion_ref.xpr]
set_property top cofdm_mid_fusion_ref_top [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {$synth_status ne "synth_design Complete!"} {
  error "Synthesis failed: $synth_status"
}
open_run synth_1
file mkdir [file join $script_dir reports]
report_utilization -hierarchical -file [file join $script_dir reports utilization_hierarchical.rpt]
report_utilization -file [file join $script_dir reports utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 -file [file join $script_dir reports timing_summary.rpt]
report_power -file [file join $script_dir reports power.rpt]
report_drc -file [file join $script_dir reports drc.rpt]
close_project
puts "COFDM synthesis reports written to [file join $script_dir reports]"
