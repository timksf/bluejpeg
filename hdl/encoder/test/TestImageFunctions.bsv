package TestImageFunctions;

import StmtFSM :: *;
import ClientServer :: *;
import GetPut :: *;
import Connectable :: *;
import List :: *;
import Vector :: *;
import BlueAXI :: *;

import BDPI :: *;
import TestHelper :: *;
import PrintUtil :: *;
import SimRAM_AXI :: *;

String input_image_path  = "../../../assets/sample_1920x1280.bmp"; //`IM_PATH;
String output_image_path = "../result.png";                        //`RES_PATH;

typedef 1920 InputWidth;
typedef 1280 InputHeight;

module mkTestImageFunctions(TestHandler_ifc);
    let i_i <- mkImageCopyTest();
    return i_i;
endmodule

//copies image from one part of the simulation memory to another with AXI transfers
module mkImageCopyTest(TestHandler_ifc)
    provisos(
        NumAlias#(ram_sz, 'd8_000_000),
        NumAlias#(dataw, 64),
        NumAlias#(addrw, 64),
        NumAlias#(amount, TMul#(InputWidth, InputHeight)), //we expect one pixel per word for simplicity
        NumAlias#(amount_bytes, TMul#(amount, 8)), //8 bytes per word
        NumAlias#(amountw, TLog#(amount_bytes)),
        NumAlias#(num_requests, TDiv#(amount_bytes, TDiv#(dataw, 8)))
    );

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    //location where the data is copied to
    UInt#(64) write_addr = fromInteger(valueof(amount)) << 3;

    //simulation memory with axi adapter
    SimRAM_AXI4_ifc#(ram_sz, addrw, dataw, 1, 0) dut <- mkSimRAM_AXI(False);

    Axi4MasterRead#(addrw, dataw, 1, 0, amountw)  i_mem_master_rd <- mkAxi4MasterRead(8, 8, True, 128, True, 8, True, True);
    Axi4MasterWrite#(addrw, dataw, 1, 0, amountw) i_mem_master_wr <- mkAxi4MasterWrite(8, 8, True, 256, True, 1, True, 2);

    mkConnection(dut.fab_rd, i_mem_master_rd.fab);
    mkConnection(dut.fab_wr, i_mem_master_wr.fab);

    //requests for memory region, pattern-test, so same region for both read and write
    AxiRequest#(addrw, amountw) rq_rd = AxiRequest { address: 0, bytesToTransfer: fromInteger(valueof(amount_bytes)), region: 0 };
    AxiRequest#(addrw, amountw) rq_wr = AxiRequest { address: pack(write_addr), bytesToTransfer: fromInteger(valueof(amount_bytes)), region: 0 };

    Reg#(UInt#(64)) rg_ram_ptr          <- mkRegU;
    Reg#(UInt#(64)) rg_image_loader_ptr <- mkRegU;
    Reg#(UInt#(64)) rg_image_writer_ptr <- mkRegU;
    Reg#(UInt#(32)) rg_read_cnt         <- mkReg(0);

    //FSMs for loading and storing images with the simulated memory
    Stmt load_image_to_ram_interleaved = seq
        action
            let p <- create_ImageLoader(input_image_path);
            rg_image_loader_ptr <= p;
        endaction
        write_to_mem_interleaved_ImageLoader(rg_image_loader_ptr, rg_ram_ptr, 'h0);
    endseq;

    Stmt ram_to_image_interleaved = seq
        mem_to_file_interleaved_ImageWriter(rg_ram_ptr, fromInteger(valueof(InputWidth)), fromInteger(valueof(InputHeight)), output_image_path, write_addr >> 3);
    endseq;

    FSM i_image_to_ram_fsm <- mkFSM(load_image_to_ram_interleaved);
    FSM i_ram_to_image_fsm <- mkFSM(ram_to_image_interleaved);

    Stmt pass_through = seq
        print_fmt($format("Starting main FSM"), GREEN);
        rg_ram_ptr <= dut.ram_instance();

        print_s("Loading image to memory", YELLOW);
        i_image_to_ram_fsm.start();
        await(i_image_to_ram_fsm.done());
        print_s("Finished writing image to RAM", GREEN);

        print_s("Copying image data to different location in RAM", YELLOW);
        i_mem_master_rd.server.request.put(rq_rd);
        i_mem_master_wr.request.put(rq_wr);
        await(i_mem_master_rd.active());
        await(!i_mem_master_rd.active());
        await(!i_mem_master_wr.active());
        print_s("Finished copying image", GREEN);
        print_fmt($format("Forwarded %0d packets of width %0d totaling %0d bytes", rg_read_cnt, valueof(dataw), (rg_read_cnt*fromInteger(valueof(dataw))) >> 3), YELLOW);

        i_ram_to_image_fsm.start();
        await(i_ram_to_image_fsm.done());
    endseq;

    FSM i_test_fsm <- mkFSM(pass_through);

    rule r_fwd_rd_to_wr;
        let r <- i_mem_master_rd.server.response.get();
        i_mem_master_wr.data.put(r);
        rg_read_cnt <= rg_read_cnt + 1;
    endrule

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

endpackage