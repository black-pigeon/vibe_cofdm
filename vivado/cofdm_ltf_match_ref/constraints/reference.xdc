create_clock -name cofdm_clk -period 8.138 [get_ports clk]
set_input_delay 0.0 -clock cofdm_clk [get_ports {rst sample_valid sample_re sample_im search_start search_base_index}]
set_output_delay 0.0 -clock cofdm_clk [get_ports {search_ready search_busy peak_valid peak_score peak_index peak_corr_re peak_corr_im peak_energy search_error}]
