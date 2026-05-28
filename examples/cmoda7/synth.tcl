read_xdc [file dirname $script_path]/cmoda7.xdc
synth_design -top cmod_jpeg_top
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

write_checkpoint -force $project_dir/${project_name}_pnr.dcp
puts "Finished place_design"
