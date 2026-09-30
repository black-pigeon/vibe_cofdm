set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set report_dir [file join $script_dir reports_qcldpc]
file mkdir $report_dir
create_project cofdm_qcldpc_ref [file join $script_dir project_qcldpc] -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
add_files [file join $rtl_dir cofdm_qcldpc_648_decoder.sv]
add_files [file join $rtl_dir cofdm_qcldpc_edge_rom.sv]
add_files [file join $rtl_dir cofdm_payload_codeword_bridge.sv]
set_property top cofdm_payload_codeword_bridge [get_filesets sources_1]
update_compile_order -fileset sources_1
set xdc [file join $report_dir qcldpc_clock.xdc]
set fp [open $xdc w]
puts $fp {create_clock -name clk -period 8.138 [get_ports clk]}
close $fp
add_files -fileset constrs_1 $xdc
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {error "QC-LDPC synthesis failed"}
open_run synth_1
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing.rpt]
close_project
