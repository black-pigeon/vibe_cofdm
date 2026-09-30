set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
if {![file exists [file join $proj_dir cofdm_ltf_chain_ref.xpr]]} { source [file join $script_dir create_project.tcl] }
open_project [file join $proj_dir cofdm_ltf_chain_ref.xpr]
set_property top tb_ltf_fine_cfo_chain [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
puts "COFDM integrated LTF chain XSim completed"
