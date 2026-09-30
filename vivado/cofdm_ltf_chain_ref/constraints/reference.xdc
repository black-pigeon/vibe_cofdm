create_clock -name cofdm_clk -period 8.138 [get_ports clk]
set_input_delay 0.0 -clock cofdm_clk [get_ports {rst fft_out_valid fft_out_last fft_out_re fft_out_im rot_re rot_im}]
set_output_delay 0.0 -clock cofdm_clk [get_ports {fft_out_ready ltf1_stored fine_sum_valid fine_sum_re fine_sum_im active_count phase_valid phase phase_inc_valid phase_inc frame_error}]
