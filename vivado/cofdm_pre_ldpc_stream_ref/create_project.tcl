set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set repo_dir [file normalize [file join $rtl_dir .. ..]]
create_project cofdm_pre_ldpc_stream_ref [file join $script_dir project] -part xc7z020clg400-2 -force
set_property XPM_LIBRARIES {XPM_FIFO} [current_project]
foreach module {cofdm_phase_lut cofdm_common_phase_rotator cofdm_cordic_atan2 cofdm_pilot_phase_accum cofdm_matched_llr cofdm_pre_ldpc_symbol cofdm_symbol_pilots cofdm_llr_packetizer cofdm_llr_fifo cofdm_pre_ldpc_stream} {
    add_files [file join $rtl_dir $module.sv]
}
set_property verilog_define {COFDM_XILINX_FIFO} [get_filesets sources_1]
set_property top cofdm_pre_ldpc_stream [get_filesets sources_1]
add_files -fileset sim_1 [file join $rtl_dir tb tb_pre_ldpc_stream.sv]
set_property top tb_pre_ldpc_stream [get_filesets sim_1]
set_property verilog_define {COFDM_XILINX_FIFO} [get_filesets sim_1]
# Testbench uses repository-relative fixture names; copy only the fixtures
# into the isolated XSim working directory, without changing the testbench.
set sim_dir [file join $script_dir project cofdm_pre_ldpc_stream_ref.sim sim_1 behav xsim]
file mkdir [file join $sim_dir matlab vectors]
file copy -force [file join $repo_dir matlab vectors pre_ldpc_stream] [file join $sim_dir matlab vectors]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
