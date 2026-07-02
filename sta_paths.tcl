project_open Life -revision Life
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path -file output_files/Life.worst_setup.rpt
project_close
