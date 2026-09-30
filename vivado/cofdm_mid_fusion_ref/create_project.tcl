# Create the XC7Z020 reference project used by the COFDM PHY work.
set script_dir [file normalize [file dirname [info script]]]
set proj_dir   [file normalize [file join $script_dir project]]
set part_name  xc7z020clg400-2
file mkdir $proj_dir
create_project cofdm_mid_fusion_ref $proj_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
set src_files [list \
  [file join $rtl_dir cofdm_mid_fusion_ctrl_bram.sv] \
  [file join $rtl_dir cofdm_mid_fusion_ref_top.sv] \
  [file join $rtl_dir cofdm_fusion_lane.sv] \
  [file join $rtl_dir cofdm_quadrant_select.sv]]
add_files -fileset sources_1 $src_files
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sources_1] *.sv]

set xdc_file [file join $script_dir constraints reference.xdc]
file mkdir [file dirname $xdc_file]
add_files -fileset constrs_1 $xdc_file

set sim_files [list [file join $rtl_dir tb tb_cofdm_mid_fusion_ref.sv]]
add_files -fileset sim_1 $sim_files
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_cofdm_mid_fusion_ref [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property top cofdm_mid_fusion_ref_top [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_Explore [get_runs impl_1]
puts "COFDM project created: $proj_dir"
close_project
