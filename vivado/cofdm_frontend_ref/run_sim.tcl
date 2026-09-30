set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
file mkdir [file join $script_dir reports]
if {![file exists [file join $proj_dir cofdm_frontend_ref.xpr]]} { source [file join $script_dir create_project.tcl] }
open_project [file join $proj_dir cofdm_frontend_ref.xpr]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
if {[llength [get_files -quiet *cofdm_cfo_angle_estimator.sv]] == 0} {
  add_files -fileset sources_1 [file join $rtl_dir cofdm_cfo_angle_estimator.sv]
}
set_property top tb_sync_frontend_ref_top [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
puts "COFDM front-end XSim regression completed"
