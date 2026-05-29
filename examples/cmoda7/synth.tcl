read_xdc [file dirname $script_path]/cmoda7.xdc
synth_design -top cmod_jpeg_top
puts "Finished synth_design"

# implement
opt_design
puts "Finished opt_design"

report_timing_summary -file $project_dir/${project_name}_tim1.rpt
report_utilization -file $project_dir/${project_name}_util1.rpt
report_drc -file $project_dir/${project_name}_drc1.rpt

write_checkpoint -force $project_dir/${project_name}_drc.dcp

place_design
puts "Finished place_design"

route_design
puts "Finished route_design"

report_timing_summary -file $project_dir/${project_name}_tim_route.rpt
report_utilization -file $project_dir/${project_name}_util_route.rpt

write_checkpoint -force $project_dir/${project_name}_pnr.dcp

phys_opt_design
puts "Finished phys_opt_design"

phys_opt_design -directive ExploreWithAggressiveHoldFix
puts "Finished phys_opt_design -directive ExploreWithAggressiveHoldFix"

report_timing_summary -file $project_dir/${project_name}_tim_physopt_route.rpt
report_timing -delay_type min -max_paths 50 -file $project_dir/${project_name}_hold_physopt_route.rpt
report_timing -delay_type min -from [get_clocks clk_100] -to [get_clocks clk_dct] -max_paths 50 -file $project_dir/${project_name}_hold_100_to_dct.rpt
report_timing -delay_type min -from [get_clocks clk_100] -to [get_clocks clk_100] -max_paths 50 -file $project_dir/${project_name}_hold_100.rpt
report_utilization -file $project_dir/${project_name}_util_physopt_route.rpt
report_drc -file $project_dir/${project_name}_drc_physopt_route.rpt

write_checkpoint -force $project_dir/${project_name}_physopt.dcp

write_bitstream -force $project_dir/${project_name}.bit
puts "Finished write_bitstream"
