#per-module cell counts of a routed decoder checkpoint, grouped by instance-name prefix because bsc flattens the core
#usage: vivado -mode batch -source decoder_module_stats.tcl -tclargs <checkpoint> <outfile>
set dcp [lindex $argv 0]
set out [open [lindex $argv 1] w]
open_checkpoint $dcp
set prefixes {i_markers i_frames i_tables i_bits i_huff i_rld i_dequant i_dezz i_idct i_merger i_untiler i_csrs i_axi_csrs i_axis_rd i_axis_wr}
set all [get_cells -hier -filter {IS_PRIMITIVE}]
set seen {}
puts $out [format "%-12s %7s %7s %7s %6s %5s %6s" module LUT FF LUTRAM CARRY BRAM DSP]
proc count {cells} {
    set lut 0; set ff 0; set lram 0; set car 0; set bram 0.0; set dsp 0
    foreach c $cells {
        set r [get_property REF_NAME $c]
        switch -glob $r {
            LUT*    {incr lut}
            FD*     {incr ff}
            RAMD* - RAMS* - RAM32M* - RAM64M* - RAM128* - RAM256* {incr lram}
            CARRY*  {incr car}
            RAMB36* {set bram [expr {$bram + 1.0}]}
            RAMB18* {set bram [expr {$bram + 0.5}]}
            DSP*    {incr dsp}
        }
    }
    return [list $lut $ff $lram $car $bram $dsp]
}
set used {}
foreach p $prefixes {
    #a wrapper top that instantiates the core as ifc adds that prefix to every name
    set cells [filter $all "NAME =~ ${p}* || NAME =~ */${p}* || NAME =~ ifc_${p}* || NAME =~ */ifc_${p}*"]
    set cells [filter $cells "NAME !~ ${p}_*_csrs* && NAME !~ ifc_${p}_*_csrs*"]
    foreach c $cells {dict set used $c 1}
    lassign [count $cells] lut ff lram car bram dsp
    puts $out [format "%-12s %7d %7d %7d %6d %5.1f %6d" $p $lut $ff $lram $car $bram $dsp]
}
set rest {}
foreach c $all { if {![dict exists $used $c]} {lappend rest $c} }
lassign [count $rest] lut ff lram car bram dsp
puts $out [format "%-12s %7d %7d %7d %6d %5.1f %6d" other $lut $ff $lram $car $bram $dsp]
lassign [count $all] lut ff lram car bram dsp
puts $out [format "%-12s %7d %7d %7d %6d %5.1f %6d" total $lut $ff $lram $car $bram $dsp]
close $out
