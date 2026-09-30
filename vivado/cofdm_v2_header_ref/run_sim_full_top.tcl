set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set project_file [file join $script_dir project_full_top cofdm_phy_rx_v2_ref.xpr]
if {[file exists $project_file]} {open_project $project_file} else {
  source [file join $script_dir create_full_project.tcl]
}
if {[llength [get_files -quiet *tb_phy_rx_v2_top.sv]]==0} {add_files -fileset sim_1 [file join $rtl_dir tb tb_phy_rx_v2_top.sv]}
set vecdir [file normalize [file join $script_dir .. .. vectors phy_rx_v2]]
foreach f [glob [file join $vecdir *.mem]] {if {[llength [get_files -quiet $f]]==0} {add_files -fileset sim_1 $f}}
set_property top tb_phy_rx_v2_top [get_filesets sim_1]
set_property verilog_define {COFDM_XILINX_FIFO COFDM_XILINX_RAMB} [get_filesets sim_1]
set_property xsim.simulate.runtime {0ns} [get_filesets sim_1]
launch_simulation
run all
set status [get_value -radix unsigned /tb_phy_rx_v2_top/test_pass]
if {$status ne "1"} {error "RX simulation did not reach PASS"}
close_sim
close_project
