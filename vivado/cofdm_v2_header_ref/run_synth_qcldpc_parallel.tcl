# Out-of-context resource/timing sweep for 3/9/27 replicated QC-LDPC lanes.
# Usage: vivado -mode batch -source run_synth_qcldpc_parallel.tcl -tclargs 3
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
if {$argc < 1} { error "lane count is required (3, 9 or 27)" }
set lanes [lindex $argv 0]
if {![string is integer -strict $lanes] || ![expr {$lanes == 3 || $lanes == 9 || $lanes == 27}]} {
    error "lane count must be 3, 9 or 27"
}
set report_dir [file join $script_dir reports_qcldpc_parallel L$lanes]
file mkdir $report_dir
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_edge_rom.sv]
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_648_decoder.sv]
read_verilog -sv [file join $rtl_dir cofdm_qcldpc_parallel_bank.sv]
read_xdc [file join $script_dir parallel_clock.xdc]
synth_design -top cofdm_qcldpc_parallel_bank -part xc7z020clg400-2 \
    -generic "LANES=$lanes MAX_ITERS=12"
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing.rpt]
report_power -file [file join $report_dir power.rpt]
puts "QCLDPC parallel synthesis complete: LANES=$lanes"
