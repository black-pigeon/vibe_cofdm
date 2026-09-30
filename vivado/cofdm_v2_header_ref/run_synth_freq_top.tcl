set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set report_dir [file join $script_dir reports_freq_top]
file mkdir $report_dir
create_project cofdm_phy_rx_v2_freq_ref [file join $script_dir project_freq_top] -part xc7z020clg400-2 -force
foreach f {cofdm_phase_lut cofdm_common_phase_rotator cofdm_cordic_atan2 cofdm_pilot_phase_accum cofdm_matched_llr cofdm_pre_ldpc_symbol cofdm_pilot_prbs cofdm_symbol_pilots cofdm_header_descrambler cofdm_llr_packetizer cofdm_llr_fifo cofdm_pre_ldpc_stream cofdm_v2_header_decoder_tdm cofdm_v2_rx_header_path cofdm_ltf_freq_rom cofdm_ltf_fft_stream_adapter cofdm_ltf_channel_estimator cofdm_ltf_channel_chain cofdm_phy_rx_v2_freq_top} {
  add_files [file join $rtl_dir $f.sv]
}
set_property file_type SystemVerilog [get_files *.sv]
set_property verilog_define {COFDM_XILINX_FIFO} [get_filesets sources_1]
set_property top cofdm_phy_rx_v2_freq_top [get_filesets sources_1]
update_compile_order -fileset sources_1
synth_design -top cofdm_phy_rx_v2_freq_top -part xc7z020clg400-2
create_clock -name clk -period 8.138 [get_ports clk]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing.rpt]
report_power -file [file join $report_dir power.rpt]
close_project
puts "COFDM frequency-domain v2 integration synthesis completed"
