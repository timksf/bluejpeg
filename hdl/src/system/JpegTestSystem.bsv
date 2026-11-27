package JpegTestSystem;

import BRAM :: *;
import BRAMFIFO :: *;
import Clocks :: *;
import Connectable :: *;
import FIFOF :: *;
import GetPut :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Stream :: *;
import AxiStreamAsyncFifo :: *;
import BlueCSRAXI4LiteAdapter :: *;
import BlueCSRCore :: *;
import UartAxisBridge :: *;

import BlueJPEG :: *;
import BlueJPEGRegs :: *;
import JpegTestRegs :: *;
import StreamFabAdapters :: *;
import Types :: *;

//encoder configuration of the test system, the mkBlueJPEGTop_1920_12 synthesis variant
typedef 1920 SysMaxImgWidth;
typedef 12   SysDCTScale;
typedef 12   SysQuantScale;
typedef 8    SysPixelWidth;

//JPEG bytes buffered ahead of the UART so a frame never waits for the serial link
typedef 8192 OutputBufferBytes;

interface JpegTestSystem_ifc;
    (* prefix = "S_AXI_jpeg" *)
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_jpeg_rd;
    (* prefix = "S_AXI_jpeg" *)
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_jpeg_wr;
    (* prefix = "S_AXI_test" *)
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_test_rd;
    (* prefix = "S_AXI_test" *)
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_test_wr;

    //UART pins, clocked by the UART clock
    (* always_ready, always_enabled, prefix = "" *)
    method Action uart_rx((* port = "uart_rx" *) Bit#(1) value);
    (* always_ready, result = "uart_tx" *)
    method Bit#(1) uart_tx;

    (* always_ready *)
    method Bool irq;
    (* always_ready *)
    method Bool busy;
endinterface

/*
 * Pattern ROM -> BlueJPEG -> output buffer -> dual-clock FIFO -> UART.
 *
 * The encoder, both register maps and the pattern source run on the current (system) clock,
 * with the DCT on the same clock as in all encoder simulations. The UART runs on clk_uart.
 * A deep BRAM FIFO in the system domain takes the whole JPEG stream so the encoder output
 * is not throttled by the serial link, the dual-clock FIFO then crosses into the UART domain.
 * The UART bit time is a register in the system domain, synchronized into the UART domain.
 */
module [Module] mkJpegTestSystem#(Clock clk_uart, Reset rst_uart)(JpegTestSystem_ifc);
    Clock clk_sys <- exposeCurrentClock;
    Reset rst_sys <- exposeCurrentReset;

    //encoder
    BlueJPEGCfg_t#(SysMaxImgWidth, SysDCTScale, SysQuantScale, SysPixelWidth) cfg_jpeg = BlueJPEGCfg_t {
        slow_clock:          clk_sys,
        slow_reset:          rst_sys,
        _prx_miw:            ?,
        _prx_dsc:            ?,
        _prx_qsc:            ?,
        _prx_pixw:           ?,
        en_tiler:            True,
        double_buffer_tiler: True,
        en_chroma:           True,
        shallow_dct:         False
    };
    BlueJPEG_ifc i_enc <- mkBlueJPEG(cfg_jpeg);

    //test system registers
    BlueCSRAccess_ifc#(32, 32, 0, JpegTestRegs_ifc) i_regs     <- create_blue_csr(jpeg_test_regs, False);
    BlueCSR_AXI4Lite_ifc#(32, 32, 0)                i_regs_axi <- mkBlueCSRAXI4LiteAdapter(i_regs.external, 1, 1);
    JpegTestRegs_ifc                                regs       = i_regs.internal;

    //pattern ROM and pixel stream into the encoder
    BRAM_Configure cfg_rom = defaultValue;
    cfg_rom.memorySize   = valueOf(PatternPixels);
    cfg_rom.latency      = 1;
    cfg_rom.outFIFODepth = 3;
    cfg_rom.loadFormat   = tagged Hex pattern_file;

    BRAM1Port#(UInt#(16), Bit#(24)) i_rom     <- mkBRAM1Server(cfg_rom);
    AXI4_Stream_Wr#(24, 0)          i_pix_out <- mkAXI4_Stream_Wr(2);

    mkConnection(i_pix_out.fab, i_enc.s_axis);

    Reg#(Bool)      rg_streaming <- mkReg(False);
    Reg#(UInt#(32)) rg_req_idx   <- mkReg(0);
    Reg#(UInt#(32)) rg_resp_idx  <- mkReg(0);
    Reg#(UInt#(16)) rg_rom_addr  <- mkReg(0);
    PulseWire       pw_start     <- mkPulseWire;

    //JPEG stream out of the encoder into the output buffer
    AXI4_Stream_Rd#(8, 0)          i_jpeg_in <- mkAXI4_Stream_Rd(2);
    FIFOF#(AXI4_Stream_Pkg#(8, 0)) f_jpeg    <- mkSizedBRAMFIFOF(valueOf(OutputBufferBytes));

    mkConnection(i_enc.m_axis, i_jpeg_in.fab);

    //dual-clock FIFO into the UART domain
    AXI4_Stream_Wr#(8, 0)               i_jpeg_out <- mkAXI4_Stream_Wr(2);
    AxiStreamAsyncFifo_ifc#(8, 0, 0, 0) i_cdc      <- mkAxiStreamAsyncFifo(16, clk_sys, rst_sys, clk_uart);

    mkConnection(i_jpeg_out.fab, i_cdc.s_axis);

    //UART bit time, written in the system domain and read in the UART domain
    Reg#(Bit#(16))        rg_uart_div <- mkSyncRegFromCC(default_uart_div, clk_uart);
    UartAxisBridge#(8, 0) i_uart      <- mkUartAxisBridge(1, rg_uart_div, 2, 2, 0, 0, clocked_by clk_uart, reset_by rst_uart);

    mkConnection(i_cdc.m_axis, i_uart.s_axis, clocked_by clk_uart, reset_by rst_uart);

    //frame progress, owned by r_monitor
    Reg#(Bool) rg_enc_busy    <- mkReg(False);
    Reg#(Bool) rg_frame       <- mkReg(False);
    Reg#(Bool) rg_in_started  <- mkReg(False);
    Reg#(Bool) rg_in_done     <- mkReg(False);
    Reg#(Bool) rg_out_started <- mkReg(False);
    Reg#(Bool) rg_out_done    <- mkReg(False);

    //a frame start of the encoder starts the pattern stream
    rule r_start (!rg_streaming && regs.enable && i_enc.busy && !rg_enc_busy);
        regs.perf_rst;
        pw_start.send;
        rg_streaming <= True;
        rg_req_idx   <= 0;
        rg_resp_idx  <= 0;
        rg_rom_addr  <= 0;
    endrule

    rule r_rom_request (rg_streaming && rg_req_idx < regs.npix);
        i_rom.portA.request.put(BRAMRequest { write: False, responseOnWrite: False, address: rg_rom_addr, datain: ? });
        rg_rom_addr <= (rg_rom_addr == fromInteger(valueOf(PatternPixels) - 1)) ? 0 : rg_rom_addr + 1;
        rg_req_idx  <= rg_req_idx + 1;
    endrule

    rule r_rom_response (rg_streaming);
        let pixel <- i_rom.portA.response.get;
        Bool last = rg_resp_idx == regs.npix - 1;
        i_pix_out.pkg.put(AXI4_Stream_Pkg { data: pixel, user: 0, keep: '1, dest: 0, id: 0, last: last });
        rg_resp_idx <= rg_resp_idx + 1;
        if(last) rg_streaming <= False;
    endrule

    rule r_buffer_in;
        let beat <- i_jpeg_in.pkg.get;
        f_jpeg.enq(beat);
    endrule

    rule r_buffer_out;
        i_jpeg_out.pkg.put(f_jpeg.first);
        f_jpeg.deq;
    endrule

    rule r_uart_div;
        rg_uart_div <= regs.uart_div;
    endrule

    //the UART receive direction is not used, received bytes are dropped
    (* fire_when_enabled, no_implicit_conditions *)
    rule r_uart_rx_drop;
        i_uart.m_axis.ptready(True);
    endrule

    /*
     * Watches the handshakes at the encoder's stream ports. The input window runs from the
     * first to the last accepted pixel, the output window from the first to the last JPEG byte,
     * and the frame from the stream start to the last JPEG byte. A start clears all windows,
     * and the counters restart in the same cycle.
     */
    (* fire_when_enabled, no_implicit_conditions *)
    rule r_monitor;
        Bool in_valid  = i_pix_out.fab.tvalid;
        Bool in_hs     = in_valid && i_enc.s_axis.tready;
        Bool in_last   = in_hs && i_pix_out.fab.tlast;
        Bool out_valid = i_enc.m_axis.tvalid;
        Bool out_hs    = out_valid && i_jpeg_in.fab.tready;
        Bool out_last  = out_hs && i_enc.m_axis.tlast;

        Bool in_started  = !pw_start && rg_in_started;
        Bool in_done     = !pw_start && rg_in_done;
        Bool out_started = !pw_start && rg_out_started;
        Bool out_done    = !pw_start && rg_out_done;

        Bool in_window  = (in_started || in_hs) && !in_done;
        Bool out_window = (out_started || out_hs) && !out_done;
        Bool frame      = pw_start || rg_frame;

        if(in_window) regs.in_cycles.tick;
        if(in_window && in_valid && !in_hs) regs.in_stalls.tick;
        if(out_hs) regs.out_bytes.tick;
        if(out_window) regs.out_cycles.tick;
        if(out_window && out_valid && !out_hs) regs.out_stalls.tick;
        if(frame) regs.total_cycles.tick;

        rg_enc_busy    <= i_enc.busy;
        rg_frame       <= frame && !out_last;
        rg_in_started  <= in_started || in_hs;
        rg_in_done     <= in_done || in_last;
        rg_out_started <= out_started || out_hs;
        rg_out_done    <= out_done || out_last;
    endrule

    rule r_status;
        regs.status(rg_streaming, rg_in_done, rg_out_done);
    endrule

    interface s_jpeg_rd = i_enc.s_axi_cfg_rd;
    interface s_jpeg_wr = i_enc.s_axi_cfg_wr;
    interface s_test_rd = i_regs_axi.s_rd;
    interface s_test_wr = i_regs_axi.s_wr;
    method uart_rx      = i_uart.rx;
    method uart_tx      = i_uart.tx;
    method irq          = i_enc.irq;
    method busy         = rg_streaming || (rg_out_started && !rg_out_done);
endmodule

endpackage
