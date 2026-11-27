package TbJpegDecoder;

import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import BlueAXI :: *;
import BlueCSR :: *;

import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;
import BlueJPEGDec :: *;

/*
 * Streams the input files of the simulation directory through one decoder
 * instance over AXI-Stream and writes the decoded YCbCr pixels (three bytes
 * each) of every frame to dec_out_<i>.raw. test/host/jpeg_decoder_check.py
 * creates the inputs and compares the outputs against libjpeg.
 *
 * Input i is the first of these files that exists, missing indices are
 * skipped:
 *
 *   dec_in_<i>.jpg    a valid frame, checked against libjpeg
 *   dec_bad_<i>.jpg   damaged entropy-coded data, the frame leaves concealed
 *   dec_skip_<i>.jpg  a frame the decoder rejects, no pixels leave
 *
 * After a valid frame the stream pauses until the frame has left and the
 * testbench has checked IMSZ, PERF2 and the frame-done interrupt over
 * AXI-Lite, so the printed cycles cover one frame from its first byte. After
 * a damaged or rejected frame the next file follows right away, like the next
 * frame of a camera, which also completes a frame that was cut short. At the
 * end PERF4 must count the frames that left and PERF5 at least one error per
 * damaged or rejected input, or none without such inputs.
 */

typedef 24 NumImages;

typedef 256 MaxImgWidth;
typedef 13  IDCTScale;
typedef 8   DequantScale;
typedef 8   PixelWidth;

typedef enum { None, Clean, Bad, Skip } InputKind_t deriving(Bits, Eq, FShow);

module [Module] mkTbJpegDecoderCase#(
    Bool        en_untiler,
    Bool        double_buffer,
    Bool        en_chroma,
    Bool        en_look,
    ChromaSub_t max_sub
)(TestHandler_ifc);

    function print_s   = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let cur_clk <- exposeCurrentClock;
    let cur_rst <- exposeCurrentReset;

    BlueJPEGDecCfg_t#(MaxImgWidth, IDCTScale, DequantScale, PixelWidth) cfg = BlueJPEGDecCfg_t {
        slow_clock:            cur_clk,
        slow_reset:            cur_rst,
        _prx_miw:              ?,
        _prx_dsc:              ?,
        _prx_qsc:              ?,
        _prx_pixw:             ?,
        en_untiler:            en_untiler,
        double_buffer_untiler: double_buffer,
        en_chroma:             en_chroma,
        en_huff_lookahead:     en_look,
        max_chroma_sub:        max_sub
    };
    BlueJPEGDec_ifc dut      <- mkBlueJPEGDec(cfg);
    let             csr_defs <- build_blue_csr_tb_lookup(blue_jpeg_dec_csrs);

    AXI4_Lite_Master_Rd#(32, 32) i_cfg_rd  <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_cfg_wr  <- mkAXI4_Lite_Master_Wr(4);
    let                          i_cfg_acc <- mkBlueCSRTbAccessorAXI4Lite(csr_defs, i_cfg_rd, i_cfg_wr);

    AXI4_Stream_Wr#(8, 0)  i_axis_tx <- mkAXI4_Stream_Wr(16);
    AXI4_Stream_Rd#(24, 0) i_axis_rx <- mkAXI4_Stream_Rd(16);

    mkConnection(i_axis_tx.fab,    dut.s_axis);
    mkConnection(dut.m_axis,       i_axis_rx.fab);
    mkConnection(dut.s_axi_cfg_rd, i_cfg_rd.fab);
    mkConnection(dut.s_axi_cfg_wr, i_cfg_wr.fab);

    Vector#(NumImages, Reg#(InputKind_t)) rg_kind  <- replicateM(mkReg(None));
    Vector#(NumImages, Reg#(UInt#(64)))   rg_start <- replicateM(mkReg(0));
    Vector#(NumImages, Reg#(UInt#(32)))   rg_size  <- replicateM(mkReg(0));

    //producer
    Reg#(File)      rg_in       <- mkReg(InvalidFile);
    Reg#(Bool)      rg_eof      <- mkReg(False);
    Reg#(UInt#(32)) rg_bytes    <- mkReg(0);
    Reg#(UInt#(32)) rg_opened   <- mkReg(0);
    Reg#(UInt#(32)) rg_produced <- mkReg(0);
    Reg#(UInt#(32)) rg_need     <- mkReg(0);

    //consumer
    Reg#(File)      rg_out      <- mkReg(InvalidFile);
    Reg#(Bool)      rg_done     <- mkReg(False);
    Reg#(UInt#(32)) rg_pixels   <- mkReg(0);
    Reg#(UInt#(32)) rg_consumed <- mkReg(0);
    Reg#(UInt#(32)) rg_frames   <- mkReg(0);
    Reg#(UInt#(32)) rg_damaged  <- mkReg(0);
    Reg#(Bit#(32))  rg_pix_ctr  <- mkReg(0);
    Reg#(Bit#(32))  rg_rsp      <- mkReg(0);
    Reg#(Bit#(32))  rg_imsz     <- mkReg(0);
    Reg#(UInt#(64)) rg_t_end    <- mkReg(0);

    Reg#(UInt#(64)) rg_cycle <- mkReg(0);

    rule r_cycle;
        rg_cycle <= rg_cycle + 1;
        if(rg_cycle == 50_000_000) begin
            print_s("ERROR: timeout", RED);
            $finish(1);
        end
    endrule

    function Action check_cond(Bool cond, String msg) = action
        if(!cond) begin
            print_fmt($format("ERROR: ", msg), RED);
            $finish(1);
        end
    endaction;

    function Stmt read_reg(String ident) = seq
        i_cfg_acc.read_reg_req(ident);
        action
            let r <- i_cfg_acc.read_reg_rsp();
            rg_rsp <= tpl_1(r);
        endaction
    endseq;

    function String in_name(Integer i, InputKind_t k);
        String pre = k == Bad ? "dec_bad_" : (k == Skip ? "dec_skip_" : "dec_in_");
        return pre + integerToString(i) + ".jpg";
    endfunction

    //finds input i and opens it, the kind stays None when no file exists
    function Stmt open_input(Integer i) = seq
        action
            let fd <- $fopen(in_name(i, Clean), "rb");
            rg_in <= fd;
            if(fd != InvalidFile) rg_kind[i] <= Clean;
        endaction
        if(rg_in == InvalidFile) action
            let fd <- $fopen(in_name(i, Bad), "rb");
            rg_in <= fd;
            if(fd != InvalidFile) rg_kind[i] <= Bad;
        endaction
        if(rg_in == InvalidFile) action
            let fd <- $fopen(in_name(i, Skip), "rb");
            rg_in <= fd;
            if(fd != InvalidFile) rg_kind[i] <= Skip;
        endaction
    endseq;

    //shared loops, each input only starts them, which keeps the unrolled statement small

    Stmt stream = seq
        rg_eof <= False;
        while(!rg_eof) action
            int c <- $fgetc(rg_in);
            if(c == -1) rg_eof <= True;
            else begin
                i_axis_tx.pkg.put(AXI4_Stream_Pkg {
                    data: truncate(pack(c)),
                    user: 0,
                    keep: unpack(-1),
                    dest: 0,
                    last: False,
                    id:   0
                });
                rg_bytes <= rg_bytes + 1;
            end
        endaction
        $fclose(rg_in);
    endseq;

    Stmt collect = seq
        action
            rg_done   <= False;
            rg_pixels <= 0;
        endaction
        while(!rg_done) action
            let p <- i_axis_rx.pkg.get;
            YCbCr_t px = unpack(p.data);
            $fwrite(rg_out, "%c%c%c", px.y, px.cb, px.cr);
            rg_pixels <= rg_pixels + 1;
            if(p.last) rg_done <= True;
        endaction
        action
            $fclose(rg_out);
            rg_frames  <= rg_frames + 1;
            rg_pix_ctr <= rg_pix_ctr + pack(rg_pixels);
        endaction
    endseq;

    //the stream pauses after a valid frame, so the registers belong to this frame
    Stmt check_frame = seq
        await(dut.irq);
        read_reg("IMSZ");
        action
            rg_imsz  <= rg_rsp;
            rg_t_end <= rg_cycle;
        endaction
        read_reg("PERF2");
        check_cond(rg_rsp == rg_pix_ctr, "PERF2 does not match the received pixel count");
        action
            let done_bit <- i_cfg_acc.field_bit("IRQP", "DONE");
            i_cfg_acc.write_reg_req("IRQP", 1 << done_bit);
        endaction
        action
            let r <- i_cfg_acc.write_reg_rsp();
        endaction
        check_cond(!dut.irq, "irq must drop after clearing IRQP.DONE");
    endseq;

    FSM i_stream  <- mkFSM(stream);
    FSM i_collect <- mkFSM(collect);
    FSM i_check   <- mkFSM(check_frame);

    function Stmt produce(Integer i) = seq
        open_input(i);
        //the consumer collects the frame while it streams in
        rg_opened <= fromInteger(i + 1);
        if(rg_in != InvalidFile) seq
            //wait until the last valid frame has left and was checked
            await(rg_consumed >= rg_need);
            action
                rg_bytes    <= 0;
                rg_start[i] <= rg_cycle;
                i_stream.start;
            endaction
            i_stream.waitTillDone;
            rg_size[i] <= rg_bytes;
        endseq
        action
            rg_produced <= fromInteger(i + 1);
            if(rg_kind[i] == Clean) rg_need <= fromInteger(i + 1);
        endaction
    endseq;

    function Stmt consume(Integer i) = seq
        await(rg_opened > fromInteger(i));
        if(rg_kind[i] == Clean || rg_kind[i] == Bad) seq
            action
                let fd <- $fopen("dec_out_" + integerToString(i) + ".raw", "wb");
                rg_out <= fd;
                i_collect.start;
            endaction
            i_collect.waitTillDone;
        endseq
        if(rg_kind[i] == Clean) seq
            await(rg_produced > fromInteger(i));
            i_check.start;
            i_check.waitTillDone;
            print_fmt($format("%s: %0dx%0d, %0d bytes, %0d pixels, %0d cycles",
                in_name(i, Clean), rg_imsz[15:0], rg_imsz[31:16], rg_size[i], rg_pixels, rg_t_end - rg_start[i]), GREEN);
        endseq
        action
            if(rg_kind[i] == Bad)  print_fmt($format("%s: concealed frame, %0d pixels", in_name(i, Bad), rg_pixels), GREEN);
            if(rg_kind[i] == Skip) print_fmt($format("%s: rejected frame", in_name(i, Skip)), GREEN);
            if(rg_kind[i] == Bad || rg_kind[i] == Skip) rg_damaged <= rg_damaged + 1;
            rg_consumed <= fromInteger(i + 1);
        endaction
    endseq;

    Stmt producer = seq endseq;
    Stmt consumer = seq endseq;
    for(Integer i = 0; i < valueOf(NumImages); i = i + 1) begin
        producer = seq producer; produce(i); endseq;
        consumer = seq consumer; consume(i); endseq;
    end

    Stmt main = seq
        print_s("=== TbJpegDecoder start ===", GREEN);
        action
            let done_bit <- i_cfg_acc.field_bit("IRQE", "DONE");
            i_cfg_acc.write_reg_req("IRQE", 1 << done_bit);
        endaction
        action
            let r <- i_cfg_acc.write_reg_rsp();
        endaction
        par
            producer;
            consumer;
        endpar
        read_reg("PERF4");
        check_cond(unpack(rg_rsp) == rg_frames, "PERF4 does not match the decoded frame count");
        read_reg("PERF5");
        if(rg_damaged == 0) check_cond(rg_rsp == 0, "PERF5 counts errors without damaged inputs");
        else check_cond(unpack(rg_rsp) >= rg_damaged, "PERF5 counts fewer errors than damaged inputs");
        read_reg("ERR");
        check_cond((rg_rsp == 0) == (rg_damaged == 0), "ERR does not match the damaged inputs");
        if(rg_frames == 0) print_s("ERROR: no input found", RED);
        print_fmt($format("decoded %0d frames, %0d damaged or rejected inputs", rg_frames, rg_damaged), GREEN);
    endseq;

    FSM i_fsm <- mkFSM(main);

    method Action go();
        i_fsm.start();
    endmethod

    method Bool done();
        return i_fsm.done();
    endmethod

endmodule

module [Module] mkTbJpegDecoder(TestHandler_ifc);
    let ifc <- mkTbJpegDecoderCase(True, True, True, False, Sub420);
    return ifc;
endmodule

endpackage
