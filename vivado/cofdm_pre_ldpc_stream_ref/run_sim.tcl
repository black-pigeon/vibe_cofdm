source [file join [file dirname [info script]] create_project.tcl]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
launch_simulation
close_sim
close_project
