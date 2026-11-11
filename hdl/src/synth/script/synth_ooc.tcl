set script_dir [file dirname [file normalize [info script]]]

set_param general.maxThreads 8
read_xdc [file join $script_dir .. constr ooc.xdc]
synth_design -top $top_module -mode out_of_context
puts "Finished synth_design"

source [file join $script_dir timing_reports.tcl]

opt_design
timing_reports opt

report_timing_summary -file $project_dir/${project_name}_tim1.rpt
report_utilization -file $project_dir/${project_name}_util1.rpt
report_drc -file $project_dir/${project_name}_drc1.rpt
puts "Finished opt_design"

write_checkpoint -force $project_dir/${project_name}_drc.dcp
place_design
timing_reports place

report_timing_summary -file $project_dir/${project_name}_tim2.rpt
report_utilization -file $project_dir/${project_name}_util2.rpt
puts "Finished place_design"

write_checkpoint -force $project_dir/${project_name}_place.dcp

phys_opt_design
route_design
timing_reports route
report_clock_interaction -file $project_dir/${project_name}_clock_interaction.rpt
report_drc -file $project_dir/${project_name}_route_drc.rpt
write_checkpoint -force $project_dir/${project_name}_route.dcp
