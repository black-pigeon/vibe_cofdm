create_clock -name cofdm_clk -period 8.138 [get_ports clk]
set_input_delay 0.0 -clock cofdm_clk [get_ports {rst fft_out_valid fft_out_last fft_out_re fft_out_im}]
set_output_delay 0.0 -clock cofdm_clk [get_ports {fft_out_ready channel_valid channel_last channel_bin channel_re channel_im channel_done channel_ready channel_error noise_variance noise_valid noise_sample_count h_rd_re h_rd_im h_valid}]
