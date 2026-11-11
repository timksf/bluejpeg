# The two GTX clocks retain their phase relation
# RGMII RX crossings retain the bounds from the upstream FIFO constraint scripts
set pll [get_cells -hier -filter {REF_NAME == PLLE2_ADV && NAME =~ *i_pll_i_pll_i_pll}]
set gtx [get_clocks -of_objects [get_pins -of_objects $pll -filter {REF_PIN_NAME == CLKOUT0 || REF_PIN_NAME == CLKOUT1}]]
set sys [get_clocks -of_objects [get_pins -hier -filter {REF_PIN_NAME == ui_clk || (REF_PIN_NAME == CLKOUT2 && NAME =~ *i_pll_i_pll_i_pll*)}]]
set_clock_groups -asynchronous \
    -group [get_clocks clk_200] \
    -group $gtx \
    -group $sys \
    -group [get_clocks jtag_tck]
