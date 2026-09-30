create_clock -name cofdm_clk -period 8.138 [get_ports clk]
set_input_delay 0.0 -clock cofdm_clk [get_ports {rst fft_valid fft_symbol_start fft_last fft_symbol_id fft_bin_index fft_bin_active fft_re fft_im rot_re rot_im}]
set_output_delay 0.0 -clock cofdm_clk [get_ports {ltf1_stored fine_sum_valid fine_sum_re fine_sum_im active_count}]
