set script_dir [file dirname [file normalize [info script]]]
set constr_dir [file normalize [file join $script_dir .. constr]]
set hdl_dir [file normalize [file join $script_dir .. .. .. ..]]
set eth_dir [file normalize [file join $hdl_dir .. dep verilog-ethernet]]
foreach rom [glob -nocomplain [file join $hdl_dir rom *.mem]] {
    file copy -force $rom [pwd]
    add_files -norecurse $rom
}
foreach name {system jtag mdio rgmii} {
    read_xdc [file join $constr_dir ${name}.xdc]
}
set use_mig [expr {[llength [get_files -quiet *mig_wrapper.v]] != 0}]
if {$use_mig} {
    source [file join $script_dir .. ip mig.tcl]
}
synth_design -top $top_module
set delay_cells [get_cells -hier -filter {(REF_NAME == IDELAYE2 || REF_NAME == IDELAYCTRL) && NAME =~ *i_eth*}]
set_property IODELAY_GROUP rgmii_rx_grp $delay_cells
foreach path {
    syn/vivado/rgmii_phy_if.tcl
    syn/vivado/eth_mac_1g_rgmii.tcl
    syn/vivado/eth_mac_fifo.tcl
    lib/axis/syn/vivado/axis_async_fifo.tcl
    lib/axis/syn/vivado/sync_reset.tcl
} {
    source [file join $eth_dir $path]
}
read_xdc [file join $constr_dir cdc.xdc]
set config_sync [get_cells -hier -filter {NAME =~ *cfg_*_sync1_reg*}]
if {[llength $config_sync]} {
    set_max_delay -datapath_only 12.0 -from [all_clocks] -to [get_pins -of_objects $config_sync -filter {REF_PIN_NAME == D}]
}
opt_design
report_utilization -file $project_dir/${project_name}_util1.rpt
place_design
route_design
phys_opt_design
report_timing_summary -file $project_dir/${project_name}_tim3.rpt
report_utilization -file $project_dir/${project_name}_util3.rpt
report_utilization -hierarchical -file $project_dir/${project_name}_util3_hier.rpt
report_drc -file $project_dir/${project_name}_drc3.rpt
report_methodology -file $project_dir/${project_name}_method3.rpt
report_clock_interaction -file $project_dir/${project_name}_clocks3.rpt
write_checkpoint -force $project_dir/${project_name}_physopt.dcp
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "Final WNS: $wns, WHS: $whs"
if {$wns < 0 || $whs < 0} { error "UDP design failed timing" }
if {[get_msg_config -count -severity {CRITICAL WARNING}] != 0} {
    error "UDP build has critical warnings"
}
set bitstream_file [file join $project_dir ${project_name}_out_[format %.3f $wns]ns.bit]
write_bitstream -force -file $bitstream_file
write_cfgmem -force -format mcs -size 16 -interface SPIx4 \
    -loadbit [list up 0x00000000 $bitstream_file] \
    -file [file join $project_dir ${project_name}_out.mcs]
