# Register helpers for the UDP system, sourced after helpers.tcl
if {![info exists bluejpeg_udp_hz]} { set bluejpeg_udp_hz 81250000 }

proc bluejpeg_udp_reg {name} {
    set offsets {MIV 0x00 CTRL 0x04 STS 0x08 NPIX 0x0c BASE 0x10 MEMADDR 0x14 MEMDATA 0x18
                 CHK1 0x20 CHK2 0x24 LDPKT 0x28 LDPIX 0x2c LDDROP 0x30 FRAMES 0x40
                 INCYC 0x44 INSTL 0x48 OUTB 0x4c OUTCYC 0x50 OUTSTL 0x54 TOTAL 0x58 PKTS 0x5c PERIOD 0x60}
    return [dict get $offsets $name]
}

proc bluejpeg_udp_rd {tap name} {
    return [bluej_bus_access $tap 0x3 0 [bluejpeg_udp_reg $name] 0]
}

proc bluejpeg_udp_wr {tap name value} {
    bluej_bus_access $tap 0x3 1 [bluejpeg_udp_reg $name] $value
}

proc bluejpeg_udp_wait {tap mask value {timeout_ms 10000}} {
    set deadline [expr {[clock milliseconds] + $timeout_ms}]
    while {[clock milliseconds] < $deadline} {
        set status [bluejpeg_udp_rd $tap STS]
        if {$status & 0x20} { error "frame store AXI error" }
        if {($status & $mask) == $value} { return $status }
        sleep 10
    }
    error "UDP system status timeout"
}

proc bluejpeg_udp_check_ids {tap} {
    set sys [expr {[bluejpeg_udp_rd $tap MIV] & 0xfff}]
    set jpeg [expr {[bluej_bus_access $tap 0x3 0 0x4000 0] & 0xfff}]
    if {$sys != 3 || $jpeg != 1} { error "unexpected UDP system or JPEG module ID" }
    echo "UDP system and JPEG module IDs verified"
}

proc bluejpeg_udp_setup {tap {width 1920} {height 1080} {base 0}} {
    if {$width <= 0 || $width > 1920 || $height <= 0 || $height > 65535 || ($width & 7) || ($height & 7)} {
        error "dimensions must be positive multiples of eight within encoder limits"
    }
    if {$base < 0 || $base + $width * $height > 0x10000000} { error "frame exceeds DDR address range" }
    bluejpeg_udp_check_ids $tap
    bluejpeg_udp_wait $tap 2 2
    bluejpeg_udp_wr $tap CTRL 0
    bluejpeg_udp_wait $tap 0x19 0
    set deadline [expr {[clock milliseconds] + 10000}]
    while {![expr {[bluej_bus_access $tap 0x3 0 0x4008 0] & 1}]} {
        if {[clock milliseconds] >= $deadline} { error "encoder tables not ready" }
        sleep 10
    }
    bluejpeg_udp_wr $tap BASE $base
    bluejpeg_udp_wr $tap NPIX [expr {$width * $height}]
    bluej_bus_access $tap 0x3 1 0x400c [expr {($height << 16) | $width}]
    bluej_bus_access $tap 0x3 1 0x4018 3
    bluej_bus_access $tap 0x3 1 0x401c 1
}

proc bluejpeg_udp_start {tap} {
    bluejpeg_udp_wait $tap 0x19 0
    bluejpeg_udp_wr $tap CTRL [expr {([bluejpeg_udp_rd $tap CTRL] & 4) | 1}]
}

proc bluejpeg_udp_repeat {tap enable} {
    set ctrl [expr {[bluejpeg_udp_rd $tap CTRL] & 4}]
    bluejpeg_udp_wr $tap CTRL [expr {$ctrl | ($enable ? 2 : 0)}]
}

proc bluejpeg_udp_verify {tap} {
    bluejpeg_udp_wr $tap CTRL 0
    bluejpeg_udp_wait $tap 0x19 0
    bluejpeg_udp_wr $tap CTRL 8
    sleep 10
    bluejpeg_udp_wait $tap 4 4
    set sum1 [bluejpeg_udp_rd $tap CHK1]
    set sum2 [bluejpeg_udp_rd $tap CHK2]
    echo [format "CHK1 %08x CHK2 %08x" $sum1 $sum2]
    return [list $sum1 $sum2]
}

proc bluejpeg_udp_peek {tap address} {
    bluejpeg_udp_wr $tap MEMADDR $address
    return [bluejpeg_udp_rd $tap MEMDATA]
}

proc bluejpeg_udp_poke {tap address value} {
    bluejpeg_udp_wr $tap MEMADDR $address
    bluejpeg_udp_wr $tap MEMDATA $value
}

proc bluejpeg_udp_report {tap} {
    global bluejpeg_udp_hz
    foreach name {STS NPIX BASE CHK1 CHK2 LDPKT LDPIX LDDROP FRAMES INCYC INSTL OUTB OUTCYC OUTSTL TOTAL PKTS PERIOD} {
        set values($name) [bluejpeg_udp_rd $tap $name]
        echo [format "%s %u" $name $values($name)]
    }
    if {$values(INCYC)} {
        echo [format "input %.4f pixels/cycle" [expr {double($values(NPIX)) / $values(INCYC)}]]
    }
    echo [format "encoding time %.3f ms" [expr {1000.0 * $values(TOTAL) / $bluejpeg_udp_hz}]]
    if {$values(PERIOD)} {
        echo [format "frame period %.3f ms, %.3f fps" [expr {1000.0 * $values(PERIOD) / $bluejpeg_udp_hz}] [expr {double($bluejpeg_udp_hz) / $values(PERIOD)}]]
    }
    for {set index 0} {$index < 7} {incr index} {
        echo [format "PERF%d %u" $index [bluej_bus_access $tap 0x3 0 [expr {0x4030 + 4 * $index}] 0]]
    }
}
