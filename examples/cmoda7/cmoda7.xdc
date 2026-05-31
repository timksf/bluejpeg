set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports { clk_12 }]
create_clock -add -name clk_12 -period 83.333 -waveform {0 41.666} [get_ports { clk_12 }]

# Vivado infers these from the instantiated MMCM/BUFR, but keep the derived
# clocks explicit so their intended rates and names are visible in the XDC.
create_generated_clock -name clk_100 \
    -source [get_pins {i_MMCME2_BASE/CLKIN1}] \
    -multiply_by 50 -divide_by 6 \
    [get_pins {i_MMCME2_BASE/CLKOUT0}]

create_generated_clock -name clk_dct \
    -source [get_pins {i_clkdiv_dct_BUFR/I}] \
    -divide_by 8 \
    [get_pins {i_clkdiv_dct_BUFR/O}]

# The DCT domain crosses to/from the 100 MHz domain through Bluespec Gearbox
# CDC logic. Keep each domain constrained internally, but do not time direct
# register-to-register paths between the two clock domains.
set_clock_groups -asynchronous \
    -group [get_clocks clk_100] \
    -group [get_clocks clk_dct]

set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports { btn }]

set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]

set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { uart_rxd }]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { uart_txd }]
