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
 * Streams dec_in_<i>.jpg from the simulation directory through one decoder
 * instance back to back over AXI-Stream and writes the decoded YCbCr pixels
 * (three bytes each) to dec_out_<i>.raw. Missing inputs are skipped. After
 * each frame the testbench checks IMSZ, PERF2 and the frame-done interrupt
 * over AXI-Lite. test/host/jpeg_decoder_check.py creates the inputs and
 * compares the outputs against libjpeg.
 *
 * This package holds the color configuration with raster output and double
 * buffering. TbJpegDecoderGray and TbJpegDecoderBlocks cover the other
 * configurations.
 */

typedef 6 NumImages;

typedef 256 MaxImgWidth;
typedef 13  IDCTScale;
typedef 8   DequantScale;
typedef 8   PixelWidth;

module [Module] mkTbJpegDecoderCase#(Bool en_untiler, Bool double_buffer, Bool en_chroma, Bool en_look)(TestHandler_ifc);

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
        en_huff_lookahead:     en_look
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

    Reg#(File)      rg_in      <- mkReg(InvalidFile);
    Reg#(File)      rg_out     <- mkReg(InvalidFile);
    Reg#(Bool)      rg_eof     <- mkReg(False);
    Reg#(Bool)      rg_done    <- mkReg(False);
    Reg#(UInt#(32)) rg_pixels  <- mkReg(0);
    Reg#(UInt#(32)) rg_bytes   <- mkReg(0);
    Reg#(UInt#(64)) rg_cycle   <- mkReg(0);
    Reg#(UInt#(64)) rg_t_start <- mkReg(0);
    Reg#(UInt#(32)) rg_decoded <- mkReg(0);
    Reg#(Bit#(32))  rg_rsp     <- mkReg(0);
    Reg#(Bit#(32))  rg_pix_ctr <- mkReg(0);

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

    function Stmt run_image(Integer i);
        String in_name  = "dec_in_"  + integerToString(i) + ".jpg";
        String out_name = "dec_out_" + integerToString(i) + ".raw";
        return seq
            action
                let fd <- $fopen(in_name, "rb");
                rg_in      <= fd;
                rg_eof     <= False;
                rg_done    <= False;
                rg_pixels  <= 0;
                rg_bytes   <= 0;
                rg_t_start <= rg_cycle;
            endaction
            if(rg_in != InvalidFile) seq
                action
                    let fd <- $fopen(out_name, "wb");
                    rg_out <= fd;
                endaction
                par
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
                    while(!rg_done) action
                        let p <- i_axis_rx.pkg.get;
                        YCbCr_t px = unpack(p.data);
                        $fwrite(rg_out, "%c%c%c", px.y, px.cb, px.cr);
                        rg_pixels <= rg_pixels + 1;
                        if(p.last) rg_done <= True;
                    endaction
                endpar
                action
                    $fclose(rg_in);
                    $fclose(rg_out);
                endaction

                //frame-done interrupt, then clear it with W1C
                await(dut.irq);
                read_reg("IMSZ");
                print_fmt($format("%s: %0dx%0d, %0d bytes, %0d pixels, %0d cycles",
                    in_name, rg_rsp[15:0], rg_rsp[31:16], rg_bytes, rg_pixels, rg_cycle - rg_t_start), GREEN);
                //PERF2 counts freely, so the frame is the difference to the previous reading
                read_reg("PERF2");
                check_cond(unpack(rg_rsp - rg_pix_ctr) == rg_pixels, "PERF2 does not match the received pixel count");
                rg_pix_ctr <= rg_rsp;
                action
                    let done_bit <- i_cfg_acc.field_bit("IRQP", "DONE");
                    i_cfg_acc.write_reg_req("IRQP", 1 << done_bit);
                endaction
                action
                    let r <- i_cfg_acc.write_reg_rsp();
                endaction
                check_cond(!dut.irq, "irq must drop after clearing IRQP.DONE");
                rg_decoded <= rg_decoded + 1;
            endseq
        endseq;
    endfunction

    Stmt all_images = seq endseq;
    for(Integer i = 0; i < valueOf(NumImages); i = i + 1)
        all_images = seq all_images; run_image(i); endseq;

    Stmt main = seq
        print_s("=== TbJpegDecoder start ===", GREEN);
        action
            let done_bit <- i_cfg_acc.field_bit("IRQE", "DONE");
            i_cfg_acc.write_reg_req("IRQE", 1 << done_bit);
        endaction
        action
            let r <- i_cfg_acc.write_reg_rsp();
        endaction
        all_images;
        read_reg("ERR");
        check_cond(rg_rsp == 0, "ERR reports an error");
        read_reg("PERF4");
        check_cond(unpack(rg_rsp) == rg_decoded, "PERF4 does not match the decoded frame count");
        if(rg_decoded == 0) print_s("ERROR: no dec_in_*.jpg found", RED);
        print_fmt($format("decoded %0d images", rg_decoded), GREEN);
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
    let ifc <- mkTbJpegDecoderCase(True, True, True, False);
    return ifc;
endmodule

endpackage
