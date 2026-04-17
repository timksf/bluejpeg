package TestSimRAM;

import StmtFSM :: *;
import ClientServer :: *;
import GetPut :: *;
import Connectable :: *;
import List :: *;
import Vector :: *;

import BlueAXI :: *;

import TestHelper :: *;
import PrintUtil :: *;
import BDPI :: *;
import SimRAM_AXI :: *;

module mkTestSimRAM(TestHandler);
    let i <- mkPassthroughTest();
    return i;
endmodule

module mkPassthroughTest(TestHandler) 
    provisos(
        NumAlias#(ram_sz, 'd8_000_000),
        NumAlias#(dataw, 64),
        NumAlias#(addrw, 64),
        NumAlias#(amount, 1000), //1000 words
        NumAlias#(amount_bytes, TMul#(amount, 8)), //8 bytes per word
        NumAlias#(amountw, TLog#(amount_bytes)),
        NumAlias#(num_requests, TDiv#(amount_bytes, TDiv#(dataw, 8)))
    );

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    //simulation memory with axi adapter
    SimRAM_AXI4_ifc#(ram_sz, addrw, dataw, 1, 0) dut <- mkSimRAM_AXI(False);
    
    Axi4MasterRead#(addrw, dataw, 1, 0, amountw) mem_master_rd <- mkAxi4MasterRead(8, 8, True, 128, True, 8, True, True);
    Axi4MasterWrite#(addrw, dataw, 1, 0, amountw) mem_master_wr <- mkAxi4MasterWrite(8, 8, True, 256, True, 1, True, 2);

    mkConnection(dut.fab_rd, mem_master_rd.fab);
    mkConnection(dut.fab_wr, mem_master_wr.fab);

    //requests for memory region, pattern-test, so same region for both read and write
    AxiRequest#(addrw, amountw) rq_rd = AxiRequest { address: 0, bytesToTransfer: fromInteger(valueof(amount_bytes)), region: 0 };
    AxiRequest#(addrw, amountw) rq_wr = AxiRequest { address: 0, bytesToTransfer: fromInteger(valueof(amount_bytes)), region: 0 };

    Reg#(UInt#(64)) ram_ptr <- mkRegU;
    Reg#(UInt#(32)) mem_ctr <- mkReg(0);

    Stmt pass_through = seq
        print_fmt($format("Starting main FSM"), GREEN);
        ram_ptr <= dut.ram_instance();

        print_s("Writing pattern to memory", YELLOW);
        mem_master_wr.request.put(rq_wr);
        while(mem_ctr < fromInteger(valueof(num_requests))) par
            mem_master_wr.data.put(pack(extend(mem_ctr)));
            mem_ctr <= mem_ctr + 1;
        endpar
        await(!mem_master_wr.active());
        print_s("Finished writing pattern to RAM", GREEN);
        mem_ctr <= 0;

        //load data from ram model with AXI master and write to different region
        mem_master_rd.server.request.put(rq_rd);
        while(mem_ctr < fromInteger(valueof(num_requests)))
            action
                let resp <- mem_master_rd.server.response.get();
                print_fmt($format("Request [%04d] Result %0d", mem_ctr, resp), YELLOW);
                if(resp != pack(extend(mem_ctr))) begin
                    print_fmt($format("Expected %0x got %0x", mem_ctr, resp), RED);
                    $finish();
                end
                mem_ctr <= mem_ctr + 1;
            endaction
        await(!mem_master_rd.active());
        print_s("Finished reading RAM region", GREEN);

    endseq;

    FSM testFSM <- mkFSM(pass_through);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod

endmodule

endpackage