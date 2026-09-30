set script_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize [file join $script_dir project]]
create_project cofdm_capture_ref $proj_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
add_files -fileset sources_1 [list \
  [file join $rtl_dir cofdm_stf_sync_frontend.sv] \
  [file join $rtl_dir cofdm_cfo_nco_rotator.sv] \
  [file join $rtl_dir cofdm_cfo_angle_estimator.sv] \
  [file join $rtl_dir cofdm_capture_ctrl.sv] \
  [file join $rtl_dir cofdm_capture_ref_top.sv]]
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sources_1] *.sv]
set xdc_file [file normalize [file join $script_dir .. cofdm_frontend_ref constraints reference.xdc]]
if {[file exists $xdc_file]} { add_files -fileset constrs_1 $xdc_file }
add_files -fileset sim_1 [file join $rtl_dir tb tb_capture_ctrl.sv]
set_property file_type {SystemVerilog} [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top cofdm_capture_ref_top [get_filesets sources_1]
set_property top tb_capture_ctrl [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
