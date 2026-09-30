set d [file normalize [file dirname [info script]]]
set p [file join $d probe_project]
create_project probe_fft $p -part xc7z020clg400-2 -force
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name cofdm_fft_256
set ip [get_ips cofdm_fft_256]
set_property -dict [list \
  CONFIG.Component_Name {cofdm_fft_256} \
  CONFIG.transform_length {256} \
  CONFIG.data_format {fixed_point} \
  CONFIG.input_width {16} \
  CONFIG.phase_factor_width {16} \
  CONFIG.implementation_options {pipelined_streaming_io} \
  CONFIG.output_ordering {natural_order} \
  CONFIG.scaling_options {scaled} \
  CONFIG.throttle_scheme {nonrealtime} \
  CONFIG.target_data_throughput {100} \
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
report_property $ip
close_project
