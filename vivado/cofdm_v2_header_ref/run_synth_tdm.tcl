set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set report_dir [file join $script_dir reports_tdm]
file mkdir $report_dir
create_project cofdm_v2_header_tdm_ref [file join $script_dir project_tdm] -part xc7z020clg400-2 -force
add_files [file join $rtl_dir cofdm_v2_header_decoder_tdm.sv]
set_property file_type SystemVerilog [get_files *.sv]
set_property top cofdm_v2_header_decoder_tdm [get_filesets sources_1]
update_compile_order -fileset sources_1
synth_design -top cofdm_v2_header_decoder_tdm -part xc7z020clg400-2
create_clock -name clk -period 8.138 [get_ports clk]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing.rpt]
close_project
