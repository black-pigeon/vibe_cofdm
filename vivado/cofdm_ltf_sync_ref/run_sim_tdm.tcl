set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
if {![file exists [file join $proj_dir cofdm_ltf_sync_ref.xpr]]} {
  source [file join $script_dir create_project.tcl]
}
open_project [file join $proj_dir cofdm_ltf_sync_ref.xpr]
set_property top tb_ltf_sync_capture_frontend_tdm [get_filesets sim_1]
set_property verilog_define {COFDM_XILINX_ROM} [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
puts "COFDM TDM LTF synchronization XSim completed"
