# Reimplement an existing full-system checkpoint after updating CDC constraints
if {$argc != 2} { error "Usage: reimplement.tcl checkpoint.dcp output_directory" }
set script_dir [file dirname [file normalize [info script]]]
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
file mkdir $output_dir
set_param general.maxThreads 8
open_checkpoint $checkpoint
source [file join $script_dir .. constr cdc.xdc]
if {[llength $app] != 1 || [llength $dct] != 1} {
    error "Checkpoint must use the related PLL application and DCT clocks"
}
write_checkpoint -force [file join $output_dir constrained.dcp]
place_design
phys_opt_design -directive AggressiveFanoutOpt
route_design
phys_opt_design
source [file join $script_dir refine_timing.tcl]
report_timing_summary -file [file join $output_dir timing.rpt]
report_timing -max_paths 30 -nworst 3 -file [file join $output_dir paths.rpt]
report_utilization -file [file join $output_dir utilization.rpt]
report_clock_interaction -file [file join $output_dir clocks.rpt]
report_cdc -details -file [file join $output_dir cdc.rpt]
report_bus_skew -file [file join $output_dir bus_skew.rpt]
if {[regexp {\(VIOLATED\)} [report_bus_skew -return_string]]} {
    error "UDP demo failed CDC bus skew bounds"
}
report_drc -file [file join $output_dir drc.rpt]
write_checkpoint -force [file join $output_dir routed.dcp]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "Final WNS: $wns, WHS: $whs"
if {$wns < 0 || $whs < 0} { error "UDP demo failed timing" }
if {[get_msg_config -count -severity {CRITICAL WARNING}] != 0} {
    error "UDP demo has critical warnings"
}
write_bitstream -force [file join $output_dir bluejpeg_demo_200.bit]
