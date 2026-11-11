# Run from the repository root against the routed DDR3 design
set repo [file normalize [file join [file dirname [info script]] ../../../..]]
set dcp [file join $repo hdl/build/BlueJPEG_PA200T_UDP_mig/BlueJPEG_PA200T_UDP/BlueJPEG_PA200T_UDP_physopt.dcp]
set out [file join $repo hdl/build/udp_encoder_analysis]
set argv [list --dcp $dcp --out [file join $out primitives.tsv]]
source [file join $repo dep/bluelens/collect_vivado_primitives.tcl]

# BlueLens excludes constant cells and distributed RAM macro parents
# Keep the leaf memory cells, and use native Vivado LUT combining accounting
set encoder [get_cells -hier -filter {IS_PRIMITIVE && NAME =~ *i_sys_i_enc*}]
set selected {}
foreach cell $encoder {
    if {![skip_ref [get_property REF_NAME $cell]]} {
        lappend selected $cell
    }
}
if {![llength $selected]} { error "encoder cells not found" }
report_utilization -cells $selected -file [file join $out encoder_utilization.rpt]

# Internal register-to-register paths, excluding incoming system reset paths
set encoder_seq [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ *i_sys_i_enc*}]
report_timing -from $encoder_seq -to $encoder_seq -delay_type max -max_paths 10 -nworst 1 -path_type full_clock_expanded -file [file join $out encoder_timing.rpt]
report_timing -delay_type max -max_paths 10 -nworst 1 -path_type full_clock_expanded -file [file join $out system_timing.rpt]
