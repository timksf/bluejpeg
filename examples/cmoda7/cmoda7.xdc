

create_clock -period 10.0 -name system_clock [get_ports aclk]
create_clock -period 10.0 -name system_clock [get_ports dct_clk]  