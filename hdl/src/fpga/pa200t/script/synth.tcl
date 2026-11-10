# PA200T-Starlite build for the BlueJPEG test design, sourced by BSVTools mkVivadoTCL
# (make bitstream). Provided variables: project_dir, project_name, top_module, src_path.

set script_dir [file dirname [file normalize [info script]]]
set constr_dir [file normalize [file join $script_dir .. constr]]
set hdl_dir    [file normalize [file join $script_dir .. .. .. ..]]

# pattern ROM image, $readmemh resolves the bare file name in the working directory
foreach rom [glob -nocomplain [file join $hdl_dir rom *.mem]] {
    file copy -force $rom [pwd]
    add_files -norecurse $rom
}

read_xdc [file join $constr_dir system.xdc]
read_xdc [file join $constr_dir jtag.xdc]
read_xdc [file join $constr_dir uart.xdc]

synth_design -top $top_module
puts "Finished synth_design"

# needs the PLL output clocks, which only exist after synthesis
read_xdc [file join $constr_dir cdc.xdc]

opt_design

report_timing_summary -file $project_dir/${project_name}_tim1.rpt
report_utilization -file $project_dir/${project_name}_util1.rpt
report_utilization -hierarchical -file $project_dir/${project_name}_util1_hier.rpt
report_drc -file $project_dir/${project_name}_drc1.rpt
puts "Finished opt_design"

place_design

report_timing_summary -file $project_dir/${project_name}_tim2.rpt
report_utilization -file $project_dir/${project_name}_util2.rpt
puts "Finished place_design"

route_design
puts "Finished route_design"

phys_opt_design
puts "Finished phys_opt_design"

report_timing_summary -file $project_dir/${project_name}_tim3.rpt
report_utilization -file $project_dir/${project_name}_util3.rpt
report_utilization -hierarchical -file $project_dir/${project_name}_util3_hier.rpt
report_clock_interaction -file $project_dir/${project_name}_clocks3.rpt
report_drc -file $project_dir/${project_name}_drc3.rpt
report_methodology -file $project_dir/${project_name}_method3.rpt

write_checkpoint $project_dir/${project_name}_physopt.dcp -force

# tag outputs with the final setup WNS, e.g. BlueJPEG_PA200T_out_0.412ns.bit
set wns_path [get_timing_paths -max_paths 1 -nworst 1 -setup]
set wns [expr {[llength $wns_path] ? [get_property SLACK $wns_path] : ""}]
set wns_tag [expr {[string is double -strict $wns] ? [format "%.3fns" $wns] : "na"}]
puts "Final WNS: $wns_tag"

set out_base       ${project_name}_out_${wns_tag}
set bitstream_file [file join $project_dir ${out_base}.bit]
write_bitstream -force -file $bitstream_file

# PA200T-Starlite U7: W25Q128JVSIQ, 128 Mbit (16 MiB), quad SPI.
# Hardware Manager configuration memory part: w25q128jvq-spi-x1_x2_x4.
write_cfgmem -force -format mcs -size 16 -interface SPIx4 \
    -loadbit [list up 0x00000000 $bitstream_file] \
    -file [file join $project_dir ${out_base}.mcs]
puts "Finished configuration memory generation"
