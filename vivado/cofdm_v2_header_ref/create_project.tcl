set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl]]
create_project cofdm_v2_header_ref [file join $script_dir project] -part xc7z020clg400-2 -force
add_files [list [file join $rtl_dir cofdm_v2_header_decoder.sv] [file join $rtl_dir cofdm_v2_header_frontend.sv] [file join $rtl_dir cofdm_v2_rx_header_path.sv]]
set_property file_type SystemVerilog [get_files *.sv]
set_property top cofdm_v2_header_decoder [get_filesets sources_1]
update_compile_order -fileset sources_1
