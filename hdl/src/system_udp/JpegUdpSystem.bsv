package JpegUdpSystem;

import Clocks :: *;
import Connectable :: *;
import GetPut :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Master :: *;
import AXI4_Stream :: *;
import BlueCSRAXI4LiteAdapter :: *;
import BlueCSRCore :: *;
import EthernetTypes :: *;
import UdpRgmiiCsr :: *;

import BlueJPEG :: *;
import BlueJPEGClockCrossing :: *;
import BlueJPEGRegs :: *;
import JpegUdpRegs :: *;
import UdpFrameStore :: *;
import UdpLoader :: *;
import UdpPacketizer :: *;
import Types :: *;

interface JpegUdpSystem_ifc;
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32)   s_jpeg_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32)   s_jpeg_wr;
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32)   s_sys_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32)   s_sys_wr;
    interface AXI4_Master_Rd_Fab#(30, 32, 4, 0) m_mem_rd;
    interface AXI4_Master_Wr_Fab#(30, 32, 4, 0) m_mem_wr;
    interface Put#(UdpRxHeader)                 rx_header;
    interface EthernetStreamSink_ifc            rx_payload;
    interface Get#(UdpTxRequest)                tx_header;
    interface EthernetStreamSource_ifc          tx_payload;
    method Bool                                 irq;
    method Bool                                 busy;
endinterface

module [Module] mkJpegUdpSystem#(Bool calibrated)(JpegUdpSystem_ifc);
    Clock             clk_sys <- exposeCurrentClock;
    Reset             rst_sys <- exposeCurrentReset;
    JpegUdpSystem_ifc i_sys   <- mkJpegUdpSystemDct(calibrated, clk_sys, rst_sys);
    return i_sys;
endmodule

module [Module] mkUdpEncoder#(Clock clk_dct, Reset rst_dct)(BlueJPEG_ifc);
    BlueJPEGCfg_t#(1920, 12, 12, 8) cfg = BlueJPEGCfg_t {
        slow_clock:          clk_dct,
        slow_reset:          rst_dct,
        _prx_miw:            ?,
        _prx_dsc:            ?,
        _prx_qsc:            ?,
        _prx_pixw:           ?,
        en_tiler:            True,
        double_buffer_tiler: True,
        en_chroma:           True
    };
    BlueJPEG_ifc i_encoder <- mkBlueJPEG(cfg);
    return i_encoder;
endmodule

module [Module] mkJpegUdpSystemDct#(Bool calibrated, Clock clk_dct, Reset rst_dct)(JpegUdpSystem_ifc);
    BlueJPEG_ifc      i_encoder <- mkUdpEncoder(clk_dct, rst_dct);
    JpegUdpSystem_ifc i_sys     <- mkJpegUdpSystemEncoder(calibrated, i_encoder);
    return i_sys;
endmodule

module [Module] mkJpegUdpSystemAsync#(Bool calibrated, Clock clk_enc, Reset rst_enc, Clock clk_dct, Reset rst_dct)(JpegUdpSystem_ifc);
    BlueJPEG_ifc      i_encoder     <- mkUdpEncoder(clk_dct, rst_dct, clocked_by clk_enc, reset_by rst_enc);
    BlueJPEG_ifc      i_encoder_cdc <- mkBlueJPEGClockCrossing(clk_enc, rst_enc, i_encoder);
    JpegUdpSystem_ifc i_sys         <- mkJpegUdpSystemEncoder(calibrated, i_encoder_cdc);
    return i_sys;
endmodule

module [Module] mkJpegUdpSystemEncoder#(Bool calibrated, BlueJPEG_ifc i_enc)(JpegUdpSystem_ifc);
    UdpFrameStore_ifc i_store      <- mkUdpFrameStore;
    UdpLoader_ifc     i_loader     <- mkUdpLoader;
    UdpPacketizer_ifc i_packetizer <- mkUdpPacketizer;

    BlueCSRAccess_ifc#(32, 32, 0, JpegUdpRegs_ifc) i_regs <- create_blue_csr(jpeg_udp_regs, False);
    BlueCSR_AXI4Lite_ifc#(32, 32, 0)               i_axi  <- mkBlueCSRAXI4LiteAdapter(i_regs.external, 1, 1);
    JpegUdpRegs_ifc                                regs   = i_regs.internal;

    AXI4_Stream_Wr#(24, 0) i_pixels <- mkAXI4_Stream_Wr(2);
    AXI4_Stream_Rd#(8, 0)  i_jpeg   <- mkAXI4_Stream_Rd(2);

    mkConnection(i_store.pixels,  i_pixels.pkg);
    mkConnection(i_pixels.fab,    i_enc.s_axis);
    mkConnection(i_enc.m_axis,    i_jpeg.fab);
    mkConnection(i_jpeg.pkg,      i_packetizer.jpeg);
    mkConnection(i_loader.pixels, i_store.load);

    Reg#(Bool)     rg_frame          <- mkReg(False);
    Reg#(Bool)     rg_encoder_seen   <- mkReg(False);
    Reg#(Bool)     rg_in_started     <- mkReg(False);
    Reg#(Bool)     rg_in_done        <- mkReg(False);
    Reg#(Bool)     rg_out_started    <- mkReg(False);
    Reg#(Bool)     rg_out_done       <- mkReg(False);
    Reg#(Bool)     rg_memory_pending <- mkReg(False);
    Reg#(Bool)     rg_had_start      <- mkReg(False);
    Reg#(Bit#(32)) rg_cycle          <- mkReg(0);
    Reg#(Bit#(32)) rg_last_start     <- mkReg(0);
    PulseWire      pw_start          <- mkPulseWire;
    PulseWire      pw_memory_start   <- mkPulseWire;
    PulseWire      pw_memory_done    <- mkPulseWire;

    Bool idle           = !rg_frame && !i_enc.busy && i_store.idle && !i_loader.active && !rg_memory_pending;
    Bool valid_frame    = udp_frame_range_valid(regs.base, regs.npix);
    Bool memory_allowed = calibrated && idle && regs.memaddr < 'h10000000;

    rule r_loader_config;
        i_loader.configure(calibrated && !rg_frame && !i_enc.busy && !rg_memory_pending && (i_store.idle || i_store.loading) && valid_frame && regs.load_enable && !regs.start && !regs.repeat_frames && !regs.verify && !regs.memory_pending, regs.base, regs.npix);
    endrule

    rule r_start (calibrated && idle && valid_frame && !regs.verify && !regs.memory_pending && (regs.start || regs.repeat_frames));
        i_enc.start_frame;
        i_store.start(regs.base, regs.npix, False);
        regs.clear_start;
        regs.perf_rst;
        pw_start.send;
    endrule

    //retry during table initialization, the request is a pulse and never queues in the encoder
    rule r_wait_encoder (rg_frame && !rg_encoder_seen && !i_enc.busy);
        i_enc.start_frame;
    endrule

    rule r_verify (calibrated && idle && valid_frame && regs.verify && !regs.memory_pending);
        i_store.start(regs.base, regs.npix, True);
        regs.clear_verify;
    endrule

    rule r_memory_request (regs.memory_pending && !rg_memory_pending && memory_allowed);
        let request <- regs.memory_request.get;
        i_store.memory(regs.memaddr, request.wr, request.wdata, request.wstrb);
        pw_memory_start.send;
    endrule

    rule r_memory_reject (regs.memory_pending && !rg_memory_pending && !memory_allowed);
        let request <- regs.memory_request.get;
        regs.memory_response.put(BlueCSR_Rsp_t { rdata: 0, resp: CSR_SLVERR });
    endrule

    rule r_memory_response (rg_memory_pending);
        match {.data, .error} <- i_store.memory_response.get;
        regs.memory_response.put(BlueCSR_Rsp_t { rdata: data, resp: error ? CSR_SLVERR : CSR_OKAY });
        pw_memory_done.send;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_monitor;
        Bool in_valid    = i_pixels.fab.tvalid;
        Bool in_hs       = in_valid && i_enc.s_axis.tready;
        Bool in_last     = in_hs && i_pixels.fab.tlast;
        Bool out_valid   = i_enc.m_axis.tvalid;
        Bool out_hs      = out_valid && i_jpeg.fab.tready;
        Bool out_last    = out_hs && i_enc.m_axis.tlast;
        Bool in_started  = !pw_start && rg_in_started;
        Bool in_done     = !pw_start && rg_in_done;
        Bool out_started = !pw_start && rg_out_started;
        Bool out_done    = !pw_start && rg_out_done;
        Bool frame       = pw_start || rg_frame;

        if((in_started || in_hs) && !in_done) regs.in_cycles.tick;
        if((in_started || in_hs) && !in_done && in_valid && !in_hs) regs.in_stalls.tick;
        if(out_hs) regs.out_bytes.tick;
        if((out_started || out_hs) && !out_done) regs.out_cycles.tick;
        if((out_started || out_hs) && !out_done && out_valid && !out_hs) regs.out_stalls.tick;
        if(frame && !out_done) regs.total_cycles.tick;
        if(i_packetizer.packet_sent) regs.packets.tick;
        if(i_packetizer.frame_done) regs.frame_done;

        if(pw_start) begin
            regs.period(rg_had_start ? rg_cycle - rg_last_start : 0);
            rg_last_start <= rg_cycle;
            rg_had_start  <= True;
        end

        rg_cycle          <= rg_cycle + 1;
        rg_frame          <= frame && !i_packetizer.frame_done;
        rg_encoder_seen   <= !pw_start && (rg_encoder_seen || i_enc.busy);
        rg_in_started     <= in_started || in_hs;
        rg_in_done        <= in_done || in_last;
        rg_out_started    <= out_started || out_hs;
        rg_out_done       <= out_done || out_last;
        rg_memory_pending <= (rg_memory_pending || pw_memory_start) && !pw_memory_done;
    endrule

    rule r_status;
        regs.status({pack(i_store.error), pack(i_loader.active), pack(i_store.reader_active), pack(i_store.verify_done), pack(calibrated), pack(rg_frame)}, i_store.checksum1, i_store.checksum2, i_loader.packets, i_loader.pixels_written, i_loader.dropped);
    endrule

    interface s_jpeg_rd  = i_enc.s_axi_cfg_rd;
    interface s_jpeg_wr  = i_enc.s_axi_cfg_wr;
    interface s_sys_rd   = i_axi.s_rd;
    interface s_sys_wr   = i_axi.s_wr;
    interface m_mem_rd   = i_store.m_rd;
    interface m_mem_wr   = i_store.m_wr;
    interface rx_header  = i_loader.rx_header;
    interface rx_payload = i_loader.rx_payload;
    interface tx_header  = i_packetizer.tx_header;
    interface tx_payload = i_packetizer.tx_payload;
    method irq           = i_enc.irq;
    method busy          = rg_frame;
endmodule

endpackage
