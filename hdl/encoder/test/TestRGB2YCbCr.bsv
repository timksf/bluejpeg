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

String input_image_path  = "../../../assets/sample_1920x1280.bmp"; //`IM_PATH;
String output_image_path = "../result.png";                        //`RES_PATH;

typedef 1920 InputWidth;
typedef 1280 InputHeight;

function Stmt axil_write_checked(AXI4_Lite_Master_Wr#(aw, dw) master, Bit#(aw) addr, Bit#(dw) data);
    return seq
        axi4_lite_write(master, addr, data);
        action
            let resp <- axi4_lite_write_response(master);
            if(resp != OKAY) $finish(1);
        endaction
    endseq;
endfunction


module [Module] mkTestRGB2YCbCr(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t1 <- mkImageTest;

    Stmt s = seq
        t1.go();
        while(!t1.done()) action endaction
    endseq;

    FSM i_test_fsm <- mkFSM(s);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

module [Module] mkSimpleTest(TestHandler_ifc);
    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    NumProxy_t#(17) coeff_width = ?;
    RGB2YCbCrParams_t#(17) conv_params = RGB2YCbCrParams_t {
        a : 9798,
        log2_b : 15,
        c : 3736,
        d : 18492,
        e : 23372
    };

    //AXI drivers
    AXI4_Lite_Master_Rd#(32, 32) i_config_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_config_wr <- mkAXI4_Lite_Master_Wr(1);
    AXI4_Stream_Wr#(24, 0)       i_axis_tx   <- mkAXI4_Stream_Wr(1);
    AXI4_Stream_Rd#(24, 0)       i_axis_rx   <- mkAXI4_Stream_Rd(1);

    //DUT
    RGB2YCbCr_ifc#(24) i_rgb2ycbcr <- mkRGB2YCbCrTop;

    mkConnection(i_config_rd.fab, i_rgb2ycbcr.fab_config_rd);
    mkConnection(i_config_wr.fab, i_rgb2ycbcr.fab_config_wr);
    mkConnection(i_axis_tx.fab, i_rgb2ycbcr.fab_data_rd);
    mkConnection(i_rgb2ycbcr.fab_data_wr, i_axis_rx.fab);

    Reg#(Bit#(32)) rg_axil_rsp <- mkRegU;
    // RGB2YCbCrConv_ifc conv <- mkRGB2YCbCrConverter(coeff_width, conv_params);

    Stmt s = seq
        print_mod_pre_color_t_s("Start", GREEN);
        //configure coefficients
        axil_write_checked(i_config_wr, 'h0C, pack(extend(conv_params.a)));
        axil_write_checked(i_config_wr, 'h10, pack(extend(conv_params.log2_b)));
        axil_write_checked(i_config_wr, 'h14, pack(extend(conv_params.c)));
        axil_write_checked(i_config_wr, 'h18, pack(extend(conv_params.d)));
        axil_write_checked(i_config_wr, 'h1C, pack(extend(conv_params.e)));
        axil_write_checked(i_config_wr, 'h24, 1);
        //start
        axil_write_checked(i_config_wr, 'h00, 1);
        //dispatch data
        action
            RGB_t rgb = RGB_t { r : 24, g : 12, b : 77 };
            i_axis_tx.pkg.put(AXI4_Stream_Pkg {
                data: pack(rgb),
                user: ?,
                keep: unpack(-1), //keep all
                dest: ?,
                id: 0,
                last: True //last transfer in stream
            });
        endaction
        //wait for result
        action
            let res <- i_axis_rx.pkg.get();
            YCbCr_t  ycbcr   = unpack(res.data);
            Bit#(32) ref_raw = rgb2ycbcr_ref(24, 12, 77);
            YCbCr_t ref_res = YCbCr_t {
                y:  unpack(truncate((ref_raw & 'hFF0000) >> 16)),
                cb: unpack(truncate((ref_raw & 'hFF00) >> 8)),
                cr: unpack(truncate(ref_raw & 'hFF))
            };
            print_fmt($format("Result: ") + fshow(ycbcr) + $format(" Ref: ") + fshow(ref_res), GREEN);
        endaction
        rg_axil_rsp <= 0;
        while(!unpack(rg_axil_rsp[0])) par
            axi4_lite_read(i_config_rd, 'h04);
            action
                let resp <- axi4_lite_read_response(i_config_rd);
                rg_axil_rsp <= resp;
            endaction
        endpar
        print_s("Module signaled finished computation", GREEN);
        action
            if(!i_rgb2ycbcr.irq) begin
                $display("ERROR: Completion IRQ was not asserted");
                $finish(1);
            end
        endaction
        axil_write_checked(i_config_wr, 'h20, 1);
        action
            if(i_rgb2ycbcr.irq) begin
                $display("ERROR: Completion IRQ did not clear");
                $finish(1);
            end
        endaction
        //read back some stats
        axi4_lite_read(i_config_rd, 'h08);
        action
            let resp <- axi4_lite_read_response(i_config_rd);
            print_fmt($format("Converter processed %0d pixels", resp), GREEN);
        endaction
    endseq;

    FSM i_test_fsm <- mkFSM(s);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

module [Module] mkImageTest(TestHandler_ifc)
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

    NumProxy_t#(17) coeff_width = ?;
    RGB2YCbCrParams_t#(17) conv_params = RGB2YCbCrParams_t {
        a : 9798,
        log2_b : 15,
        c : 3736,
        d : 18492,
        e : 23372
    };

    //location where results are written to (directly behind input image)
    UInt#(64) write_addr = fromInteger(valueof(amount)) << 3;

    //AXI drivers
    AXI4_Lite_Master_Rd#(32, 32) i_config_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_config_wr <- mkAXI4_Lite_Master_Wr(1);
    AXI4_Stream_Wr#(24, 0)       i_axis_tx   <- mkAXI4_Stream_Wr(1);
    AXI4_Stream_Rd#(24, 0)       i_axis_rx   <- mkAXI4_Stream_Rd(1);

    //DUT
    RGB2YCbCr_ifc#(24) i_rgb2ycbcr <- mkRGB2YCbCrTop;

    //simulation memory with axi adapter
    SimRAM_AXI4_ifc#(ram_sz, aw, dw, 1, 0) dut <- mkSimRAM_AXI(False);

    //use generic read master to construct a budget MM2S system
    Axi4MasterRead#(aw, dw, 1, 0, amountw)  i_mem_master_rd <- mkAxi4MasterRead(1, 1, True, 128, True, 1, True, True);
    Axi4MasterWrite#(aw, dw, 1, 0, amountw) i_mem_master_wr <- mkAxi4MasterWrite(1, 1, True, 256, True, 1, True, 2);

    Reg#(UInt#(32)) rg_read_counter  <- mkRegU;
    Reg#(UInt#(32)) rg_write_counter <- mkRegU;
    Reg#(UInt#(64)) rg_ram_ptr       <- mkRegU;
    Reg#(UInt#(64)) rg_img_load_ptr  <- mkRegU;
    Reg#(UInt#(64)) rg_img_write_ptr <- mkRegU;
    Reg#(Bit#(32))  rg_axil_rsp      <- mkRegU;

    AxiRequest#(aw, amountw) rq_rd = AxiRequest { address: 0, bytesToTransfer: fromInteger(valueof(amount_bytes)), region: 0 };
    AxiRequest#(aw, amountw) rq_wr = AxiRequest { address: pack(write_addr), bytesToTransfer: fromInteger(valueof(amount_bytes)), region: 0 };

    //connect AXI Full masters to memory
    mkConnection(dut.fab_rd, i_mem_master_rd.fab);
    mkConnection(dut.fab_wr, i_mem_master_wr.fab);

    mkConnection(i_config_rd.fab, i_rgb2ycbcr.fab_config_rd);
    mkConnection(i_config_wr.fab, i_rgb2ycbcr.fab_config_wr);
    mkConnection(i_axis_tx.fab, i_rgb2ycbcr.fab_data_rd);
    mkConnection(i_rgb2ycbcr.fab_data_wr, i_axis_rx.fab);

    rule r_mm2s;
        //assume there is a single pixel per data word in memory for simplicity
        let r <- i_mem_master_rd.server.response.get();
        Bool last = (rg_read_counter == fromInteger(valueof(amount) - 1));
        rg_read_counter <= rg_read_counter + 1;
        RGB_t rgb = unpack(r[23:0]);
        i_axis_tx.pkg.put(AXI4_Stream_Pkg {
            data: pack(rgb),
            user: ?,
            keep: unpack(-1), //keep all
            dest: ?,
            id: 0,
            last: last //last transfer in stream
        });
        // print_fmt($format("MM2S: %0d", rg_read_counter), YELLOW);
    endrule

    rule r_s2mm;
        let res <- i_axis_rx.pkg.get();
        YCbCr_t ycbcr = unpack(res.data);
        i_mem_master_wr.data.put(extend(pack(ycbcr.y)));
        // print_fmt($format("S2MM: %0d", rg_write_counter), YELLOW);
        rg_write_counter <= rg_write_counter + 1;
    endrule

    Stmt load_image_to_ram_interleaved = seq
        action
            let p <- create_ImageLoader(input_image_path);
            rg_img_load_ptr <= p;
        endaction
        write_to_mem_interleaved_ImageLoader(rg_img_load_ptr, rg_ram_ptr, 'h0);
    endseq;

    Stmt ram_to_image_interleaved = seq
        mem_to_file_gray_ImageWriter(rg_ram_ptr, fromInteger(valueof(InputWidth)), fromInteger(valueof(InputHeight)), output_image_path, write_addr >> 3);
    endseq;

    FSM i_fsm_image_to_ram <- mkFSM(load_image_to_ram_interleaved);
    FSM i_fsm_ram_to_img   <- mkFSM(ram_to_image_interleaved);

    Stmt main = seq
        rg_read_counter <= 0;
        rg_write_counter <= 0;
        rg_axil_rsp <= 0;
        print_fmt($format("Starting main FSM"), GREEN);
        rg_ram_ptr <= dut.ram_instance();

        print_s("Loading image to memory", YELLOW);
        i_fsm_image_to_ram.start();
        await(i_fsm_image_to_ram.done());
        print_s("Finished writing image to RAM", GREEN);

        //configure converter
        axil_write_checked(i_config_wr, 'h0C, pack(extend(conv_params.a)));
        axil_write_checked(i_config_wr, 'h10, pack(extend(conv_params.log2_b)));
        axil_write_checked(i_config_wr, 'h14, pack(extend(conv_params.c)));
        axil_write_checked(i_config_wr, 'h18, pack(extend(conv_params.d)));
        axil_write_checked(i_config_wr, 'h1C, pack(extend(conv_params.e)));
        axil_write_checked(i_config_wr, 'h24, 1);
        //start
        axil_write_checked(i_config_wr, 'h00, 1);

        //now start the MM2S and S2MM systems
        i_mem_master_rd.server.request.put(rq_rd);
        i_mem_master_wr.request.put(rq_wr);

        //wait for completion
        rg_axil_rsp <= 0;
        while(!unpack(rg_axil_rsp[0])) par
            axi4_lite_read(i_config_rd, 'h04);
            action
                let resp <- axi4_lite_read_response(i_config_rd);
                rg_axil_rsp <= resp;
            endaction
        endpar
        print_s("Module signaled finished computation", GREEN);
        action
            if(!i_rgb2ycbcr.irq) begin
                $display("ERROR: Completion IRQ was not asserted");
                $finish(1);
            end
        endaction
        axil_write_checked(i_config_wr, 'h20, 1);
        action
            if(i_rgb2ycbcr.irq) begin
                $display("ERROR: Completion IRQ did not clear");
                $finish(1);
            end
        endaction

        await(!i_mem_master_wr.active());
        print_s("Finished copying image", GREEN);

        //read back some stats
        axi4_lite_read(i_config_rd, 'h08);
        action
            let resp <- axi4_lite_read_response(i_config_rd);
            print_fmt($format("Converter processed %0d pixels", resp), GREEN);
        endaction

        i_fsm_ram_to_img.start();
        await(i_fsm_ram_to_img.done());
    endseq;

    FSM i_test_fsm <- mkFSM(main);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

endpackage
