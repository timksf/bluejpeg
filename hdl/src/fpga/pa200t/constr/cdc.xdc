# Clock domain crossings. Read after synth_design because the PLL output clocks are
# derived from the netlist.
#
# clk_sys (PLL CLKOUT0, 50 MHz) and clk_uart (CLKOUT1, 125 MHz) only meet in the
# dual-clock FIFO (SyncFIFO) and the UART divider register (SyncRegister). The JTAG TAP
# talks to clk_sys through the BlueJ synchronizers. The reset button and the UART receive
# pin are asynchronous inputs. All groups are therefore unrelated for timing.

set pll [get_cells -hier -filter {REF_NAME == PLLE2_ADV}]
set clk_sys  [get_clocks -of_objects [get_pins -of_objects $pll -filter {REF_PIN_NAME == CLKOUT0}]]
set clk_uart [get_clocks -of_objects [get_pins -of_objects $pll -filter {REF_PIN_NAME == CLKOUT1}]]

set_clock_groups -asynchronous \
    -group [get_clocks clk_200] \
    -group $clk_sys \
    -group $clk_uart \
    -group [get_clocks jtag_tck]

set_false_path -from [get_ports {RST_N uart_rx}]
set_false_path -to [get_ports {LED[*] uart_tx}]
