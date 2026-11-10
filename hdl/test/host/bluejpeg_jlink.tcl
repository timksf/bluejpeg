# OpenOCD session for the BlueJPEG PA200T test design over a J-Link on the JTAG header pins.
#   openocd -f bluejpeg_jlink.tcl
# Start test/host/capture_uart.py before running this so the JPEG is captured from the UART.

adapter driver jlink
transport select jtag
adapter speed 1000
reset_config none

source [file join [file dirname [info script]] helpers.tcl]
source [file join [file dirname [info script]] bluejpeg.tcl]

# custom TAP via pins, same as the pa200t design
jtag newtap pa200t tap -irlen 3 -expected-id 0x0000402f

init
scan_chain

runtest 5

bluejpeg_check_ids pa200t.tap
bluejpeg_set_baud pa200t.tap 115200
bluejpeg_encode pa200t.tap
bluejpeg_report pa200t.tap

shutdown
