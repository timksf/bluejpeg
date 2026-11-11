# OpenOCD session for the separate UDP bitstream, no programming is performed
# Leave the server running for load_frame.py and Tcl or telnet commands
adapter driver jlink
transport select jtag
adapter speed 1000
reset_config none

source [file join [file dirname [info script]] helpers.tcl]
source [file join [file dirname [info script]] bluejpeg_udp.tcl]
jtag newtap pa200t tap -irlen 3 -expected-id 0x0000402f
init
scan_chain
runtest 5

foreach {name value} {
    udp_mac 025041323030
    udp_local_ip 192.168.178.250
    udp_netmask 255.255.255.0
    udp_gateway 192.168.178.1
    udp_peer_ip 192.168.178.23
    udp_width 1920
    udp_height 1080
} {
    if {![info exists $name]} { set $name $value }
}
bluejpeg_udp_check_ids pa200t.tap
bluejpeg_udp_wait pa200t.tap 2 2
bluej_mdio_init pa200t.tap 83 0x3
bluej_phy_wait_link pa200t.tap 1 10000 0x3
bluej_eth_setup pa200t.tap $udp_mac $udp_local_ip $udp_netmask $udp_gateway $udp_peer_ip 5000 5001 0x3
bluej_eth_status pa200t.tap 0x3
bluejpeg_udp_setup pa200t.tap $udp_width $udp_height
echo "UDP setup complete, Tcl RPC is available on port 6666"
