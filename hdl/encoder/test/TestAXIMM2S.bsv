package TestAXIMM2S;
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
import TestHelper :: *;
import SimRAM_AXI :: *;
import AXIMM2S :: *;

String input_image_path  = "../../../assets/sample_192x192.bmp"; //`IM_PATH;
String output_image_path = "../result.png";                      //`RES_PATH;

typedef 192 InputWidth;
typedef 192 InputHeight;

module [Module] mkTestAXIMM2S(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t1 <- mkTestCase;

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

module [Module] mkTestCase(TestHandler_ifc)
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

    //location where results are written to (directly behind input image)
    UInt#(64) write_addr = fromInteger(valueof(amount)) << 3;

    //AXI drivers
    AXI4_Lite_Master_Rd#(32, 32) i_config_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_config_wr <- mkAXI4_Lite_Master_Wr(1);

    //MM read master has access to 64bit memory, stream with 24 bits to test narrowing
    AXI4_Stream_Rd#(24, 0) i_axis_rx <- mkAXI4_Stream_Rd(1);

    AXI4_Master_Wr#(64, 64, 0, 0) i_axi_wr_dummy <- mkAXI4_Master_Wr_Dummy();

    //DUT
    AXIMM2S_ifc#(64, 64, 24) i_aximm2s <- mkAXIMM2S(128, 1);

    //simulation memory with axi adapter
    SimRAM_AXI4_ifc#(ram_sz, aw, dw, 0, 0) i_ram <- mkSimRAM_AXI(False);

    //pointers for BDPI functions
    Reg#(UInt#(64)) rg_ram_ptr      <- mkRegU;
    Reg#(UInt#(64)) rg_img_load_ptr <- mkRegU;

    //registers for tracking different simulation relevant values
    Reg#(UInt#(64)) rg_rx_counter <- mkRegU;
    Reg#(Bit#(32))  rg_axil_rsp   <- mkRegU;
    Reg#(Bool)      rg_dut_error  <- mkRegU;
    Reg#(Bool)      rg_finished   <- mkRegU;

    //dummy master to avoid simulation errors
    mkConnection(i_axi_wr_dummy.fab, i_ram.fab_wr);

    mkConnection(i_aximm2s.fab_mm_rd, i_ram.fab_rd);
    mkConnection(i_aximm2s.fab_s_wr, i_axis_rx.fab);
    mkConnection(i_aximm2s.fab_config_rd, i_config_rd.fab);
    mkConnection(i_aximm2s.fab_config_wr, i_config_wr.fab);

    Stmt load_image_to_ram_interleaved = seq
        action
            let p <- create_ImageLoader(input_image_path);
            rg_img_load_ptr <= p;
        endaction
        write_to_mem_interleaved_ImageLoader(rg_img_load_ptr, rg_ram_ptr, 'h0);
    endseq;

    FSM i_fsm_image_to_ram <- mkFSM(load_image_to_ram_interleaved);

    Stmt main = seq
        rg_axil_rsp <= 0;
        rg_rx_counter <= 0;
        rg_finished <= False;
        rg_dut_error <= False;
        print_fmt($format("Starting main FSM"), GREEN);
        rg_ram_ptr <= i_ram.ram_instance();

        print_s("Loading image to memory", YELLOW);
        i_fsm_image_to_ram.start();
        await(i_fsm_image_to_ram.done());
        print_s("Finished writing image to RAM", GREEN);

        //configure dut
        axi4_lite_write(i_config_wr, fromInteger(cfg_start_addr_lo_offs), 'h00);
        axi4_lite_write(i_config_wr, fromInteger(cfg_start_addr_hi_offs), 'h00);
        axi4_lite_write(i_config_wr, fromInteger(cfg_tx_bytes_lo_offs), fromInteger(valueof(amount_bytes)));
        axi4_lite_write(i_config_wr, fromInteger(cfg_tx_bytes_hi_offs), 'h00);
        //start
        axi4_lite_read(i_config_rd, fromInteger(cfg_cmd_control_offs));
        action
            let rsp <- axi4_lite_read_response(i_config_rd);
            rg_axil_rsp <= rsp;
        endaction
        action
            let ctrl = rg_axil_rsp;
            ctrl[cfg_start_bit_offs] = 1'b1;
            axi4_lite_write(i_config_wr, fromInteger(cfg_cmd_control_offs), ctrl);
        endaction

        //receive data from stream and finish if certain bit is set in config registers
        par
            while(!rg_finished)
                action
                    let      rsp  <- i_axis_rx.pkg.get();
                    Bit#(24) data = rsp.data;
                    //check the received data for correctness, each 24 bit value corresponds to a truncated 64 bit word from memory
                    rg_rx_counter <= rg_rx_counter + 1;
                    let ref_v <- read_word_SimRAM(rg_ram_ptr, rg_rx_counter);
                    if(data != pack(truncate(ref_v))) begin
                        print_fmt($format("Received %0x but expected %0x at word %0x", data, ref_v, rg_rx_counter), RED);
                        $finish();
                    end
                    // else print_fmt($format("Received %0x at word %0d", data, rg_rx_counter), BLUE);
                    if(rsp.last)
                        print_s("Received last packet from stream", GREEN);
                endaction
            seq
                //wait for completion
                rg_axil_rsp <= 0;
                while(!unpack(rg_axil_rsp[fromInteger(cfg_finish_bit_offs)]) && !rg_dut_error) par
                    axi4_lite_read(i_config_rd, fromInteger(cfg_cmd_control_offs));
                    action
                        let rsp <- i_config_rd.response.get();
                        if(rsp.resp == OKAY)
                            rg_axil_rsp <= rsp.data;
                        else begin
                            print_s("Could not read CMD register!", RED);
                            $fatal();
                        end
                        //detect errors signaled by the DUT
                        if(unpack(rsp.data[fromInteger(cfg_error_bit_offs)])) begin
                            print_s("DUT signaled error state", RED);
                            rg_dut_error <= True;
                        end
                    endaction
                endpar
                if(rg_dut_error) seq
                    axi4_lite_read(i_config_rd, fromInteger(cfg_cmd_cause_offs));
                    action
                        let               rsp <- i_config_rd.response.get();
                        AXIMM2SErrorCause c   = unpack(truncate(rsp.data));
                        print_fmt($format("DUT error: ") + fshow(c), RED);
                    endaction
                    $fatal();
                endseq else
                    print_s("DUT signaled finished computation", GREEN);
                rg_finished <= True;
            endseq
        endpar
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