set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set project_file [file join $script_dir project_payload_top cofdm_phy_rx_v2_payload_ref.xpr]
if {![file exists $project_file]} {
  error "Run run_synth_payload_top.tcl first to create the Payload Vivado project"
}
open_project $project_file
set tb [file join $rtl_dir tb tb_phy_rx_v2_payload_top.sv]
if {[llength [get_files -quiet *tb_phy_rx_v2_payload_top.sv]]==0} {add_files -fileset sim_1 $tb}
set vecdir [file normalize [file join $script_dir .. .. vectors phy_rx_v2]]
if {$argc > 0} {set vecdir [file normalize [lindex $argv 0]]}
foreach f {rx_config.mem rx_bits.mem rx_iq.mem} {
  if {![file exists [file join $vecdir $f]]} {error "Missing input: $vecdir/$f"}
}
set_property top tb_phy_rx_v2_payload_top [get_filesets sim_1]
set_property verilog_define {COFDM_XILINX_FIFO COFDM_XILINX_RAMB} [get_filesets sim_1]
update_compile_order -fileset sim_1
# Compile once, then run standalone XSim without GUI/wave logging. Vivado may
# export default memory files during compilation, so replace them AFTER that.
launch_simulation -step compile
launch_simulation -step elaborate
set simrun [file normalize [file join $script_dir project_payload_top cofdm_phy_rx_v2_payload_ref.sim sim_1 behav xsim]]
foreach f {rx_config.mem rx_bits.mem rx_iq.mem} {
  file copy -force [file join $vecdir $f] [file join $simrun $f]
}
set old_pwd [pwd]
cd $simrun
file delete -force rtl_status.txt
set xsim /opt/Xilinx/Vivado/2022.2/bin/xsim
exec $xsim tb_phy_rx_v2_payload_top_behav -tclbatch [file join $script_dir payload_run_all.tcl] -log simulate.log >@stdout 2>@stdout
set f [open rtl_status.txt r]
set status [string trim [read $f]]
close $f
file copy -force rtl_llr.txt [file join $vecdir rtl_llr.txt]
file copy -force simulate.log [file join $vecdir simulate.log]
file copy -force rtl_status.txt [file join $vecdir rtl_status.txt]
cd $old_pwd
close_project
if {$status ne "1"} {error "Payload simulation did not reach PASS (see $vecdir/simulate.log)"}
