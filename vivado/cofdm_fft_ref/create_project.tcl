set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
create_project cofdm_fft_ref $proj_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
add_files -fileset sources_1 [file join $rtl_dir cofdm_fft_stream_frontend.sv]
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sources_1] *.sv]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name cofdm_fft_256
set ip [get_ips cofdm_fft_256]
set_property -dict [list \
  CONFIG.transform_length {256} \
  CONFIG.data_format {fixed_point} \
  CONFIG.input_width {16} \
  CONFIG.phase_factor_width {16} \
  CONFIG.implementation_options {pipelined_streaming_io} \
  CONFIG.output_ordering {natural_order} \
  CONFIG.scaling_options {scaled} \
  CONFIG.throttle_scheme {nonrealtime} \
  CONFIG.aclken {false} \
  CONFIG.aresetn {true} \
  CONFIG.channels {1} \
  CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.memory_options_data {block_ram} \
  CONFIG.rounding_modes {convergent_rounding} \
  CONFIG.ovflo {true} \
  CONFIG.xk_index {false}] $ip
generate_target all [get_ips $ip]
export_ip_user_files -of_objects [get_ips $ip] -no_script -sync -force
add_files -fileset sim_1 [file join $rtl_dir tb tb_fft_stream_frontend.sv]
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top cofdm_fft_stream_frontend [get_filesets sources_1]
set_property top tb_fft_stream_frontend [get_filesets sim_1]
set_property xsim.simulate.runtime {20 us} [get_filesets sim_1]
set xdc [file join $script_dir constraints reference.xdc]
file mkdir [file dirname $xdc]
add_files -fileset constrs_1 $xdc
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
