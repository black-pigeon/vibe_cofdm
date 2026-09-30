# Synthesize the bounded codeword FIFO + replicated decoder scheduler.
# This measures the integration cost; the shared replay memory has one
# synchronous read stream per active lane. A generated Xilinx dual-port/
# multi-bank FIFO should replace it in the final XC7Z020 implementation.
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set lanes 9
if {$argc > 0} {set lanes [lindex $argv 0]}
if {![string is integer -strict $lanes] || $lanes < 1 || $lanes > 27} {error "LANES must be 1..27"}
set report_dir [file join $script_dir reports_qcldpc_scheduler L$lanes]
file mkdir $report_dir
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_edge_rom.sv]
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_648_decoder.sv]
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_parallel_bank.sv]
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_codeword_scheduler.sv]
read_xdc [file join $script_dir parallel_clock.xdc]
synth_design -mode out_of_context -top cofdm_qcldpc_codeword_scheduler \
  -part xc7z020clg400-2 -generic "LANES=$lanes FIFO_DEPTH=[expr {$lanes+1}] MAX_ITERS=12"
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing.rpt]
puts "QCLDPC scheduler synthesis complete: LANES=$lanes"
