package BlueJPEGDecRegs;

import BlueCSRCore :: *;

import Types :: *;
import DecoderTypes :: *;

interface BlueJPEGDecCfg_ifc;
    method Action status(Bool busy, FrameInfo_t info, DecError_t err);
    method Action events(Bool frame_start, Bool frame_done, Bool error);

    method Action byte_in();
    method Action pixel_out();
endinterface

module [BlueCSRCtx_t#(32, 32)] blue_jpeg_dec_csrs(BlueJPEGDecCfg_ifc);

    PulseWire              pw_frame_start <- mkPulseWire;
    PulseWire              pw_frame_done  <- mkPulseWire;
    PulseWire              pw_error       <- mkPulseWire;
    PulseWire              pw_busy        <- mkPulseWire;
    PulseWire              pw_byte        <- mkPulseWire;
    PulseWire              pw_pixel       <- mkPulseWire;
    Wire#(Maybe#(Bit#(1))) w_done_update  <- mkDWire(tagged Invalid);

    Reg#(Bool)         rg_busy;
    ReadOnly#(Bit#(1)) rg_done;
    Reg#(Bit#(16))     rg_imw;
    Reg#(Bit#(16))     rg_imh;
    Reg#(Bit#(2))      rg_ncomp;
    Reg#(Bit#(3))      rg_err;

    csr_regmap_def("BlueJPEGDec", "Register File for the BlueJPEG decoder.");

    csr_reg_def('h00, "MIV", "Module ID and Version Register.");
    csr_reg_rc('h00, Bit#(12)'('h002), 0, "MID", "Module ID",      "Unique ID for this module.");
    csr_reg_rc('h00, Bit#(3)'('h0),   16, "VRS", "Module Version", "Module version.");


    csr_reg_def('h08, "STS", "Status Register.");
    rg_busy <- csr_reg_ro('h08, False, 0, "BUSY", "Busy", "High from an accepted scan header until the last pixel of that frame has left.");
    rg_done <- csr_reg_ho(
        'h08, 'b0, 4, w_done_update,
        "DONE", "Frame Done", "Set when the last pixel of a frame leaves and cleared when the next scan header is accepted."
    );


    csr_reg_def('h0C, "IMSZ", "Image Size of the last frame header.");
    rg_imw <- csr_reg_ro('h0C, 0,  0, "IMW", "Image Width",  "");
    rg_imh <- csr_reg_ro('h0C, 0, 16, "IMH", "Image Height", "");


    csr_reg_def('h10, "FMT", "Frame Format of the last frame header.");
    rg_ncomp <- csr_reg_ro('h10, 0, 0, "NCMP", "Components", "1 for grayscale, 3 for YCbCr.");


    csr_reg_def('h14, "ERR", "Error Status.");
    rg_err <- csr_reg_ro('h14, 0, 0, "CODE", "Error Code",
        "0 none, 1 stream does not start with SOI, 2 unsupported feature, 3 invalid Huffman code, 4 coefficient index overflow. The decoder stops on an error until reset.");


    //pending bits latch regardless of enable and double as sticky status
    //enabled pending bits drive the irq line
    csr_reg_def('h18, "IRQP", "Interrupt Pending (W1C).");
    csr_reg_def('h1C, "IRQE", "Interrupt Enable.");
    csr_irq('h18, 'h1C, 0, 0, pw_frame_done, "DONE", "Frame Done", "The last pixel of a frame has left the decoder.");
    csr_irq('h18, 'h1C, 1, 0, pw_error,      "ERR",  "Error",      "The decoder stopped on an error, see ERR.");


    //free-running read-only event counters, software works with differences
    csr_reg_def('h30, "PERF0", "Performance Counter Cycles.");
    let _cyc <- csr_reg_counter_ro('h30, Bit#(32)'(0), 0, pw_busy, "CYC", "Cycle Counter", "Cycles in which at least one frame was in flight.");

    csr_reg_def('h34, "PERF1", "Performance Counter Bytes.");
    let _byte <- csr_reg_counter_ro('h34, Bit#(32)'(0), 0, pw_byte, "BYTEI", "In Byte Counter", "JPEG bytes accepted.");

    csr_reg_def('h38, "PERF2", "Performance Counter Pixels.");
    let _pix <- csr_reg_counter_ro('h38, Bit#(32)'(0), 0, pw_pixel, "PIX", "Pixel Counter", "Pixels produced.");

    csr_reg_def('h3C, "PERF3", "Performance Counter Idle Cycles.");
    let _idle <- csr_reg_counter_ro('h3C, Bit#(32)'(0), 0, pw_busy && !pw_pixel, "IDLE", "Idle Cycles", "Cycles with a frame in flight in which no pixel left the decoder.");

    csr_reg_def('h40, "PERF4", "Performance Counter Frames.");
    let _frm <- csr_reg_counter_ro('h40, Bit#(32)'(0), 0, pw_frame_done, "FRM", "Frame Counter", "Frames decoded.");

    method Action status(Bool busy, FrameInfo_t info, DecError_t err);
        rg_busy  <= busy;
        if(busy) pw_busy.send;
        rg_imw   <= pack(info.width);
        rg_imh   <= pack(info.height);
        rg_ncomp <= pack(info.ncomp);
        rg_err   <= zeroExtend(pack(err));
    endmethod

    //a frame that finishes in the same cycle another one starts leaves DONE set
    method Action events(Bool frame_start, Bool frame_done, Bool error);
        if(frame_start) pw_frame_start.send;
        if(frame_done)  pw_frame_done.send;
        if(error)       pw_error.send;
        if(frame_done)       w_done_update <= tagged Valid 1;
        else if(frame_start) w_done_update <= tagged Valid 0;
    endmethod

    method byte_in   = pw_byte.send;
    method pixel_out = pw_pixel.send;

endmodule

endpackage
