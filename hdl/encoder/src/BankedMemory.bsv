package BankedMemory;

import BRAM :: *;
import FIFOF :: *;
import Vector :: *;

typedef enum {
    BANK_MAP_INTERLEAVED,
    BANK_MAP_CONTIGUOUS
} BankedMemoryMap_t deriving(Bits, Eq, FShow);

typedef struct {
    Integer address_base;
    Integer memory_size;
    Integer bank_depth;
    Integer outstanding_reads;
    BankedMemoryMap_t mapping;
} BankedMemoryConfig_t;

typedef struct {
    Bit#(addr_w) address;
    Bit#(data_w) data;
    Bit#(mask_w) write_mask;
    Bool write;
} BankedMemoryRequest_t#(
    numeric type addr_w,
    numeric type data_w,
    numeric type mask_w
) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(TLog#(n_banks)) bank;
    Bit#(bank_addr_w) address;
} BankedMemoryAccess_t#(
    numeric type n_banks,
    numeric type bank_addr_w
) deriving(Bits, Eq, FShow);

interface BankedAddressMapper_ifc#(
    numeric type n_banks,
    numeric type addr_w,
    numeric type bank_addr_w
);
    method Bool in_range(Bit#(addr_w) address);
    method BankedMemoryAccess_t#(n_banks, bank_addr_w) map_address(Bit#(addr_w) address);
endinterface

interface BankedMemoryRWPort_ifc#(
    numeric type addr_w,
    numeric type data_w,
    numeric type mask_w
);
    method Action request(BankedMemoryRequest_t#(addr_w, data_w, mask_w) req);
    method ActionValue#(Bit#(data_w)) response();
endinterface

/* One physical memory bank with N independently usable ports. */
interface BankedMemoryPort_ifc#(
    numeric type n_ports,
    numeric type addr_w,
    numeric type data_w,
    numeric type mask_w
);
    interface Vector#(n_ports, BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w)) port;
endinterface

/* N direct access lanes. Lane i always uses physical memory port i. */
interface BankedMemoryAccessor_ifc#(
    numeric type n_ports,
    numeric type addr_w,
    numeric type data_w,
    numeric type mask_w
);
    interface Vector#(n_ports, BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w)) port;
    method Bool in_range(Bit#(addr_w) address);
endinterface

module mkBankedAddressMapper#(
        BankedMemoryConfig_t cfg
    )(BankedAddressMapper_ifc#(n_banks, addr_w, bank_addr_w))
    provisos(
        Add#(1, banks_minus_one__, n_banks),
        Add#(bank_index_pad__, TLog#(n_banks), addr_w),
        Add#(bank_addr_w, bank_addr_pad__, addr_w),
        Add#(bank_index_ext_pad__, TLog#(n_banks), TAdd#(addr_w, 1)),
        Add#(bank_addr_w, bank_addr_ext_pad__, TAdd#(addr_w, 1))
    );

    method Bool in_range(Bit#(addr_w) address);
        Bit#(TAdd#(addr_w, 1)) extended_address = zeroExtend(address);
        return extended_address >= fromInteger(cfg.address_base) &&
            extended_address < fromInteger(cfg.address_base + cfg.memory_size);
    endmethod

    method BankedMemoryAccess_t#(n_banks, bank_addr_w) map_address(Bit#(addr_w) address);
        Bit#(TAdd#(addr_w, 1)) offset = zeroExtend(address) - fromInteger(cfg.address_base);
        Bit#(TAdd#(addr_w, 1)) bank = 0;
        Bit#(TAdd#(addr_w, 1)) local_address = 0;

        if(cfg.mapping == BANK_MAP_INTERLEAVED) begin
            bank = offset % fromInteger(valueof(n_banks));
            local_address = offset / fromInteger(valueof(n_banks));
        end else begin
            bank = offset / fromInteger(cfg.bank_depth);
            local_address = offset % fromInteger(cfg.bank_depth);
        end

        return BankedMemoryAccess_t {
            bank   : truncate(bank),
            address: truncate(local_address)
        };
    endmethod

endmodule

module mkBankedMemoryBRAM1Port#(
        BRAM_Configure cfg
    )(BankedMemoryPort_ifc#(1, addr_w, data_w, 1));

    BRAM1Port#(Bit#(addr_w), Bit#(data_w)) i_bram <- mkBRAM1Server(cfg);

    function BankedMemoryRWPort_ifc#(addr_w, data_w, 1) make_port(Integer port_index);
        return interface BankedMemoryRWPort_ifc;
            method Action request(BankedMemoryRequest_t#(addr_w, data_w, 1) req);
                i_bram.portA.request.put(BRAMRequest {
                    write          : req.write,
                    responseOnWrite: False,
                    address        : req.address,
                    datain         : req.data
                });
            endmethod

            method response = i_bram.portA.response.get;
        endinterface;
    endfunction

    interface port = genWith(make_port);

endmodule

module mkBankedMemoryBRAM1PortBE#(
        BRAM_Configure cfg
    )(BankedMemoryPort_ifc#(1, addr_w, data_w, mask_w))
    provisos(
        Div#(data_w, mask_w, chunk_w),
        Mul#(chunk_w, mask_w, data_w)
    );

    BRAM1PortBE#(Bit#(addr_w), Bit#(data_w), mask_w) i_bram <- mkBRAM1ServerBE(cfg);

    function BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w) make_port(Integer port_index);
        return interface BankedMemoryRWPort_ifc;
            method Action request(BankedMemoryRequest_t#(addr_w, data_w, mask_w) req);
                i_bram.portA.request.put(BRAMRequestBE {
                    writeen        : req.write ? req.write_mask : 0,
                    responseOnWrite: False,
                    address        : req.address,
                    datain         : req.data
                });
            endmethod

            method response = i_bram.portA.response.get;
        endinterface;
    endfunction

    interface port = genWith(make_port);

endmodule

module mkBankedMemoryBRAM2Port#(
        BRAM_Configure cfg
    )(BankedMemoryPort_ifc#(2, addr_w, data_w, 1));

    BRAM2Port#(Bit#(addr_w), Bit#(data_w)) i_bram <- mkBRAM2Server(cfg);

    function BankedMemoryRWPort_ifc#(addr_w, data_w, 1) make_port(Integer port_index);
        return interface BankedMemoryRWPort_ifc;
            method Action request(BankedMemoryRequest_t#(addr_w, data_w, 1) req);
                BRAMRequest#(Bit#(addr_w), Bit#(data_w)) bram_req = BRAMRequest {
                    write          : req.write,
                    responseOnWrite: False,
                    address        : req.address,
                    datain         : req.data
                };
                if(port_index == 0)
                    i_bram.portA.request.put(bram_req);
                else
                    i_bram.portB.request.put(bram_req);
            endmethod

            method ActionValue#(Bit#(data_w)) response();
                Bit#(data_w) data = ?;
                if(port_index == 0)
                    data <- i_bram.portA.response.get;
                else
                    data <- i_bram.portB.response.get;
                return data;
            endmethod
        endinterface;
    endfunction

    interface port = genWith(make_port);

endmodule

module mkBankedMemoryBRAM2PortBE#(
        BRAM_Configure cfg
    )(BankedMemoryPort_ifc#(2, addr_w, data_w, mask_w))
    provisos(
        Div#(data_w, mask_w, chunk_w),
        Mul#(chunk_w, mask_w, data_w)
    );

    BRAM2PortBE#(Bit#(addr_w), Bit#(data_w), mask_w) i_bram <- mkBRAM2ServerBE(cfg);

    function BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w) make_port(Integer port_index);
        return interface BankedMemoryRWPort_ifc;
            method Action request(BankedMemoryRequest_t#(addr_w, data_w, mask_w) req);
                BRAMRequestBE#(Bit#(addr_w), Bit#(data_w), mask_w) bram_req = BRAMRequestBE {
                    writeen        : req.write ? req.write_mask : 0,
                    responseOnWrite: False,
                    address        : req.address,
                    datain         : req.data
                };
                if(port_index == 0)
                    i_bram.portA.request.put(bram_req);
                else
                    i_bram.portB.request.put(bram_req);
            endmethod

            method ActionValue#(Bit#(data_w)) response();
                Bit#(data_w) data = ?;
                if(port_index == 0)
                    data <- i_bram.portA.response.get;
                else
                    data <- i_bram.portB.response.get;
                return data;
            endmethod
        endinterface;
    endfunction

    interface port = genWith(make_port);

endmodule

/*
 * Address-only bank router. Requests are forwarded in the calling cycle. The
 * only state in the multi-bank case records which bank owns each read response.
 */
module mkBankedMemoryAccessor#(
        Vector#(n_banks, BankedMemoryPort_ifc#(
            n_ports, bank_addr_w, data_w, mask_w)) memory,
        BankedMemoryConfig_t cfg
    )(BankedMemoryAccessor_ifc#(n_ports, addr_w, data_w, mask_w))
    provisos(
        Add#(1, banks_minus_one__, n_banks),
        Add#(bank_index_pad__, TLog#(n_banks), addr_w),
        Add#(bank_addr_w, bank_addr_pad__, addr_w),
        Add#(bank_index_ext_pad__, TLog#(n_banks), TAdd#(addr_w, 1)),
        Add#(bank_addr_w, bank_addr_ext_pad__, TAdd#(addr_w, 1))
    );

    BankedAddressMapper_ifc#(n_banks, addr_w, bank_addr_w) i_mapper <-
        mkBankedAddressMapper(cfg);

    Vector#(n_ports, BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w)) access_ports = ?;

    if(valueof(n_banks) == 1) begin
        function BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w) make_direct_port(Integer port_index);
            return interface BankedMemoryRWPort_ifc;
                method Action request(BankedMemoryRequest_t#(addr_w, data_w, mask_w) req);
                    let access = i_mapper.map_address(req.address);
                    memory[0].port[port_index].request(BankedMemoryRequest_t {
                        address   : access.address,
                        data      : req.data,
                        write_mask: req.write_mask,
                        write     : req.write
                    });
                endmethod

                method response = memory[0].port[port_index].response;
            endinterface;
        endfunction

        access_ports = genWith(make_direct_port);
    end else begin
        Vector#(n_ports, FIFOF#(Bit#(TLog#(n_banks)))) f_response_bank <-
            replicateM(mkSizedFIFOF(cfg.outstanding_reads));

        function BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w) make_banked_port(Integer port_index);
            return interface BankedMemoryRWPort_ifc;
                method Action request(BankedMemoryRequest_t#(addr_w, data_w, mask_w) req)
                        if(f_response_bank[port_index].notFull);
                    let access = i_mapper.map_address(req.address);
                    memory[access.bank].port[port_index].request(BankedMemoryRequest_t {
                        address   : access.address,
                        data      : req.data,
                        write_mask: req.write_mask,
                        write     : req.write
                    });
                    if(!req.write)
                        f_response_bank[port_index].enq(access.bank);
                endmethod

                method ActionValue#(Bit#(data_w)) response();
                    let bank = f_response_bank[port_index].first;
                    f_response_bank[port_index].deq;
                    let data <- memory[bank].port[port_index].response;
                    return data;
                endmethod
            endinterface;
        endfunction

        access_ports = genWith(make_banked_port);
    end

    interface port = access_ports;
    method in_range = i_mapper.in_range;

endmodule

/* Direct dual-port BRAM accessor used by single-bank clients such as the tiler. */
module mkBankedMemoryBRAM2Accessor#(
        BRAM_Configure bram_cfg
    )(BankedMemoryAccessor_ifc#(2, addr_w, data_w, 1));

    BankedMemoryConfig_t cfg = BankedMemoryConfig_t {
        address_base     : 0,
        memory_size      : bram_cfg.memorySize,
        bank_depth       : bram_cfg.memorySize,
        outstanding_reads: 1,
        mapping          : BANK_MAP_CONTIGUOUS
    };

    BankedMemoryPort_ifc#(2, addr_w, data_w, 1) i_bank <-
        mkBankedMemoryBRAM2Port(bram_cfg);
    Vector#(1, BankedMemoryPort_ifc#(2, addr_w, data_w, 1)) banks =
        cons(i_bank, nil);
    let ifc <- mkBankedMemoryAccessor(banks, cfg);
    return ifc;

endmodule

endpackage
