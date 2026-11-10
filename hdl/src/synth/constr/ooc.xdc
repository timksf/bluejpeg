# create_clock -period 5.0 -name system_clock [get_ports CLK]  

#
create_clock -period 5.0 -name system_clock [get_ports aclk]  
create_clock -period 40.0 -name dct_clock [get_ports CLK_dct_clock]  