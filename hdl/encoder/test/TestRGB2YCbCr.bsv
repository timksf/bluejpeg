package TestRGB2YCbCr;

import StmtFSM :: *;
import ClientServer :: *;
import GetPut :: *;
import Connectable :: *;
import List :: *;
import Vector :: *;

import BlueAXI :: *;

import BDPI :: *;
import Types :: *;
import PrintUtil :: *;
import RGB2YCbCr :: *;
import TestHelper :: *;
import SimRAM_AXI :: *;

String input_image_path = "../../../assets/sample_1920x1280.bmp"; //`IM_PATH;
String output_image_path = "../result.png"; //`RES_PATH;

typedef 1920 InputWidth;
typedef 1280 InputHeight;


module [Module] mkTestRGB2YCbCr(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t1 <- imageTest;

    Stmt s = seq
        t1.go();
        while(!t1.done()) action endaction
    endseq;

    FSM testFSM <- mkFSM(s);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod

endmodule

module [Module] simpleTest(TestHandler);
    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    NumProxy#(17) coeff_width = ?;
    RGB2YCbCr_params#(17) conv_params = RGB2YCbCr_params {
        a : 9798,
        log2_b : 15,
        c : 3736,
        d : 18492,
        e : 23372
    };

    //AXI drivers
    AXI4_Lite_Master_Rd#(32, 32) config_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) config_wr <- mkAXI4_Lite_Master_Wr(1);
    AXI4_Stream_Wr#(24, 0) axis_tx <- mkAXI4_Stream_Wr(1);
    AXI4_Stream_Rd#(24, 0) axis_rx <- mkAXI4_Stream_Rd(1);

    //DUT
    RGB2YCbCr_ifc#(24) rgb2ycbcr <- mkRGB2YCbCrTop;

    mkConnection(config_rd.fab, rgb2ycbcr.fab_config_rd);
    mkConnection(config_wr.fab, rgb2ycbcr.fab_config_wr);
    mkConnection(axis_tx.fab, rgb2ycbcr.fab_data_rd);
    mkConnection(rgb2ycbcr.fab_data_wr, axis_rx.fab);

    Reg#(Bit#(32)) rAXILRsp <- mkRegU;
    // RGB2YCbCrConv_ifc conv <- mkRGB2YCbCrConverter(coeff_width, conv_params);

    Stmt s = seq
        print_mod_pre_color_t_s("Start", GREEN);
        //configure coefficients
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_a_offs), pack(extend(conv_params.a)));
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_log2b_offs), pack(extend(conv_params.log2_b)));
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_c_offs), pack(extend(conv_params.c)));
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_d_offs), pack(extend(conv_params.d)));
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_e_offs), pack(extend(conv_params.e)));
        //start
        axi4_lite_write(config_wr, fromInteger(cfg_start_offs), 1);
        //dispatch data
        action
            RGB_t rgb = RGB_t { r : 24, g : 12, b : 77 };
            axis_tx.pkg.put(AXI4_Stream_Pkg {
                data: pack(rgb),
                user: ?,
                keep: unpack(-1), //keep all
                dest: ?,
                last: True //last transfer in stream
            });
        endaction
        //wait for result
        action
            let res <- axis_rx.pkg.get();
            YCbCr_t ycbcr = unpack(res.data);
            Bit#(32) ref_raw = rgb2ycbcr_model(24, 12, 77);
            YCbCr_t ref_res = YCbCr_t { 
                y:  unpack(truncate((ref_raw & 'hFF0000) >> 16)),
                cb: unpack(truncate((ref_raw & 'hFF00) >> 8)),
                cr: unpack(truncate(ref_raw & 'hFF))
            };
            print_fmt($format("Result: ") + fshow(ycbcr) + $format(" Ref: ") + fshow(ref_res), GREEN);
        endaction
        rAXILRsp <= 0;
        while(!unpack(rAXILRsp[0])) par
            axi4_lite_read(config_rd, fromInteger(cfg_finished_offs));
            action
                let resp <- axi4_lite_read_response(config_rd);
                rAXILRsp <= resp;
            endaction
        endpar
        print_s("Module signaled finished computation", GREEN);
        //read back some stats
        axi4_lite_read(config_rd, fromInteger(cfg_pixel_ctr_offs));
        action
            let resp <- axi4_lite_read_response(config_rd);
            print_fmt($format("Converter processed %0d pixels", resp), GREEN);
        endaction
    endseq;

    FSM testFSM <- mkFSM(s);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod

endmodule

module [Module] imageTest(TestHandler) 
    provisos(
        NumAlias#(ram_sz, 'd8_000_000),
        NumAlias#(aw, 64),
        NumAlias#(dw, 64),
        NumAlias#(amount, TMul#(InputWidth, InputHeight)), //we use one pixel per word for simplicity
        NumAlias#(amount_bytes, TMul#(amount, TDiv#(dw, 8))),
        NumAlias#(amountw, TLog#(amount_bytes))
    );

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    NumProxy#(17) coeff_width = ?;
    RGB2YCbCr_params#(17) conv_params = RGB2YCbCr_params {
        a : 9798,
        log2_b : 15,
        c : 3736,
        d : 18492,
        e : 23372
    };

    //location where results are written to (directly behind input image)
    UInt#(64) write_addr = fromInteger(valueof(amount)) << 3;

    //AXI drivers
    AXI4_Lite_Master_Rd#(32, 32) config_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) config_wr <- mkAXI4_Lite_Master_Wr(1);
    AXI4_Stream_Wr#(24, 0) axis_tx <- mkAXI4_Stream_Wr(1);
    AXI4_Stream_Rd#(24, 0) axis_rx <- mkAXI4_Stream_Rd(1);

    //DUT
    RGB2YCbCr_ifc#(24) rgb2ycbcr <- mkRGB2YCbCrTop;

    //simulation memory with axi adapter
    SimRAM_AXI4_ifc#(ram_sz, aw, dw, 1, 0) dut <- mkSimRAM_AXI(False);

    //Use generic read master to construct a budget MM2S system
    Axi4MasterRead#(aw, dw, 1, 0, amountw) mem_master_rd <- mkAxi4MasterRead(1, 1, True, 128, True, 1, True, True);
    Axi4MasterWrite#(aw, dw, 1, 0, amountw) mem_master_wr <- mkAxi4MasterWrite(1, 1, True, 256, True, 1, True, 2);

    Reg#(UInt#(32)) rReadCounter <- mkRegU;
    Reg#(UInt#(32)) rWriteCounter <- mkRegU;
    Reg#(UInt#(64)) rRAMPtr <- mkRegU;
    Reg#(UInt#(64)) rImgLoadPtr <- mkRegU;
    Reg#(UInt#(64)) rImgWritePtr <- mkRegU;
    Reg#(Bit#(32)) rAXILRsp <- mkRegU;

    AxiRequest#(aw, amountw) rq_rd = AxiRequest { address: 0, bytesToTransfer: fromInteger(valueof(amount_bytes)), region: 0 };
    AxiRequest#(aw, amountw) rq_wr = AxiRequest { address: pack(write_addr), bytesToTransfer: fromInteger(valueof(amount_bytes)), region: 0 };

    //connect AXI Full masters to memory
    mkConnection(dut.fab_rd, mem_master_rd.fab);
    mkConnection(dut.fab_wr, mem_master_wr.fab);

    mkConnection(config_rd.fab, rgb2ycbcr.fab_config_rd);
    mkConnection(config_wr.fab, rgb2ycbcr.fab_config_wr);
    mkConnection(axis_tx.fab, rgb2ycbcr.fab_data_rd);
    mkConnection(rgb2ycbcr.fab_data_wr, axis_rx.fab);

    rule rmm2s;
        //assume there is a single pixel per data word in memory for simplicity
        let r <- mem_master_rd.server.response.get();
        Bool last = (rReadCounter == fromInteger(valueof(amount) - 1));
        rReadCounter <= rReadCounter + 1;
        RGB_t rgb = unpack(r[23:0]);
        axis_tx.pkg.put(AXI4_Stream_Pkg {
            data: pack(rgb),
            user: ?,
            keep: unpack(-1), //keep all
            dest: ?,
            last: last //last transfer in stream
        });
        // print_fmt($format("MM2S: %0d", rReadCounter), YELLOW);
    endrule

    rule rs2mm;
        let res <- axis_rx.pkg.get();
        YCbCr_t ycbcr = unpack(res.data);
        mem_master_wr.data.put(extend(pack(ycbcr.y)));
        // print_fmt($format("S2MM: %0d", rWriteCounter), YELLOW);
        rWriteCounter <= rWriteCounter + 1;
    endrule

    Stmt load_image_to_ram_interleaved = seq
        action 
            let p <- create_ImageLoader(input_image_path);
            rImgLoadPtr <= p;
        endaction
        write_to_mem_interleaved_ImageLoader(rImgLoadPtr, rRAMPtr, 'h0);
    endseq;

    Stmt ram_to_image_interleaved = seq
        mem_to_file_gray_ImageWriter(rRAMPtr, fromInteger(valueof(InputWidth)), fromInteger(valueof(InputHeight)), output_image_path, write_addr >> 3);
    endseq;

    FSM fsmImageToRAM <- mkFSM(load_image_to_ram_interleaved);
    FSM fsmRAMToImg <- mkFSM(ram_to_image_interleaved);

    Stmt main = seq
        rReadCounter <= 0;
        rWriteCounter <= 0;
        rAXILRsp <= 0;
        print_fmt($format("Starting main FSM"), GREEN);
        rRAMPtr <= dut.ram_instance();

        print_s("Loading image to memory", YELLOW);
        fsmImageToRAM.start();
        await(fsmImageToRAM.done());
        print_s("Finished writing image to RAM", GREEN);

        //configure converter
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_a_offs), pack(extend(conv_params.a)));
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_log2b_offs), pack(extend(conv_params.log2_b)));
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_c_offs), pack(extend(conv_params.c)));
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_d_offs), pack(extend(conv_params.d)));
        axi4_lite_write(config_wr, fromInteger(cfg_coeff_e_offs), pack(extend(conv_params.e)));
        //start
        axi4_lite_write(config_wr, fromInteger(cfg_start_offs), 1);

        //now start the MM2S and S2MM systems
        mem_master_rd.server.request.put(rq_rd);
        mem_master_wr.request.put(rq_wr);

        //wait for completion 
        rAXILRsp <= 0;
        while(!unpack(rAXILRsp[0])) par
            axi4_lite_read(config_rd, fromInteger(cfg_finished_offs));
            action
                let resp <- axi4_lite_read_response(config_rd);
                rAXILRsp <= resp;
            endaction
        endpar
        print_s("Module signaled finished computation", GREEN);

        await(!mem_master_wr.active());
        print_s("Finished copying image", GREEN);

        //read back some stats
        axi4_lite_read(config_rd, fromInteger(cfg_pixel_ctr_offs));
        action
            let resp <- axi4_lite_read_response(config_rd);
            print_fmt($format("Converter processed %0d pixels", resp), GREEN);
        endaction

        fsmRAMToImg.start();
        await(fsmRAMToImg.done());
    endseq;

    FSM testFSM <- mkFSM(main);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod

endmodule

endpackage