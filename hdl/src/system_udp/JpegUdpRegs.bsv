package JpegUdpRegs;

import ClientServer :: *;
import FIFOF :: *;
import GetPut :: *;
import BlueCSRCore :: *;

import BlueJPEGRegs :: *;
import EncoderUtil :: *;

interface JpegUdpRegs_ifc;
    interface ReadOnly#(Bool)              start;
    interface ReadOnly#(Bool)              repeat_frames;
    interface ReadOnly#(Bool)              load_enable;
    interface ReadOnly#(Bool)              verify;
    interface ReadOnly#(UInt#(32))         npix;
    interface ReadOnly#(UInt#(32))         base;
    interface ReadOnly#(UInt#(32))         memaddr;
    interface Get#(BlueCSR_Req_t#(32, 32)) memory_request;
    interface Put#(BlueCSR_Rsp_t#(32))     memory_response;
    method Bool                            memory_pending;
    method Action                          clear_start;
    method Action                          clear_verify;
    method Action                          status(Bit#(6) value, Bit#(32) checksum1, Bit#(32) checksum2, Bit#(32) packets, Bit#(32) pixels, Bit#(32) dropped);
    method Action                          perf_rst;
    method Action                          frame_done;
    method Action                          period(Bit#(32) value);
    interface PerfCounter_ifc              in_cycles;
    interface PerfCounter_ifc              in_stalls;
    interface PerfCounter_ifc              out_bytes;
    interface PerfCounter_ifc              out_cycles;
    interface PerfCounter_ifc              out_stalls;
    interface PerfCounter_ifc              total_cycles;
    interface PerfCounter_ifc              packets;
endinterface

module [BlueCSRCtx_t#(32, 32)] jpeg_udp_regs(JpegUdpRegs_ifc);
    PulseWire                      pw_start_clear    <- mkPulseWire;
    PulseWire                      pw_verify_clear   <- mkPulseWire;
    PulseWire                      pw_perf_rst       <- mkPulseWire;
    PulseWire                      pw_frame_done     <- mkPulseWire;
    Wire#(Maybe#(Bit#(32)))        w_period          <- mkDWire(tagged Invalid);
    FIFOF#(BlueCSR_Req_t#(32, 32)) f_memory_request  <- mkFIFOF;
    FIFOF#(BlueCSR_Rsp_t#(32))     f_memory_response <- mkFIFOF;

    //START and VERIFY are cleared by hardware when the request is taken
    Maybe#(Bool) start_clear  = pw_start_clear ? tagged Valid False : tagged Invalid;
    Maybe#(Bool) verify_clear = pw_verify_clear ? tagged Valid False : tagged Invalid;

    Server#(BlueCSR_Req_t#(32, 32), BlueCSR_Rsp_t#(32)) memory_server = interface Server;
        interface request  = toPut(f_memory_request);
        interface response = toGet(f_memory_response);
    endinterface;

    csr_regmap_def("JpegUdp", "DDR3 frame store and JPEG UDP system");

    csr_reg_def('h00, "MIV", "Module ID and version");
                            csr_reg_rc(        'h00, Bit#(12)'('h003),    0,                 "MID",     "Module ID",      "Unique module ID.");
                            csr_reg_rc(        'h00, Bit#(3)'(0),         16,                "VRS",     "Version",        "Module version.");

    csr_reg_def('h04, "CTRL", "Frame and loader control");
    let rg_start         <- csr_reg_hu(        'h04, False,               0,  start_clear,   "START",   "Start",          "Request one frame.");
    let rg_repeat        <- csr_reg_rw(        'h04, False,               1,                 "REPEAT",  "Repeat",         "Run frames continuously while set.");
    let rg_load          <- csr_reg_rw(        'h04, False,               2,                 "LOADEN",  "Load enable",    "Accept pixel datagrams while idle.");
    let rg_verify        <- csr_reg_hu(        'h04, False,               3,  verify_clear,  "VERIFY",  "Verify",         "Compute frame checksums.");

    csr_reg_def('h08, "STS", "System status");
    let rg_status        <- csr_reg_ro(        'h08, Bit#(6)'(0),         0,                 "STS",     "Status",         "Busy, calibration, verify done, reader, loader and memory error bits.");

    csr_reg_def('h0c, "NPIX", "Pixels per frame");
    let rg_npix          <- csr_reg_rw(        'h0c, UInt#(32)'(2073600), 0,                 "NPIX",    "Pixels",         "Raster pixels per frame.");

    csr_reg_def('h10, "BASE", "Frame word address");
    let rg_base          <- csr_reg_rw(        'h10, UInt#(32)'(0),       0,                 "BASE",    "Base",           "Frame base in 32-bit words.");

    csr_reg_def('h14, "MEMADDR", "Peek and poke word address");
    let rg_memaddr       <- csr_reg_rw(        'h14, UInt#(32)'(0),       0,                 "MEMADDR", "Memory address", "Absolute word address for MEMDATA.");

    csr_region_server('h18, 4, unpack(rg_status[1]), CSR_SLVERR, memory_server, "MEMDATA", "Read peeks and write pokes the selected word with an AXI completion response");

    csr_reg_def('h20, "CHK1", "Verify sum of words");
    let rg_checksum1     <- csr_reg_ro(        'h20, Bit#(32)'(0),        0,                 "CHK1",    "Checksum 1",     "Wrapping sum of all frame words.");

    csr_reg_def('h24, "CHK2", "Verify sum of prefix sums");
    let rg_checksum2     <- csr_reg_ro(        'h24, Bit#(32)'(0),        0,                 "CHK2",    "Checksum 2",     "Wrapping sum of running word sums.");

    csr_reg_def('h28, "LDPKT", "Accepted loader packets");
    let rg_ldpkt         <- csr_reg_ro(        'h28, Bit#(32)'(0),        0,                 "LDPKT",   "Load packets",   "Validated datagrams since reset.");

    csr_reg_def('h2c, "LDPIX", "Accepted loader pixels");
    let rg_ldpix         <- csr_reg_ro(        'h2c, Bit#(32)'(0),        0,                 "LDPIX",   "Load pixels",    "Pixels committed to the memory writer since reset.");

    csr_reg_def('h30, "LDDROP", "Dropped loader packets");
    let rg_lddrop        <- csr_reg_ro(        'h30, Bit#(32)'(0),        0,                 "LDDROP",  "Load drops",     "Rejected datagrams since reset.");

    csr_reg_def('h40, "FRAMES", "Completed frames since reset");
    let rg_frames        <- csr_reg_counter_ro('h40, Bit#(32)'(0),        0,  pw_frame_done, "FRAMES",  "Frames",         "Frames whose final packet reached the UDP endpoint.");

    csr_reg_def('h44, "INCYC", "Input window cycles");
    let i_in_cycles      <- perf_counter(      'h44,                          pw_perf_rst,   "INCYC",   "Input cycles",   "First to last accepted pixel, inclusive.");

    csr_reg_def('h48, "INSTL", "Input stalls");
    let i_in_stalls      <- perf_counter(      'h48,                          pw_perf_rst,   "INSTL",   "Input stalls",   "Cycles in the input window with a pixel offered but not accepted.");

    csr_reg_def('h4c, "OUTB", "JPEG bytes");
    let i_out_bytes      <- perf_counter(      'h4c,                          pw_perf_rst,   "OUTB",    "JPEG bytes",     "Accepted JPEG bytes.");

    csr_reg_def('h50, "OUTCYC", "Output window cycles");
    let i_out_cycles     <- perf_counter(      'h50,                          pw_perf_rst,   "OUTCYC",  "Output cycles",  "First to last accepted JPEG byte, inclusive.");

    csr_reg_def('h54, "OUTSTL", "Output stalls");
    let i_out_stalls     <- perf_counter(      'h54,                          pw_perf_rst,   "OUTSTL",  "Output stalls",  "Cycles with a JPEG byte offered but not accepted.");

    csr_reg_def('h58, "TOTAL", "Frame cycles");
    let i_total_cycles   <- perf_counter(      'h58,                          pw_perf_rst,   "TOTAL",   "Total cycles",   "Frame start to last accepted JPEG byte, inclusive.");

    csr_reg_def('h5c, "PKTS", "UDP packets in the current or last frame");
    let i_packets        <- perf_counter(      'h5c,                          pw_perf_rst,   "PKTS",    "UDP packets",    "Packets accepted at the UDP boundary.");

    csr_reg_def('h60, "PERIOD", "Cycles between the last two frame starts");
    let rg_period        <- csr_reg_ho(        'h60, Bit#(32)'(0),        0,  w_period,      "PERIOD",  "Frame period",   "Zero until the second frame starts.");

    method clear_start  = pw_start_clear.send;
    method clear_verify = pw_verify_clear.send;
    method perf_rst     = pw_perf_rst.send;
    method frame_done   = pw_frame_done.send;

    method Action period(Bit#(32) value);
        w_period <= tagged Valid value;
    endmethod

    method Action status(Bit#(6) value, Bit#(32) checksum1, Bit#(32) checksum2, Bit#(32) packets, Bit#(32) pixels, Bit#(32) dropped);
        rg_status    <= value;
        rg_checksum1 <= checksum1;
        rg_checksum2 <= checksum2;
        rg_ldpkt     <= packets;
        rg_ldpix     <= pixels;
        rg_lddrop    <= dropped;
    endmethod

    interface start           = rg_start;
    interface repeat_frames   = reg_to_read_only(rg_repeat);
    interface load_enable     = reg_to_read_only(rg_load);
    interface verify          = rg_verify;
    interface npix            = reg_to_read_only(rg_npix);
    interface base            = reg_to_read_only(rg_base);
    interface memaddr         = reg_to_read_only(rg_memaddr);
    interface memory_request  = toGet(f_memory_request);
    interface memory_response = toPut(f_memory_response);
    method memory_pending     = f_memory_request.notEmpty;
    interface in_cycles       = i_in_cycles;
    interface in_stalls       = i_in_stalls;
    interface out_bytes       = i_out_bytes;
    interface out_cycles      = i_out_cycles;
    interface out_stalls      = i_out_stalls;
    interface total_cycles    = i_total_cycles;
    interface packets         = i_packets;
endmodule

endpackage
