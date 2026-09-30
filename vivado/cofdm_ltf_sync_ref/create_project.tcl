set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
create_project cofdm_ltf_sync_ref $proj_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set ip_dir [file normalize [file join $proj_dir ip]]
file mkdir $ip_dir
set coe_file [file normalize [file join $script_dir cofdm_ltf_template.coe]]
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 \
  -module_name cofdm_ltf_template_rom_ip -dir $ip_dir
set ltf_rom_ip [get_ips cofdm_ltf_template_rom_ip]
set_property -dict [list \
  CONFIG.Memory_Type {Single_Port_ROM} \
  CONFIG.Write_Width_A {32} \
  CONFIG.Write_Depth_A {256} \
  CONFIG.Read_Width_A {32} \
  CONFIG.Enable_A {Always_Enabled} \
  CONFIG.Load_Init_File {true} \
  CONFIG.Coe_File $coe_file \
  CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
  CONFIG.Read_Latency_A {1}] $ltf_rom_ip
generate_target all $ltf_rom_ip
foreach f {cofdm_ltf_template_rom.sv cofdm_ltf_template_rom_xilinx.sv cofdm_ltf_freq_rom.sv cofdm_ltf_rot_rom.sv cofdm_ltf_channel_estimator.sv cofdm_ltf_sample_buffer.sv cofdm_ltf_time_matcher.sv cofdm_ltf_time_matcher_tdm.sv cofdm_ltf_search_ctrl.sv cofdm_ltf_sync_capture_frontend.sv cofdm_nco_ltf_sync_bridge.sv cofdm_sync_ltf_cfo_top.sv cofdm_pre_fft_replay_mem.sv cofdm_pre_fft_replay.sv cofdm_pre_fft_stream_replay.sv cofdm_sync_pre_fft_frontend.sv cofdm_sync_pre_fft_stream_frontend.sv cofdm_stf_sync_frontend.sv cofdm_cfo_angle_estimator.sv cofdm_cfo_control.sv cofdm_cfo_nco_rotator.sv cofdm_capture_ctrl.sv cofdm_ltf_fine_cfo_accum.sv cofdm_ltf_fft_stream_adapter.sv cofdm_cordic_atan2.sv cofdm_fine_cfo_phase_to_inc.sv cofdm_ltf_fine_cfo_chain.sv} {
  add_files -fileset sources_1 [file join $rtl_dir $f]
}
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sources_1] *.sv]
add_files -fileset sim_1 [file join $rtl_dir tb tb_ltf_sync_capture_frontend.sv]
add_files -fileset sim_1 [file join $rtl_dir tb tb_ltf_sync_capture_frontend_tdm.sv]
add_files -fileset sim_1 [file join $rtl_dir tb tb_sync_ltf_cfo_top.sv]
add_files -fileset sim_1 [file join $rtl_dir tb tb_sync_pre_fft_frontend.sv]
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sim_1] *.sv]
set xdc [file join $script_dir constraints reference.xdc]
file mkdir [file dirname $xdc]
add_files -fileset constrs_1 $xdc
set_property top cofdm_ltf_sync_capture_frontend [get_filesets sources_1]
set_property top tb_ltf_sync_capture_frontend [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
