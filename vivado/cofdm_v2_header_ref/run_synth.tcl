source [file join [file dirname [info script]] create_project.tcl]
set report_dir [file join $script_dir reports]
file mkdir $report_dir
synth_design -top cofdm_v2_header_decoder -part xc7z020clg400-2
create_clock -name clk -period 8.138 [get_ports clk]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing.rpt]
close_project
