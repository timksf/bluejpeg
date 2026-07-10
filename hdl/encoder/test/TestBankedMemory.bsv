package TestBankedMemory;

import BRAM :: *;
import DefaultValue :: *;
import StmtFSM :: *;

import BankedMemory :: *;
import PrintUtil :: *;
import TestHelper :: *;

typedef 2 NumBanks;
typedef 3 NumClients;
typedef 4 AddrWidth;
typedef 32 DataWidth;
typedef 4 MaskWidth;
typedef 4 TagWidth;

module [Module] mkTestBankedMemory(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    BRAM_Configure cfg = defaultValue;
    cfg.memorySize = 16;

    BankedMemory_ifc#(
        NumBanks, NumClients, AddrWidth, DataWidth, MaskWidth, TagWidth
    ) dut <- mkBankedMemoryBRAM(cfg, BANK_ARB_ROUND_ROBIN, 4);
    BankedMemory_ifc#(
        1, 1, AddrWidth, DataWidth, MaskWidth, TagWidth
    ) fixedDut <- mkBankedMemoryBRAM(cfg, BANK_ARB_FIXED_PRIORITY, 2);

    function BankedMemoryRequest_t#(
        1, AddrWidth, DataWidth, MaskWidth, TagWidth
    ) writeReq(Bit#(1) bank, Bit#(AddrWidth) address, Bit#(DataWidth) data,
               Bit#(MaskWidth) mask);
        return BankedMemoryRequest_t {
            bank      : bank,
            address   : address,
            data      : data,
            write_mask: mask,
            write     : True,
            tag       : 0
        };
    endfunction

    function BankedMemoryRequest_t#(
        1, AddrWidth, DataWidth, MaskWidth, TagWidth
    ) readReq(Bit#(1) bank, Bit#(AddrWidth) address, Bit#(TagWidth) tag);
        return BankedMemoryRequest_t {
            bank      : bank,
            address   : address,
            data      : 0,
            write_mask: 0,
            write     : False,
            tag       : tag
        };
    endfunction

    function BankedMemoryRequest_t#(
        0, AddrWidth, DataWidth, MaskWidth, TagWidth
    ) singleBankReq(Bit#(AddrWidth) address, Bit#(DataWidth) data,
                    Bool write, Bit#(TagWidth) tag);
        return BankedMemoryRequest_t {
            bank      : 0,
            address   : address,
            data      : data,
            write_mask: '1,
            write     : write,
            tag       : tag
        };
    endfunction

    Stmt testSeq = seq
        par
            dut.request[0].put(writeReq(0, 1, 'h11223344, 'b1111));
            dut.request[1].put(writeReq(1, 1, 'h55667788, 'b1111));
        endpar
        delay(8);

        par
            dut.request[0].put(readReq(0, 1, 1));
            dut.request[1].put(readReq(1, 1, 2));
        endpar
        par
            action
                let rsp <- dut.response[0].get();
                if(rsp.data != 'h11223344 || rsp.tag != 1) begin
                    print_fmt($format("Client 0 got ", fshow(rsp)), RED);
                    $finish();
                end
            endaction
            action
                let rsp <- dut.response[1].get();
                if(rsp.data != 'h55667788 || rsp.tag != 2) begin
                    print_fmt($format("Client 1 got ", fshow(rsp)), RED);
                    $finish();
                end
            endaction
        endpar

        dut.request[2].put(writeReq(0, 1, 'haabbccdd, 'b0101));
        delay(5);
        dut.request[2].put(readReq(0, 1, 3));
        action
            let rsp <- dut.response[2].get();
            if(rsp.data != 'h11bb33dd || rsp.tag != 3) begin
                print_fmt($format("Masked write got ", fshow(rsp)), RED);
                $finish();
            end
        endaction

        par
            dut.request[0].put(writeReq(1, 2, 'h000000a0, 'b1111));
            dut.request[1].put(writeReq(1, 3, 'h000000b1, 'b1111));
            dut.request[2].put(writeReq(1, 4, 'h000000c2, 'b1111));
        endpar
        delay(10);
        par
            dut.request[0].put(readReq(1, 2, 4));
            dut.request[1].put(readReq(1, 3, 5));
            dut.request[2].put(readReq(1, 4, 6));
        endpar
        par
            action
                let rsp <- dut.response[0].get();
                if(rsp.data != 'h000000a0 || rsp.tag != 4) $finish();
            endaction
            action
                let rsp <- dut.response[1].get();
                if(rsp.data != 'h000000b1 || rsp.tag != 5) $finish();
            endaction
            action
                let rsp <- dut.response[2].get();
                if(rsp.data != 'h000000c2 || rsp.tag != 6) $finish();
            endaction
        endpar

        fixedDut.request[0].put(singleBankReq(5, 'hdeadbeef, True, 0));
        delay(4);
        fixedDut.request[0].put(singleBankReq(5, 0, False, 7));
        action
            let rsp <- fixedDut.response[0].get();
            if(rsp.data != 'hdeadbeef || rsp.tag != 7) $finish();
        endaction

        print_s("Finished successfully", GREEN);
    endseq;

    FSM testFsm <- mkFSM(testSeq);

    method Action go();
        testFsm.start();
    endmethod

    method Bool done();
        return testFsm.done();
    endmethod

endmodule

endpackage
