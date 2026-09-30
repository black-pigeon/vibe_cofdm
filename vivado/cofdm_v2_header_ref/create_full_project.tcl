set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set report_dir [file join $script_dir reports_full_top]
file mkdir $report_dir
create_project cofdm_phy_rx_v2_ref [file join $script_dir project_full_top] -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set common {cofdm_stf_sync_frontend cofdm_cfo_angle_estimator cofdm_cfo_control cofdm_cfo_nco_rotator cofdm_ltf_template_rom cofdm_ltf_sample_buffer cofdm_ltf_time_matcher cofdm_ltf_time_matcher_tdm cofdm_ltf_search_ctrl cofdm_ltf_sync_capture_frontend cofdm_nco_ltf_sync_bridge cofdm_capture_ctrl cofdm_ltf_rot_rom cofdm_ltf_fine_cfo_accum cofdm_ltf_fft_stream_adapter cofdm_cordic_atan2 cofdm_fine_cfo_phase_to_inc cofdm_ltf_fine_cfo_chain cofdm_sync_ltf_cfo_top cofdm_pre_fft_replay_mem cofdm_pre_fft_stream_replay cofdm_sync_pre_fft_stream_frontend cofdm_fft_stream_frontend cofdm_phase_lut cofdm_common_phase_rotator cofdm_pilot_phase_accum cofdm_matched_llr cofdm_pre_ldpc_symbol cofdm_pilot_prbs cofdm_symbol_pilots cofdm_header_descrambler cofdm_llr_packetizer cofdm_llr_fifo cofdm_pre_ldpc_stream cofdm_v2_header_decoder_tdm cofdm_v2_rx_header_path cofdm_ltf_freq_rom cofdm_ltf_channel_estimator cofdm_ltf_channel_chain cofdm_phy_rx_v2_freq_top cofdm_phy_rx_v2_top cofdm_qcldpc_edge_rom cofdm_qcldpc_648_decoder cofdm_payload_codeword_bridge cofdm_payload_postprocess cofdm_payload_rx cofdm_phy_rx_v2_payload_top}
foreach f $common { add_files [file join $rtl_dir $f.sv] }
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name cofdm_fft_256
set ip [get_ips cofdm_fft_256]
set_property -dict [list \
  CONFIG.transform_length {256} CONFIG.data_format {fixed_point} \
  CONFIG.input_width {16} CONFIG.phase_factor_width {16} \
  CONFIG.implementation_options {pipelined_streaming_io} \
  CONFIG.output_ordering {natural_order} CONFIG.scaling_options {scaled} \
  CONFIG.throttle_scheme {nonrealtime} CONFIG.aclken {false} \
  CONFIG.aresetn {true} CONFIG.channels {1} \
  CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.memory_options_data {block_ram} CONFIG.rounding_modes {convergent_rounding} \
  CONFIG.ovflo {true} CONFIG.xk_index {false}] $ip
generate_target all [get_ips $ip]
set_property file_type SystemVerilog [get_files *.sv]
set_property top cofdm_phy_rx_v2_top [get_filesets sources_1]
set_property verilog_define {COFDM_XILINX_FIFO COFDM_XILINX_RAMB} [get_filesets sources_1]
update_compile_order -fileset sources_1
