package JpegTestRegs;

import BlueCSRCore :: *;

import BlueJPEGRegs :: *;

//test pattern held in the BRAM ROM, 192x192 YCbCr pixels packed as {Y, Cb, Cr}
typedef 192                                PatternWidth;
typedef 192                                PatternHeight;
typedef TMul#(PatternWidth, PatternHeight) PatternPixels;

String pattern_file = "pattern_192x192.mem";

//pixels per frame after reset, the whole pattern
UInt#(32) default_npix = fromInteger(valueOf(PatternPixels));

//UART bit time in UART clocks, 125 MHz / 115200 baud
Bit#(16) default_uart_div = 1085;

interface JpegTestRegs_ifc;
    interface ReadOnly#(Bool)      enable;
    interface ReadOnly#(UInt#(32)) npix;
    interface ReadOnly#(Bit#(16))  uart_div;

    method Action status(Bool streaming, Bool in_done, Bool out_done);
    method Action perf_rst;

    interface PerfCounter_ifc in_cycles;
    interface PerfCounter_ifc in_stalls;
    interface PerfCounter_ifc out_bytes;
    interface PerfCounter_ifc out_cycles;
    interface PerfCounter_ifc out_stalls;
    interface PerfCounter_ifc total_cycles;
endinterface

/*
 * Register map of the JPEG test system. While EN is set, every frame the encoder starts
 * streams NPIX pixels from the pattern ROM into it, and all counters restart in that cycle.
 * The input and output windows run from the first to the last beat accepted at the
 * encoder's stream ports.
 */
module [BlueCSRCtx_t#(32, 32)] jpeg_test_regs(JpegTestRegs_ifc);
    PulseWire pw_perf_rst <- mkPulseWire;

    csr_regmap_def("JpegTest", "BlueJPEG test system: pattern source, output capture and UART link");

    csr_reg_def('h00, "MIV", "Module ID and version");
                            csr_reg_rc(  'h00, Bit#(12)'('h002), 0,               "MID",    "Module ID",      "Unique ID for this module.");
                            csr_reg_rc(  'h00, Bit#(3)'('h0),    16,              "VRS",    "Module Version", "Module version.");

    csr_reg_def('h04, "CTRL", "Control");
    let rg_enable        <- csr_reg_rw(  'h04, True,             0,               "EN",     "Stream Enable",  "Stream the pattern into every frame the encoder starts.");

    csr_reg_def('h08, "STS", "Status");
    let rg_streaming     <- csr_reg_ro(  'h08, False,            0,               "BUSY",   "Streaming",      "The pattern source is streaming pixels.");
    let rg_in_done       <- csr_reg_ro(  'h08, False,            1,               "INDN",   "Input Done",     "The encoder accepted the last pattern pixel.");
    let rg_out_done      <- csr_reg_ro(  'h08, False,            2,               "OUTDN",  "Output Done",    "The last JPEG byte left the encoder.");

    csr_reg_def('h0c, "NPIX", "Pixels per frame");
    let rg_npix          <- csr_reg_rw(  'h0c, default_npix,     0,               "NPIX",   "Pixel Count",    "Pixels streamed per start, the ROM address wraps after the pattern.");

    csr_reg_def('h10, "UDIV", "UART bit time");
    let rg_uart_div      <- csr_reg_rw(  'h10, default_uart_div, 0,               "UDIV",   "UART Divider",   "UART clock cycles per bit. The reset value gives 115200 baud at 125 MHz.");

    csr_reg_def('h20, "INCYC", "Input window");
    let i_in_cycles      <- perf_counter('h20,                       pw_perf_rst, "INCYC",  "Input Cycles",   "Cycles from the first to the last pixel accepted by the encoder, inclusive.");

    csr_reg_def('h24, "INSTL", "Input stalls");
    let i_in_stalls      <- perf_counter('h24,                       pw_perf_rst, "INSTL",  "Input Stalls",   "Cycles in the input window with a pixel offered but not accepted.");

    csr_reg_def('h28, "OUTB", "Output bytes");
    let i_out_bytes      <- perf_counter('h28,                       pw_perf_rst, "OUTB",   "Output Bytes",   "JPEG bytes accepted from the encoder.");

    csr_reg_def('h2c, "OUTCYC", "Output window");
    let i_out_cycles     <- perf_counter('h2c,                       pw_perf_rst, "OUTCYC", "Output Cycles",  "Cycles from the first to the last JPEG byte leaving the encoder, inclusive.");

    csr_reg_def('h30, "OUTSTL", "Output stalls");
    let i_out_stalls     <- perf_counter('h30,                       pw_perf_rst, "OUTSTL", "Output Stalls",  "Cycles in the output window with a byte offered but the output buffer full.");

    csr_reg_def('h34, "TOTAL", "End-to-end cycles");
    let i_total_cycles   <- perf_counter('h34,                       pw_perf_rst, "TOTAL",  "Total Cycles",   "Cycles from the encoder's frame start until the last JPEG byte left the encoder.");

    method perf_rst = pw_perf_rst.send;

    method Action status(Bool streaming, Bool in_done, Bool out_done);
        rg_streaming <= streaming;
        rg_in_done   <= in_done;
        rg_out_done  <= out_done;
    endmethod

    interface enable       = regToReadOnly(rg_enable);
    interface npix         = regToReadOnly(rg_npix);
    interface uart_div     = regToReadOnly(rg_uart_div);
    interface in_cycles    = i_in_cycles;
    interface in_stalls    = i_in_stalls;
    interface out_bytes    = i_out_bytes;
    interface out_cycles   = i_out_cycles;
    interface out_stalls   = i_out_stalls;
    interface total_cycles = i_total_cycles;
endmodule

endpackage
