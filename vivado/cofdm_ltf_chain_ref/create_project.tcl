set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
create_project cofdm_ltf_chain_ref $proj_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set rtl_files [list \
  cofdm_ltf_fine_cfo_accum.sv cofdm_ltf_fft_stream_adapter.sv \
  cofdm_cordic_atan2.sv cofdm_fine_cfo_phase_to_inc.sv \
  cofdm_ltf_fine_cfo_chain.sv]
foreach f $rtl_files { add_files -fileset sources_1 [file join $rtl_dir $f] }
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sources_1] *.sv]
add_files -fileset sim_1 [file join $rtl_dir tb tb_ltf_fine_cfo_chain.sv]
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sim_1] *.sv]
set xdc [file join $script_dir constraints reference.xdc]
file mkdir [file dirname $xdc]
add_files -fileset constrs_1 $xdc
set_property top cofdm_ltf_fine_cfo_chain [get_filesets sources_1]
set_property top tb_ltf_fine_cfo_chain [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
