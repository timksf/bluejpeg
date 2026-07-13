package TestBankedMemory;

import BRAM :: *;
import DefaultValue :: *;
import StmtFSM :: *;
import Vector :: *;

import BankedMemory :: *;
import PrintUtil :: *;
import TestHelper :: *;

typedef 6 AddrWidth;
typedef 5 BankAddrWidth;
typedef 32 DataWidth;
typedef 4 MaskWidth;

module [Module] mkTestBankedMemory(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    BRAM_Configure bank_bram_cfg = defaultValue;
    bank_bram_cfg.memorySize = 16;

    BankedMemoryConfig_t bank_cfg = BankedMemoryConfig_t {
        address_base     : 4,
        memory_size      : 32,
        bank_depth       : 16,
        outstanding_reads: 4,
        mapping          : BANK_MAP_INTERLEAVED
    };

    Vector#(2, BankedMemoryPort_ifc#(2, BankAddrWidth, DataWidth, MaskWidth)) i_banks <-
        replicateM(mkBankedMemoryBRAM2PortBE(bank_bram_cfg));
    BankedMemoryAccessor_ifc#(2, AddrWidth, DataWidth, MaskWidth) dut <-
        mkBankedMemoryAccessor(i_banks, bank_cfg);
    BankedAddressMapper_ifc#(2, AddrWidth, BankAddrWidth) i_mapper <-
        mkBankedAddressMapper(bank_cfg);

    BRAM_Configure direct_bram_cfg = defaultValue;
    direct_bram_cfg.memorySize = 16;

    BankedMemoryConfig_t direct_cfg = BankedMemoryConfig_t {
        address_base     : 0,
        memory_size      : 16,
        bank_depth       : 16,
        outstanding_reads: 1,
        mapping          : BANK_MAP_CONTIGUOUS
    };

    BankedMemoryPort_ifc#(2, 4, DataWidth, MaskWidth) i_direct_bank <-
        mkBankedMemoryBRAM2PortBE(direct_bram_cfg);
    Vector#(1, BankedMemoryPort_ifc#(2, 4, DataWidth, MaskWidth)) direct_banks =
        cons(i_direct_bank, nil);
    BankedMemoryAccessor_ifc#(2, 4, DataWidth, MaskWidth) direct_dut <-
        mkBankedMemoryAccessor(direct_banks, direct_cfg);

    BankedMemoryConfig_t contiguous_cfg = BankedMemoryConfig_t {
        address_base     : 3,
        memory_size      : 12,
        bank_depth       : 6,
        outstanding_reads: 2,
        mapping          : BANK_MAP_CONTIGUOUS
    };
    BankedAddressMapper_ifc#(2, 5, 3) i_contiguous_mapper <-
        mkBankedAddressMapper(contiguous_cfg);

    Reg#(UInt#(32)) rg_cycle      <- mkReg(0);
    Reg#(UInt#(32)) rg_read_start <- mkReg(0);

    rule r_count_cycles;
        rg_cycle <= rg_cycle + 1;
    endrule

    function BankedMemoryRequest_t#(addr_w, DataWidth, MaskWidth) write_req(
            Bit#(addr_w) address, Bit#(DataWidth) data, Bit#(MaskWidth) mask
        );
        return BankedMemoryRequest_t {
            address   : address,
            data      : data,
            write_mask: mask,
            write     : True
        };
    endfunction

    function BankedMemoryRequest_t#(addr_w, DataWidth, MaskWidth) read_req(Bit#(addr_w) address);
        return BankedMemoryRequest_t {
            address   : address,
            data      : 0,
            write_mask: 0,
            write     : False
        };
    endfunction

    Stmt test_seq = seq
        action
            let access0 = i_mapper.map_address(4);
            let access1 = i_mapper.map_address(5);
            let access2 = i_mapper.map_address(10);
            if(!i_mapper.in_range(4) || !i_mapper.in_range(35) ||
                    i_mapper.in_range(3) || i_mapper.in_range(36) ||
                    access0.bank != 0 || access0.address != 0 ||
                    access1.bank != 1 || access1.address != 0 ||
                    access2.bank != 0 || access2.address != 3) begin
                print_s("Interleaved address mapping failed", RED);
                $finish();
            end

            let contiguous0 = i_contiguous_mapper.map_address(3);
            let contiguous1 = i_contiguous_mapper.map_address(9);
            let contiguous2 = i_contiguous_mapper.map_address(14);
            if(!i_contiguous_mapper.in_range(3) || !i_contiguous_mapper.in_range(14) ||
                    i_contiguous_mapper.in_range(2) || i_contiguous_mapper.in_range(15) ||
                    contiguous0.bank != 0 || contiguous0.address != 0 ||
                    contiguous1.bank != 1 || contiguous1.address != 0 ||
                    contiguous2.bank != 1 || contiguous2.address != 5) begin
                print_s("Contiguous address mapping failed", RED);
                $finish();
            end
        endaction

        /* Different banks and both physical ports accept requests together. */
        par
            dut.port[0].request(write_req(4, 'h11223344, 'b1111));
            dut.port[1].request(write_req(5, 'h55667788, 'b1111));
        endpar
        par
            dut.port[0].request(read_req(4));
            dut.port[1].request(read_req(5));
        endpar
        par
            action
                let data <- dut.port[0].response();
                if(data != 'h11223344) $finish();
            endaction
            action
                let data <- dut.port[1].response();
                if(data != 'h55667788) $finish();
            endaction
        endpar

        /* A two-port bank also accepts two accesses to the same bank per cycle. */
        par
            dut.port[0].request(write_req(6, 'ha0a0a0a0, 'b1111));
            dut.port[1].request(write_req(8, 'hb1b1b1b1, 'b1111));
        endpar
        par
            dut.port[0].request(read_req(6));
            dut.port[1].request(read_req(8));
        endpar
        par
            action
                let data <- dut.port[0].response();
                if(data != 'ha0a0a0a0) $finish();
            endaction
            action
                let data <- dut.port[1].response();
                if(data != 'hb1b1b1b1) $finish();
            endaction
        endpar

        dut.port[0].request(write_req(4, 'haabbccdd, 'b0101));
        dut.port[0].request(read_req(4));
        action
            let data <- dut.port[0].response();
            if(data != 'h11bb33dd) begin
                print_fmt($format("Masked write got %h", data), RED);
                $finish();
            end
        endaction

        /* One lane may pipeline reads to different banks; responses stay ordered. */
        dut.port[0].request(read_req(4));
        dut.port[0].request(read_req(5));
        action
            let data <- dut.port[0].response();
            if(data != 'h11bb33dd) $finish();
        endaction
        action
            let data <- dut.port[0].response();
            if(data != 'h55667788) $finish();
        endaction

        par
            direct_dut.port[0].request(write_req(1, 'hdeadbeef, 'b1111));
            direct_dut.port[1].request(write_req(2, 'hcafef00d, 'b1111));
        endpar
        action
            rg_read_start <= rg_cycle;
            direct_dut.port[0].request(read_req(1));
        endaction
        action
            let data <- direct_dut.port[0].response();
            if(data != 'hdeadbeef) $finish();
            print_fmt($format("Direct accessor read latency: ", rg_cycle - rg_read_start, " cycles"), BLUE);
            if(rg_cycle - rg_read_start > 2) begin
                print_s("One-bank accessor added read latency", RED);
                $finish();
            end
        endaction
        direct_dut.port[1].request(read_req(2));
        action
            let data <- direct_dut.port[1].response();
            if(data != 'hcafef00d) $finish();
        endaction

        print_s("Finished successfully", GREEN);
    endseq;

    FSM test_fsm <- mkFSM(test_seq);

    method Action go();
        test_fsm.start();
    endmethod

    method Bool done();
        return test_fsm.done();
    endmethod

endmodule

endpackage
