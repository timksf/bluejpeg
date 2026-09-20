package TestBankedMemory;

import BRAM :: *;
import DefaultValue :: *;
import RegFile :: *;
import StmtFSM :: *;
import Vector :: *;

import BankedMemory :: *;
import PrintUtil :: *;
import TestHelper :: *;

typedef 6 AddrWidth;
typedef 5 BankAddrWidth;
typedef 5 SharedAddrWidth;
typedef 3 SharedBankAddrWidth;
typedef 32 DataWidth;
typedef 4 MaskWidth;

module mkTestMemory2(BankedMemoryPort_ifc#(1, 2, 2, DataWidth, 1));

    RegFile#(Bit#(2), Bit#(DataWidth)) i_memory <- mkRegFileFull;
    Reg#(Bit#(2)) rg_read_address <- mkRegU;

    function BankedMemoryPhysicalRWPort_ifc#(2, DataWidth, 1) make_port(
            Integer port_index
        );
        return interface BankedMemoryPhysicalRWPort_ifc;
            method request_ready = True;

            method ActionValue#(Maybe#(Bit#(DataWidth))) request(
                    BankedMemoryRequest_t#(2, DataWidth, 1) req
                );
                if(req.write)
                    i_memory.upd(req.address, req.data);
                else
                    rg_read_address <= req.address;
                return tagged Invalid;
            endmethod

            method ActionValue#(Bit#(DataWidth)) response();
                return i_memory.sub(rg_read_address);
            endmethod
        endinterface;
    endfunction

    interface port = genWith(make_port);

endmodule

module mkTestBankedMemoryStructural(Empty);

    BRAM_Configure cfg_bram = defaultValue;
    cfg_bram.memorySize = 4;

    BankedMemoryConfig_t direct_cfg = BankedMemoryConfig_t {
        address_base: 0,
        memory_size : 4,
        bank_depth  : 4,
        mapping     : BANK_MAP_CONTIGUOUS
    };

    BankedMemoryConfig_t ping_cfg = BankedMemoryConfig_t {
        address_base: 0,
        memory_size : 8,
        bank_depth  : 4,
        mapping     : BANK_MAP_CONTIGUOUS
    };

    BankedMemoryPort_ifc#(2, 1, 2, DataWidth, MaskWidth) i_wide_bank <-
        mkBankedMemoryBRAM2PortBE(cfg_bram);
    Vector#(1, BankedMemoryPort_ifc#(2, 1, 2, DataWidth, MaskWidth)) wide_banks =
        cons(i_wide_bank, nil);
    BankedMemoryAccessor_ifc#(1, 3, DataWidth, MaskWidth) i_c_lt_p <-
        mkBankedMemoryAccessor(wide_banks, direct_cfg);

    Vector#(2, BankedMemoryPort_ifc#(1, 0, 2, DataWidth, MaskWidth)) ping_banks <-
        replicateM(mkBankedMemoryLUTRAM1PortBE);
    BankedMemoryAccessor_ifc#(2, 3, DataWidth, MaskWidth) i_ping_pong <-
        mkBankedMemoryAccessor(ping_banks, ping_cfg);

endmodule

module [Module] mkTestBankedMemory(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    BRAM_Configure bank_bram_cfg = defaultValue;
    bank_bram_cfg.memorySize = 16;

    BankedMemoryConfig_t bank_cfg = BankedMemoryConfig_t {
        address_base     : 4,
        memory_size      : 32,
        bank_depth       : 16,
        mapping          : BANK_MAP_INTERLEAVED
    };

    Vector#(2, BankedMemoryPort_ifc#(2, 1, BankAddrWidth, DataWidth, MaskWidth)) i_banks <-
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
        mapping          : BANK_MAP_CONTIGUOUS
    };

    BankedMemoryPort_ifc#(2, 1, 4, DataWidth, MaskWidth) i_direct_bank <-
        mkBankedMemoryBRAM2PortBE(direct_bram_cfg);
    Vector#(1, BankedMemoryPort_ifc#(2, 1, 4, DataWidth, MaskWidth)) direct_banks =
        cons(i_direct_bank, nil);
    BankedMemoryAccessor_ifc#(2, 4, DataWidth, MaskWidth) direct_dut <-
        mkBankedMemoryAccessor(direct_banks, direct_cfg);

    BankedMemoryConfig_t contiguous_cfg = BankedMemoryConfig_t {
        address_base     : 3,
        memory_size      : 12,
        bank_depth       : 6,
        mapping          : BANK_MAP_CONTIGUOUS
    };
    BankedAddressMapper_ifc#(2, 5, 3) i_contiguous_mapper <-
        mkBankedAddressMapper(contiguous_cfg);

    BRAM_Configure shared_bram_cfg = defaultValue;
    shared_bram_cfg.memorySize = 8;

    BankedMemoryConfig_t shared_cfg = BankedMemoryConfig_t {
        address_base     : 0,
        memory_size      : 32,
        bank_depth       : 8,
        mapping          : BANK_MAP_INTERLEAVED
    };

    Vector#(4, BankedMemoryPort_ifc#(
        1, 1, SharedBankAddrWidth, DataWidth, MaskWidth)) i_shared_banks <-
        replicateM(mkBankedMemoryBRAM1PortBE(shared_bram_cfg));
    BankedMemoryAccessor_ifc#(3, SharedAddrWidth, DataWidth, MaskWidth) shared_dut <-
        mkBankedMemoryAccessor(i_shared_banks, shared_cfg);

    Vector#(4, BankedMemoryPort_ifc#(
        2, 1, SharedBankAddrWidth, DataWidth, MaskWidth)) i_shared_dual_banks <-
        replicateM(mkBankedMemoryBRAM2PortBE(shared_bram_cfg));
    BankedMemoryAccessor_ifc#(3, SharedAddrWidth, DataWidth, MaskWidth) shared_dual_dut <-
        mkBankedMemoryAccessor(i_shared_dual_banks, shared_cfg);

    BankedMemoryConfig_t comb_cfg = BankedMemoryConfig_t {
        address_base: 0,
        memory_size : 12,
        bank_depth  : 4,
        mapping     : BANK_MAP_INTERLEAVED
    };

    Vector#(3, BankedMemoryPort_ifc#(1, 0, 2, DataWidth, MaskWidth)) i_comb_banks <-
        replicateM(mkBankedMemoryLUTRAM1PortBE);
    BankedMemoryAccessor_ifc#(4, 4, DataWidth, MaskWidth) comb_dut <-
        mkBankedMemoryAccessor(i_comb_banks, comb_cfg);

    BankedMemoryConfig_t scalar_cfg = BankedMemoryConfig_t {
        address_base: 0,
        memory_size : 4,
        bank_depth  : 4,
        mapping     : BANK_MAP_CONTIGUOUS
    };

    BankedMemoryPort_ifc#(1, 0, 2, DataWidth, MaskWidth) i_scalar_bank <-
        mkBankedMemoryLUTRAM1PortBE;
    Vector#(1, BankedMemoryPort_ifc#(1, 0, 2, DataWidth, MaskWidth)) scalar_banks =
        cons(i_scalar_bank, nil);
    BankedMemoryAccessor_ifc#(1, 2, DataWidth, MaskWidth) scalar_dut <-
        mkBankedMemoryAccessor(scalar_banks, scalar_cfg);

    BankedMemoryConfig_t ping_cfg = BankedMemoryConfig_t {
        address_base: 0,
        memory_size : 8,
        bank_depth  : 4,
        mapping     : BANK_MAP_CONTIGUOUS
    };

    Vector#(2, BankedMemoryPort_ifc#(1, 0, 2, DataWidth, MaskWidth)) i_ping_banks <-
        replicateM(mkBankedMemoryLUTRAM1PortBE);
    BankedMemoryAccessor_ifc#(2, 3, DataWidth, MaskWidth) ping_dut <-
        mkBankedMemoryAccessor(i_ping_banks, ping_cfg);

    BankedMemoryPort_ifc#(1, 2, 2, DataWidth, 1) i_latency_2_bank <-
        mkTestMemory2;
    Vector#(1, BankedMemoryPort_ifc#(1, 2, 2, DataWidth, 1)) latency_2_banks =
        cons(i_latency_2_bank, nil);
    BankedMemoryAccessor_ifc#(1, 2, DataWidth, 1) latency_2_dut <-
        mkBankedMemoryAccessor(latency_2_banks, scalar_cfg);

    Reg#(UInt#(32)) rg_cycle      <- mkReg(0);
    Reg#(UInt#(32)) rg_read_start <- mkReg(0);

    Reg#(Bool)                  rg_fairness_active  <- mkReg(False);
    Vector#(3, Reg#(UInt#(8))) rg_fairness_accepts <- replicateM(mkReg(0));

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

    rule r_count_cycles;
        rg_cycle <= rg_cycle + 1;
    endrule

    for(Integer client = 0; client < 3; client = client + 1) begin
        rule r_drive_fairness (rg_fairness_active);
            shared_dut.port[client].request(write_req(
                fromInteger(client * 4), fromInteger(client), '1));
            rg_fairness_accepts[client] <= rg_fairness_accepts[client] + 1;
        endrule
    end

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

        /* A second read may occupy the request skid until the first is consumed. */
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

        /* Three logical ports, fewer than four banks, may still select one bank together. */
        par
            shared_dut.port[0].request(write_req(0, 'h01010101, 'b1111));
            shared_dut.port[1].request(write_req(4, 'h12121212, 'b1111));
            shared_dut.port[2].request(write_req(8, 'h23232323, 'b1111));
        endpar
        par
            shared_dut.port[0].request(read_req(0));
            shared_dut.port[1].request(read_req(4));
            shared_dut.port[2].request(read_req(8));
        endpar
        par
            action
                let data <- shared_dut.port[0].response();
                if(data != 'h01010101) $finish();
            endaction
            action
                let data <- shared_dut.port[1].response();
                if(data != 'h12121212) $finish();
            endaction
            action
                let data <- shared_dut.port[2].response();
                if(data != 'h23232323) $finish();
            endaction
        endpar

        /* C=P+1 clients share the two physical ports of one dual-port bank. */
        par
            shared_dual_dut.port[0].request(write_req(0, 'h30303030, 'b1111));
            shared_dual_dut.port[1].request(write_req(4, 'h41414141, 'b1111));
            shared_dual_dut.port[2].request(write_req(8, 'h52525252, 'b1111));
        endpar
        par
            shared_dual_dut.port[0].request(read_req(0));
            shared_dual_dut.port[1].request(read_req(4));
            shared_dual_dut.port[2].request(read_req(8));
        endpar
        par
            action
                let data <- shared_dual_dut.port[0].response();
                if(data != 'h30303030) $finish();
            endaction
            action
                let data <- shared_dual_dut.port[1].response();
                if(data != 'h41414141) $finish();
            endaction
            action
                let data <- shared_dual_dut.port[2].response();
                if(data != 'h52525252) $finish();
            endaction
        endpar

        /* Sustained same-bank traffic must make progress on every logical port. */
        rg_fairness_active <= True;
        delay(64);
        rg_fairness_active <= False;
        action
            for(Integer client = 0; client < 3; client = client + 1) begin
                if(rg_fairness_accepts[client] < 20 ||
                        rg_fairness_accepts[client] > 23) begin
                    print_fmt($format("Logical port %0d starved after %0d accepted requests",
                        client, rg_fairness_accepts[client]), RED);
                    $finish();
                end
            end
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

        /* L=0 covers decode, arbitration, memory, and response muxing in one cycle. */
        par
            scalar_dut.port[0].request(write_req(2, 'hfacecafe, 'b1111));
            ping_dut.port[0].request(write_req(1, 'h0a0b0c0d, 'b1111));
            ping_dut.port[1].request(write_req(5, 'h1a1b1c1d, 'b1111));
            comb_dut.port[0].request(write_req(0, 'h01020304, 'b1111));
            comb_dut.port[1].request(write_req(1, 'h11121314, 'b1111));
            comb_dut.port[2].request(write_req(2, 'h21222324, 'b1111));
        endpar
        latency_2_dut.port[0].request(BankedMemoryRequest_t {
            address   : 1,
            data      : 'h76543210,
            write_mask: 1,
            write     : True
        });
        action
            rg_read_start <= rg_cycle;
            latency_2_dut.port[0].request(BankedMemoryRequest_t {
                address   : 1,
                data      : 0,
                write_mask: 0,
                write     : False
            });
        endaction
        action
            let data <- latency_2_dut.port[0].response();
            if(data != 'h76543210 || rg_cycle - rg_read_start != 2) begin
                print_fmt($format("Fixed L=2 response returned after %0d cycles",
                    rg_cycle - rg_read_start), RED);
                $finish();
            end
        endaction
        par
            scalar_dut.port[0].request(read_req(2));
            action
                let data <- scalar_dut.port[0].response();
                if(data != 'hfacecafe) begin
                    print_s("1/1/1 combinational access added a router cycle", RED);
                    $finish();
                end
            endaction
        endpar
        par
            ping_dut.port[0].request(read_req(1));
            ping_dut.port[1].request(read_req(5));
            action
                let data <- ping_dut.port[0].response();
                if(data != 'h0a0b0c0d) $finish();
            endaction
            action
                let data <- ping_dut.port[1].response();
                if(data != 'h1a1b1c1d) $finish();
            endaction
        endpar
        par
            comb_dut.port[0].request(read_req(0));
            comb_dut.port[1].request(read_req(1));
            comb_dut.port[2].request(read_req(2));
            action
                let data <- comb_dut.port[0].response();
                if(data != 'h01020304) $finish();
            endaction
            action
                let data <- comb_dut.port[1].response();
                if(data != 'h11121314) $finish();
            endaction
            action
                let data <- comb_dut.port[2].response();
                if(data != 'h21222324) $finish();
            endaction
        endpar

        /* A delayed consumer uses one response skid; writes remain eligible. */
        scalar_dut.port[0].request(read_req(2));
        scalar_dut.port[0].request(write_req(1, 'h12345678, 'b1111));
        action
            let data <- scalar_dut.port[0].response();
            if(data != 'hfacecafe) $finish();
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
