# Synthesize one standalone encoder configuration for resource accounting
# Routed critical paths are reported from the complete UDP design checkpoint
set constraint_file [file join $project_dir encoder_resource.xdc]
set handle [open $constraint_file w]
puts $handle {create_clock -period 12.307692 -name encoder_clk [get_ports aclk]}
puts $handle {set_false_path -from [get_ports aresetn]}
close $handle
read_xdc $constraint_file
synth_design -mode out_of_context -top $top_module
opt_design
report_utilization -file $project_dir/${project_name}_util.rpt
report_utilization -hierarchical -file $project_dir/${project_name}_util_hier.rpt
write_checkpoint -force $project_dir/${project_name}_synth.dcp
