# Volatile FPGA configuration over the on-board FT232H
tcl_port disabled
telnet_port disabled
gdb_port disabled
adapter driver ftdi
ftdi vid_pid 0x0403 0x6014
ftdi layout_init 0x0008 0x000b
adapter speed 10000
transport select jtag
jtag newtap xc7 tap -irlen 6 -expected-id 0x13636093
pld device virtex2 xc7.tap 1
init
