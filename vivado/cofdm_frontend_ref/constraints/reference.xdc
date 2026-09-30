create_clock -name cofdm_clk -period 8.138 [get_ports clk]
set_input_delay 0.0 -clock cofdm_clk [get_ports {rst clear_phase sample_valid sample_re sample_im phase_inc}]
set_output_delay 0.0 -clock cofdm_clk [get_ports {metric_valid sync_hit sync_index corrected_valid corrected_re corrected_im phase_dbg cfo_valid cfo_angle_turns cfo_phase_inc}]
