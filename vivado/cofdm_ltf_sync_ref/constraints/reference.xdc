create_clock -name cofdm_clk -period 8.138 [get_ports clk]
set_input_delay 0.0 -clock cofdm_clk [get_ports {rst sample_valid sample_re sample_im stf_hit stf_index}]
set_output_delay 0.0 -clock cofdm_clk [get_ports {ltf_peak_valid ltf_peak_score ltf_peak_index ltf_peak_corr_re ltf_peak_corr_im ltf_peak_energy ltf_search_busy ltf_search_pending ltf_search_error}]
