package BlueJPEGClockCrossing;

import Clocks :: *;
import Connectable :: *;
import GetPut :: *;
import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Lite_Types :: *;
import AXI4_Stream :: *;

import BlueJPEG :: *;

typedef enum { ENCODER_IDLE, ENCODER_WAIT_IDLE, ENCODER_REQUEST, ENCODER_WAIT_END } EncoderRequestState_t deriving(Bits, Eq, FShow);

/*
 * Presents the encoder interface in the system clock domain. Stream sidebands
 * travel with their data. AXI-Lite writes are paired before crossing, with
 * responses returned only after the encoder transaction completes.
 *
 * One start request may be outstanding. The encoder domain retries the pulse
 * until busy is observed, then returns a completion token after busy falls.
 * System busy stays asserted throughout this handshake. Both domains must reset
 * from a common reset source so queued data and commands share one reset epoch.
 */
module mkBlueJPEGClockCrossing#(Clock clk_enc, Reset rst_enc, BlueJPEG_ifc encoder)(BlueJPEG_ifc);
    Clock clk_sys <- exposeCurrentClock;

    //pixel and JPEG streams
    AXI4_Stream_Rd#(24, 0)                i_pixels_sys <- mkAXI4_Stream_Rd(2);
    AXI4_Stream_Wr#(24, 0)                i_pixels_enc <- mkAXI4_Stream_Wr(2, clocked_by clk_enc, reset_by rst_enc);
    AXI4_Stream_Rd#(8, 0)                 i_jpeg_enc   <- mkAXI4_Stream_Rd(2, clocked_by clk_enc, reset_by rst_enc);
    AXI4_Stream_Wr#(8, 0)                 i_jpeg_sys   <- mkAXI4_Stream_Wr(2);
    SyncFIFOIfc#(AXI4_Stream_Pkg#(24, 0)) f_pixels     <- mkSyncFIFOFromCC(512, clk_enc);
    SyncFIFOIfc#(AXI4_Stream_Pkg#(8, 0))  f_jpeg       <- mkSyncFIFOToCC(2048, clk_enc, rst_enc);

    mkConnection(i_pixels_sys.pkg, toPut(f_pixels));
    mkConnection(toGet(f_pixels),  i_pixels_enc.pkg);
    mkConnection(i_pixels_enc.fab, encoder.s_axis);
    mkConnection(encoder.m_axis,   i_jpeg_enc.fab);
    mkConnection(i_jpeg_enc.pkg,   toPut(f_jpeg));
    mkConnection(toGet(f_jpeg),    i_jpeg_sys.pkg);

    //configuration bus
    AXI4_Lite_Slave_Rd#(32, 32)                   i_cfg_sys_rd <- mkAXI4_Lite_Slave_Rd(2);
    AXI4_Lite_Slave_Wr#(32, 32)                   i_cfg_sys_wr <- mkAXI4_Lite_Slave_Wr(2);
    AXI4_Lite_Master_Rd#(32, 32)                  i_cfg_enc_rd <- mkAXI4_Lite_Master_Rd(2, clocked_by clk_enc, reset_by rst_enc);
    AXI4_Lite_Master_Wr#(32, 32)                  i_cfg_enc_wr <- mkAXI4_Lite_Master_Wr(2, clocked_by clk_enc, reset_by rst_enc);
    SyncFIFOIfc#(AXI4_Lite_Read_Rq_Pkg#(32))      f_cfg_rd_req <- mkSyncFIFOFromCC(4, clk_enc);
    SyncFIFOIfc#(AXI4_Lite_Read_Rs_Pkg#(32))      f_cfg_rd_rsp <- mkSyncFIFOToCC(4, clk_enc, rst_enc);
    SyncFIFOIfc#(AXI4_Lite_Write_Rq_Pkg#(32, 32)) f_cfg_wr_req <- mkSyncFIFOFromCC(4, clk_enc);
    SyncFIFOIfc#(AXI4_Lite_Write_Rs_Pkg)          f_cfg_wr_rsp <- mkSyncFIFOToCC(4, clk_enc, rst_enc);

    mkConnection(i_cfg_sys_rd.request,  toPut(f_cfg_rd_req));
    mkConnection(toGet(f_cfg_rd_req),   i_cfg_enc_rd.request);
    mkConnection(i_cfg_enc_rd.response, toPut(f_cfg_rd_rsp));
    mkConnection(toGet(f_cfg_rd_rsp),   i_cfg_sys_rd.response);
    mkConnection(i_cfg_sys_wr.request,  toPut(f_cfg_wr_req));
    mkConnection(toGet(f_cfg_wr_req),   i_cfg_enc_wr.request);
    mkConnection(i_cfg_enc_wr.response, toPut(f_cfg_wr_rsp));
    mkConnection(toGet(f_cfg_wr_rsp),   i_cfg_sys_wr.response);
    mkConnection(i_cfg_enc_rd.fab,      encoder.s_axi_cfg_rd);
    mkConnection(i_cfg_enc_wr.fab,      encoder.s_axi_cfg_wr);

    //frame start handshake and status
    SyncFIFOIfc#(Bool)          f_start    <- mkSyncFIFOFromCC(2, clk_enc);
    SyncFIFOIfc#(Bool)          f_done     <- mkSyncFIFOToCC(2, clk_enc, rst_enc);
    SyncBitIfc#(Bit#(1))        i_busy     <- mkSyncBit(clk_enc, rst_enc, clk_sys);
    SyncBitIfc#(Bit#(1))        i_irq      <- mkSyncBit(clk_enc, rst_enc, clk_sys);
    Reg#(EncoderRequestState_t) rg_request <- mkReg(ENCODER_IDLE, clocked_by clk_enc, reset_by rst_enc);
    Reg#(Bool)                  rg_pending <- mkReg(False);
    PulseWire                   pw_start   <- mkPulseWire;
    PulseWire                   pw_done    <- mkPulseWire;

    rule r_status;
        i_busy.send(pack(encoder.busy));
        i_irq.send(pack(encoder.irq));
    endrule

    rule r_take_start (rg_request == ENCODER_IDLE);
        f_start.deq;
        rg_request <= ENCODER_WAIT_IDLE;
    endrule

    rule r_begin_request (rg_request == ENCODER_WAIT_IDLE && !encoder.busy);
        encoder.start_frame;
        rg_request <= ENCODER_REQUEST;
    endrule

    rule r_request_start (rg_request == ENCODER_REQUEST && !encoder.busy);
        encoder.start_frame;
    endrule

    rule r_observe_start (rg_request == ENCODER_REQUEST && encoder.busy);
        rg_request <= ENCODER_WAIT_END;
    endrule

    rule r_complete (rg_request == ENCODER_WAIT_END && !encoder.busy);
        f_done.enq(True);
        rg_request <= ENCODER_IDLE;
    endrule

    rule r_retire (rg_pending);
        f_done.deq;
        pw_done.send;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_pending;
        rg_pending <= (rg_pending || pw_start) && !pw_done;
    endrule

    interface s_axis       = i_pixels_sys.fab;
    interface m_axis       = i_jpeg_sys.fab;
    interface s_axi_cfg_rd = i_cfg_sys_rd.fab;
    interface s_axi_cfg_wr = i_cfg_sys_wr.fab;
    method busy            = rg_pending || i_busy.read == 1;
    method irq             = i_irq.read == 1;

    method Action start_frame if(!rg_pending && i_busy.read == 0);
        f_start.enq(True);
        pw_start.send;
    endmethod
endmodule

endpackage
