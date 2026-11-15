# Sourced after synthesis, so primitive names and generated clocks are available
# Keep application clocks together and except only explicit CDC paths below
set pll [get_cells -hier -filter {REF_NAME == PLLE2_ADV && NAME =~ *i_pll_i_pll_i_pll}]
set gtx [get_clocks -of_objects [get_pins -of_objects $pll -filter {REF_PIN_NAME == CLKOUT0 || REF_PIN_NAME == CLKOUT1}]]
set sys [get_clocks -of_objects [get_pins -hier -filter {REF_PIN_NAME == ui_clk || (REF_PIN_NAME == CLKOUT2 && NAME =~ *i_pll_i_pll_i_pll*)}]]
set dct [get_clocks -of_objects [get_pins -of_objects $pll -filter {REF_PIN_NAME == CLKOUT3}]]
set app [get_clocks -of_objects [get_pins -of_objects $pll -filter {REF_PIN_NAME == CLKOUT4}]]
set_clock_groups -asynchronous -group [get_clocks clk_200] \
    -group [concat $gtx $sys $app $dct] -group [get_clocks jtag_tck]

# The upstream Ethernet scripts retain their RGMII RX FIFO constraints
# Global asynchronous application groups would override these max delays
set memory_fifos [get_cells -quiet -hier -filter {NAME =~ *i_cdc_f_* && REF_NAME =~ SyncFIFO*}]
set encoder_fifos [get_cells -quiet -hier -filter {NAME =~ *i_encoder_cdc_f_* && REF_NAME =~ SyncFIFO*}]
if {[llength $memory_fifos] && [llength $memory_fifos] != 5} { error "Expected five DDR bridge channels" }
if {[llength $app] && [llength $encoder_fifos] != 8} { error "Expected eight encoder bridge channels" }
foreach fifo [concat $memory_fifos $encoder_fifos] {
    set sync_regs [get_cells -quiet -hier -filter "NAME =~ ${fifo}/dSyncReg1_reg* || NAME =~ ${fifo}/dEnqPtr_reg* || NAME =~ ${fifo}/sSyncReg1_reg* || NAME =~ ${fifo}/sDeqPtr_reg*"]
    if {![llength $sync_regs]} { error "Missing FIFO synchronizers in $fifo" }
    set_property ASYNC_REG TRUE $sync_regs
    set_property SHREG_EXTRACT NO $sync_regs
    foreach {source target} {sGEnqPtr dSyncReg1 dGDeqPtr sSyncReg1} {
        set from_regs [get_cells -quiet -hier -filter "NAME =~ ${fifo}/${source}_reg*"]
        set to_regs [get_cells -quiet -hier -filter "NAME =~ ${fifo}/${target}_reg*"]
        if {![llength $from_regs] || ![llength $to_regs]} { error "Missing Gray pointer in $fifo" }
        # Bound both transit time and bit skew by the fastest application period
        set_max_delay -datapath_only 5.0 -from $from_regs -to $to_regs
        set_bus_skew 5.0 -from $from_regs -to $to_regs
    }
    # Data stays stable until its synchronized write pointer is visible
    # Distributed RAM has an explicit head register, BRAM has a local read port
    set data_regs [get_cells -quiet -hier -filter "NAME =~ ${fifo}/fifoMem_reg*"]
    set head_regs [get_cells -quiet -hier -filter "NAME =~ ${fifo}/dDoutReg_reg*"]
    if {[llength $data_regs] && [llength $head_regs]} {
        set write_pointer [get_cells -hier -filter "NAME =~ ${fifo}/sGEnqPtr_reg*"]
        set source_clock [get_clocks -of_objects [get_pins -of_objects $write_pointer -filter {REF_PIN_NAME == C}]]
        if {[llength $source_clock] != 1} { error "Missing source clock for $fifo" }
        set_max_delay -datapath_only 5.0 -from $source_clock -to $head_regs
    }
    # Both sides are flushed by a common reset epoch
    set resets [get_pins -quiet -hier -filter "NAME =~ ${fifo}/* && (REF_PIN_NAME == CLR || REF_PIN_NAME == PRE)"]
    if {[llength $resets]} { set_false_path -to $resets }
}

set status_syncs [get_cells -quiet -hier -filter {REF_NAME =~ SyncBit* && (NAME =~ *i_calibrated || NAME =~ *i_encoder_cdc_i_busy || NAME =~ *i_encoder_cdc_i_irq)}]
foreach sync $status_syncs {
    set regs [get_cells -quiet -hier -filter "NAME =~ ${sync}/dSyncReg*"]
    set_property ASYNC_REG TRUE $regs
    set_property SHREG_EXTRACT NO $regs
    set_max_delay -datapath_only 5.0 \
        -from [get_cells -hier -filter "NAME == ${sync}/sSyncReg_reg"] \
        -to [get_cells -hier -filter "NAME == ${sync}/dSyncReg1_reg"]
    set resets [get_pins -quiet -hier -filter "NAME =~ ${sync}/* && (REF_PIN_NAME == CLR || REF_PIN_NAME == PRE)"]
    if {[llength $resets]} { set_false_path -to $resets }
}
if {[llength $app] && [llength $status_syncs] != 3} { error "Expected three status synchronizers, found: $status_syncs" }
