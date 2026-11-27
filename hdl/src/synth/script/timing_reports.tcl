proc timing_reports {stage} {
    global project_dir project_name
    set prefix $project_dir/${project_name}_${stage}
    report_timing_summary -report_unconstrained -file ${prefix}_summary.rpt
    report_timing -delay_type max -max_paths 50 -nworst 1 -file ${prefix}_paths.rpt
    foreach clock [get_clocks] {
        set name [get_property NAME $clock]
        report_timing -from $clock -to $clock -delay_type max -max_paths 30 -nworst 1 -file ${prefix}_${name}.rpt
    }
    foreach module {i_img_tiler i_stuffer i_huff i_tables i_rle i_du_proc i_fwriter i_csrs i_axi_csrs i_markers i_frames i_bits i_rld i_dequant i_dezz i_idct i_merger i_untiler} {
        set cells [get_cells -hier -filter "IS_SEQUENTIAL && NAME =~ *${module}*"]
        if {[llength $cells]} {
            report_timing -from $cells -to $cells -delay_type max -max_paths 10 -nworst 1 -file ${prefix}_${module}.rpt
        }
    }
    report_utilization -file ${prefix}_util.rpt
}

