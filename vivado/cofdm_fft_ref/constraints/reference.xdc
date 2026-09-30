create_clock -name cofdm_clk -period 8.138 [get_ports aclk]
set_input_delay 0.0 -clock cofdm_clk [get_ports {aresetn in_valid in_symbol_start in_re in_im}]
set_output_delay 0.0 -clock cofdm_clk [get_ports {in_ready out_valid out_re out_im out_last out_user frame_started fft_overflow input_halt output_halt config_done accepted_fft_samples}]
