# BlueJPEG PA200T test design: register helpers for OpenOCD, used by bluejpeg_jlink.tcl.
# Needs helpers.tcl. Bus map (see src/fpga/pa200t/PA200T_JPEG.bsv):
#   0x0000  TEST  test system (pattern source, output capture, UART), src/system/JpegTestRegs.bsv
#   0x2000  JPEG  encoder, src/encoder/BlueJPEGRegs.bsv

set bluejpeg_instr     0x3
set bluejpeg_test      0x0000
set bluejpeg_jpeg      0x2000
set bluejpeg_uart_hz   125000000
set bluejpeg_sys_hz    50000000

proc bluejpeg_rd {tap addr} {
    global bluejpeg_instr
    return [bluej_bus_access $tap $bluejpeg_instr 0 $addr 0]
}

proc bluejpeg_wr {tap addr data} {
    global bluejpeg_instr
    bluej_bus_access $tap $bluejpeg_instr 1 $addr $data
}

proc bluejpeg_test_reg {name} {
    global bluejpeg_test
    set offsets {MIV 0x00 CTRL 0x04 STS 0x08 NPIX 0x0c UDIV 0x10 INCYC 0x20 INSTL 0x24 OUTB 0x28 OUTCYC 0x2c OUTSTL 0x30 TOTAL 0x34}
    return [expr {$bluejpeg_test + [dict get $offsets $name]}]
}

proc bluejpeg_jpeg_reg {name} {
    global bluejpeg_jpeg
    set offsets {MIV 0x00 CTRL 0x04 STS 0x08 IMSZ 0x0c CGEN 0x14 IRQP 0x18 IRQE 0x1c
                 PERF0 0x30 PERF1 0x34 PERF2 0x38 PERF3 0x3c PERF4 0x40 PERF5 0x44 PERF6 0x48}
    return [expr {$bluejpeg_jpeg + [dict get $offsets $name]}]
}

# Module IDs: encoder 0x001, test system 0x002.
proc bluejpeg_check_ids {tap} {
    set jpeg [expr {[bluejpeg_rd $tap [bluejpeg_jpeg_reg MIV]] & 0xfff}]
    set test [expr {[bluejpeg_rd $tap [bluejpeg_test_reg MIV]] & 0xfff}]
    echo [format "module ids: JPEG 0x%03x, TEST 0x%03x" $jpeg $test]
    if {$jpeg != 0x001 || $test != 0x002} {
        error "unexpected module ids, check the bitstream and the JTAG connection"
    }
}

# UART bit time in 125 MHz clocks. Example: bluejpeg_set_baud pa200t.tap 921600
proc bluejpeg_set_baud {tap baud} {
    global bluejpeg_uart_hz
    set div [expr {($bluejpeg_uart_hz + $baud / 2) / $baud}]
    if {$div < 1 || $div > 0xffff} {
        error "baud rate outside the 16-bit divider range"
    }
    bluejpeg_wr $tap [bluejpeg_test_reg UDIV] $div
    echo [format "UART: %d baud requested, divider %d, actual %.0f baud" $baud $div [expr {double($bluejpeg_uart_hz) / $div}]]
    return $div
}

# STS.RDY rises once the default tables and Huffman codes are ready after reset.
proc bluejpeg_wait_ready {tap} {
    for {set poll 0} {$poll < 100} {incr poll} {
        if {[bluejpeg_rd $tap [bluejpeg_jpeg_reg STS]] & 1} {
            return
        }
    }
    error "encoder tables not ready"
}

# Encode one frame. The test system streams the pattern ROM into every frame the encoder
# starts, so this only configures and starts the encoder. LED[0] lights with the interrupt.
proc bluejpeg_encode {tap {width 192} {height 192}} {
    bluejpeg_wait_ready $tap
    bluejpeg_wr $tap [bluejpeg_test_reg NPIX] [expr {$width * $height}]
    bluejpeg_wr $tap [bluejpeg_jpeg_reg IRQP] 0x3
    bluejpeg_wr $tap [bluejpeg_jpeg_reg IRQE] 0x1
    bluejpeg_wr $tap [bluejpeg_jpeg_reg IMSZ] [expr {($height << 16) | $width}]
    bluejpeg_wr $tap [bluejpeg_jpeg_reg CTRL] 0x1

    for {set poll 0} {$poll < 100} {incr poll} {
        set irqp [bluejpeg_rd $tap [bluejpeg_jpeg_reg IRQP]]
        if {$irqp & 0x2} {
            error "encoder rejected the image size"
        }
        if {$irqp & 0x1} {
            echo "frame done"
            return
        }
    }
    error "frame did not finish"
}

# Clear the interrupt, LED[0] goes dark.
proc bluejpeg_ack {tap} {
    bluejpeg_wr $tap [bluejpeg_jpeg_reg IRQP] 0x1
}

# Print all counters of the last frame with derived figures, in 50 MHz system clock cycles.
proc bluejpeg_report {tap} {
    global bluejpeg_sys_hz
    foreach name {PERF0 PERF1 PERF2 PERF3 PERF4 PERF5 PERF6} {
        set v($name) [bluejpeg_rd $tap [bluejpeg_jpeg_reg $name]]
    }
    foreach name {INCYC INSTL OUTB OUTCYC OUTSTL TOTAL} {
        set v($name) [bluejpeg_rd $tap [bluejpeg_test_reg $name]]
    }

    echo "encoder:"
    echo [format "  running cycles            %10d" $v(PERF0)]
    echo [format "  pixels accepted           %10d" $v(PERF1)]
    echo [format "  JPEG bytes                %10d" $v(PERF2)]
    echo [format "  idle (no pixel) cycles    %10d" $v(PERF3)]
    echo [format "  flush cycles              %10d" $v(PERF4)]
    echo [format "  frame cycles              %10d" $v(PERF5)]
    echo [format "  boot cycles               %10d" $v(PERF6)]
    echo "test system:"
    echo [format "  input window cycles       %10d" $v(INCYC)]
    echo [format "  input stall cycles        %10d" $v(INSTL)]
    echo [format "  output bytes              %10d" $v(OUTB)]
    echo [format "  output window cycles      %10d" $v(OUTCYC)]
    echo [format "  output stall cycles       %10d" $v(OUTSTL)]
    echo [format "  frame start to last byte  %10d" $v(TOTAL)]

    if {$v(PERF0) > 0 && $v(PERF1) > 0} {
        echo "derived:"
        echo [format "  pixels per running cycle  %10.4f" [expr {double($v(PERF1)) / $v(PERF0)}]]
        echo [format "  cycles per pixel          %10.3f" [expr {double($v(PERF0)) / $v(PERF1)}]]
        echo [format "  configure cycles          %10d" [expr {$v(PERF5) - $v(PERF0) - $v(PERF4)}]]
        echo [format "  frame time                %10.3f ms" [expr {1000.0 * $v(PERF5) / $bluejpeg_sys_hz}]]
        echo [format "  throughput                %10.2f Mpixel/s" [expr {double($v(PERF1)) * $bluejpeg_sys_hz / $v(PERF5) / 1e6}]]
    }
}
