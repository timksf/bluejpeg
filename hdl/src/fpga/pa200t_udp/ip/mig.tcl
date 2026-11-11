set mig_script_dir [file dirname [file normalize [info script]]]
set mig_ip_dir [file normalize [file join $project_dir mig_ip]]
file mkdir $mig_ip_dir
create_ip -name mig_7series -vendor xilinx.com -library ip -module_name mig_7series_0 -dir $mig_ip_dir
set_property CONFIG.XML_INPUT_FILE [file join $mig_script_dir mig.prj] [get_ips mig_7series_0]
generate_target all [get_ips mig_7series_0]
create_ip_run [get_ips mig_7series_0]
launch_runs mig_7series_0_synth_1 -jobs 2
wait_on_run mig_7series_0_synth_1
if {[get_property PROGRESS [get_runs mig_7series_0_synth_1]] ne "100%"} {
    error "MIG out of context synthesis failed"
}
# Check the generated primitive parameters, the XML frequency is rounded by the wizard
set mig_rtl [get_files -all -quiet *mig_7series_0_mig.v]
if {[llength $mig_rtl] != 1} { error "Cannot find the generated MIG clock parameters" }
set handle [open $mig_rtl r]
set content [read $handle]
close $handle
if {![regexp {parameter CLKIN_PERIOD\s*=\s*5000,} $content]} {
    error "MIG must use the board's 5000 ps system input"
}
