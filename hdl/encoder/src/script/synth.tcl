set script_dir [file dirname [file normalize [info script]]]

read_xdc $script_dir/constr.xdc
synth_design -top $top_module -mode out_of_context
puts "Finished synth_design"

# implement
opt_design

report_timing_summary -file $project_dir/${project_name}_tim1.rpt
report_utilization -file $project_dir/${project_name}_util1.rpt
report_drc -file $project_dir/${project_name}_drc1.rpt
puts "Finished opt_design"

write_checkpoint -force $project_dir/${project_name}_drc.dcp
place_design

report_timing_summary -file $project_dir/${project_name}_tim2.rpt
report_utilization -file $project_dir/${project_name}_util2.rpt
puts "Finished place_design"

write_checkpoint -force $project_dir/${project_name}_place.dcp
