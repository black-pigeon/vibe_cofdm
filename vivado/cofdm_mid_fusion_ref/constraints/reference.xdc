# Virtual clock for out-of-context/reference timing.  8.138 ns = 122.88 MHz.
# Board pin assignments are intentionally absent until the Zynq carrier board
# and ADC clocking scheme are fixed.
create_clock -name cofdm_clk -period 8.138 [get_ports clk]
set_input_delay 0.0 -clock cofdm_clk [get_ports {rst start sample_valid sample_last sample_pilot old_re old_im fresh_re fresh_im old_var fresh_var result_ready}]
set_output_delay 0.0 -clock cofdm_clk [get_ports {busy done result_valid result_last result_re result_im fifo_full fifo_empty}]
