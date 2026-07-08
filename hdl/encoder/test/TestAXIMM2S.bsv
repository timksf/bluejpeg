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

String input_image_path = "../../../assets/sample_192x192.bmp"; //`IM_PATH;
String output_image_path = "../result.png"; //`RES_PATH;

typedef 192 InputWidth;
typedef 192 InputHeight;

function Stmt axil_write_checked(AXI4_Lite_Master_Wr#(32, 32) wr, Bit#(32) addr, Bit#(32) data);
    return seq
        axi4_lite_write(wr, addr, data);
        action
            let rsp <- axi4_lite_write_response(wr);
            if(rsp != OKAY) $fatal();
        endaction
    endseq;
endfunction

module [Module] mkTestAXIMM2S(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t1 <- test;

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

module [Module] test(TestHandler) 
    provisos(
        NumAlias#(ram_sz, 'd8_000_000),
        NumAlias#(aw, 64),
        NumAlias#(dw, 64),
        NumAlias#(amount, TMul#(InputWidth, InputHeight)), //we use one pixel per word for simplicity
        NumAlias#(amount_bytes, TMul#(amount, TDiv#(24, 8))),
        NumAlias#(amountw, TLog#(amount_bytes))
    );

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    //location where results are written to (directly behind input image)
    UInt#(64) write_addr = fromInteger(valueof(amount)) << 3;

    //AXI drivers
    AXI4_Lite_Master_Rd#(32, 32) config_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) config_wr <- mkAXI4_Lite_Master_Wr(1);

    //MM read master has access to 64bit memory, stream with 24 bits to test narrowing
    AXI4_Stream_Rd#(24, 0) axis_rx <- mkAXI4_Stream_Rd(1);

    AXI4_Master_Wr#(64, 64, 0, 0) axi_wr_dummy <- mkAXI4_Master_Wr_Dummy();

    //DUT
    AXIMM2S_ifc#(64, 64, 24) aximm2s <- mkAXIMM2S(128, 1);

    //simulation memory with axi adapter
    SimRAM_AXI4_ifc#(ram_sz, aw, dw, 0, 0) ram <- mkSimRAM_AXI(False);

    //pointers for BDPI functions
    Reg#(UInt#(64)) rRAMPtr <- mkRegU;
    Reg#(UInt#(64)) rImgLoadPtr <- mkRegU;

    //registers for tracking different simulation relevant values
    Reg#(UInt#(64)) rRXCounter <- mkRegU;
    Reg#(Bit#(32)) rAXILRsp <- mkRegU;
    Reg#(Bool) rDUTError <- mkRegU;
    Reg#(Bool) rFinished <- mkRegU;

    //dummy master to avoid simulation errors
    mkConnection(axi_wr_dummy.fab, ram.fab_wr);

    mkConnection(aximm2s.fab_mm_rd, ram.fab_rd);
    mkConnection(aximm2s.fab_s_wr, axis_rx.fab);
    mkConnection(aximm2s.fab_config_rd, config_rd.fab);
    mkConnection(aximm2s.fab_config_wr, config_wr.fab);

    Stmt load_image_to_ram_interleaved = seq
        action 
            let p <- create_ImageLoader(input_image_path);
            rImgLoadPtr <= p;
        endaction
        write_to_mem_interleaved_ImageLoader(rImgLoadPtr, rRAMPtr, 'h0);
    endseq;

    FSM fsmImageToRAM <- mkFSM(load_image_to_ram_interleaved);

    Stmt main = seq
        rAXILRsp <= 0;
        rRXCounter <= 0;
        rFinished <= False;
        rDUTError <= False;
        print_fmt($format("Starting main FSM"), GREEN);
        rRAMPtr <= ram.ram_instance();

        print_s("Loading image to memory", YELLOW);
        fsmImageToRAM.start();
        await(fsmImageToRAM.done());
        print_s("Finished writing image to RAM", GREEN);

        //configure dut
        axil_write_checked(config_wr, fromInteger(cfg_start_addr_lo_offs), 'h00);
        axil_write_checked(config_wr, fromInteger(cfg_start_addr_hi_offs), 'h00);
        axil_write_checked(config_wr, fromInteger(cfg_tx_bytes_lo_offs), fromInteger(valueof(amount_bytes)));
        axil_write_checked(config_wr, fromInteger(cfg_tx_bytes_hi_offs), 'h00);
        //start
        axil_write_checked(config_wr, fromInteger(cfg_cmd_control_offs), 1 << cfg_start_bit_offs);
        
        //receive data from stream and finish if certain bit is set in config registers
        par
            while(!rFinished)
                action
                    let rsp <- axis_rx.pkg.get();
                    Bit#(24) data = rsp.data;
                    //check the received data for correctness, each 24 bit value corresponds to a truncated 64 bit word from memory
                    rRXCounter <= rRXCounter + 1;
                    let ref_v <- read_word_SimRAM(rRAMPtr, rRXCounter);
                    if(data != pack(truncate(ref_v))) begin
                        print_fmt($format("Received %0x but expected %0x at word %0x", data, ref_v, rRXCounter), RED);
                        $finish();
                    end 
                    // else print_fmt($format("Received %0x at word %0d", data, rRXCounter), BLUE);
                    if(rsp.last)
                        print_s("Received last packet from stream", GREEN);
                endaction
            seq
                //wait for completion
                rAXILRsp <= 0;
                while(!unpack(rAXILRsp[fromInteger(cfg_finish_bit_offs)]) && !rDUTError) par
                    axi4_lite_read(config_rd, fromInteger(cfg_cmd_control_offs));
                    action
                        let rsp <- config_rd.response.get();
                        if(rsp.resp == OKAY)
                            rAXILRsp <= rsp.data;
                        else begin
                            print_s("Could not read CMD register!", RED);
                            $fatal();
                        end
                        //detect errors signaled by the DUT
                        if(unpack(rsp.data[fromInteger(cfg_error_bit_offs)])) begin
                            print_s("DUT signaled error state", RED);
                            rDUTError <= True;
                        end
                    endaction
                endpar
                if(rDUTError) seq
                    axi4_lite_read(config_rd, fromInteger(cfg_cmd_cause_offs));
                    action
                        let rsp <- config_rd.response.get();
                        AXIMM2S_Error_Cause c = unpack(truncate(rsp.data));
                        print_fmt($format("DUT error: ") + fshow(c), RED);
                    endaction
                    $fatal();
                endseq else
                    print_s("DUT signaled finished computation", GREEN);
                rFinished <= True;
            endseq
        endpar
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
