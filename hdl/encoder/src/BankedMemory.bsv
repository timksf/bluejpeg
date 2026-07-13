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
    numeric type n_memory_ports,
    numeric type addr_w,
    numeric type data_w,
    numeric type mask_w
);
    interface Vector#(n_memory_ports, BankedMemoryRWPort_ifc#(
        addr_w, data_w, mask_w)) port;
endinterface

/* N logical request ports sharing the configured banks. */
interface BankedMemoryAccessor_ifc#(
    numeric type n_clients,
    numeric type addr_w,
    numeric type data_w,
    numeric type mask_w
);
    interface Vector#(n_clients, BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w)) port;
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
 * Bank router with per-client queues and round-robin arbitration. If enough
 * physical ports exist, logical port i uses physical port i directly. If there
 * are more logical ports than physical ports, colliding accesses are buffered
 * independently and serialized without starving a continuously requesting
 * logical port.
 */
module mkBankedMemoryAccessor#(
        Vector#(n_banks, BankedMemoryPort_ifc#(
            n_memory_ports, bank_addr_w, data_w, mask_w)) memory,
        BankedMemoryConfig_t cfg
    )(BankedMemoryAccessor_ifc#(n_clients, addr_w, data_w, mask_w))
    provisos(
        Add#(1, banks_minus_one__, n_banks),
        Add#(1, clients_minus_one__, n_clients),
        Add#(1, memory_ports_minus_one__, n_memory_ports),
        Add#(bank_index_pad__, TLog#(n_banks), addr_w),
        Add#(bank_addr_w, bank_addr_pad__, addr_w),
        Add#(bank_index_ext_pad__, TLog#(n_banks), TAdd#(addr_w, 1)),
        Add#(bank_addr_w, bank_addr_ext_pad__, TAdd#(addr_w, 1))
    );

    BankedAddressMapper_ifc#(n_banks, addr_w, bank_addr_w) i_mapper <-
        mkBankedAddressMapper(cfg);

    Vector#(n_clients, BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w)) access_ports = ?;

    if(valueof(n_clients) <= valueof(n_memory_ports)) begin
        if(valueof(n_banks) == 1) begin
            function BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w) make_direct_port(
                    Integer client_index
                );
                return interface BankedMemoryRWPort_ifc;
                    method Action request(BankedMemoryRequest_t#(addr_w, data_w, mask_w) req);
                        let access = i_mapper.map_address(req.address);
                        memory[0].port[client_index].request(BankedMemoryRequest_t {
                            address   : access.address,
                            data      : req.data,
                            write_mask: req.write_mask,
                            write     : req.write
                        });
                    endmethod

                    method response = memory[0].port[client_index].response;
                endinterface;
            endfunction

            access_ports = genWith(make_direct_port);
        end else begin
            Vector#(n_clients, FIFOF#(Bit#(TLog#(n_banks)))) f_response_bank <-
                replicateM(mkSizedFIFOF(cfg.outstanding_reads));

            function BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w) make_direct_banked_port(
                    Integer client_index
                );
                return interface BankedMemoryRWPort_ifc;
                    method Action request(BankedMemoryRequest_t#(addr_w, data_w, mask_w) req)
                            if(f_response_bank[client_index].notFull);
                        let access = i_mapper.map_address(req.address);
                        memory[access.bank].port[client_index].request(BankedMemoryRequest_t {
                            address   : access.address,
                            data      : req.data,
                            write_mask: req.write_mask,
                            write     : req.write
                        });
                        if(!req.write)
                            f_response_bank[client_index].enq(access.bank);
                    endmethod

                    method ActionValue#(Bit#(data_w)) response();
                        let bank = f_response_bank[client_index].first;
                        f_response_bank[client_index].deq;
                        let data <- memory[bank].port[client_index].response;
                        return data;
                    endmethod
                endinterface;
            endfunction

            access_ports = genWith(make_direct_banked_port);
        end
    end else begin
        Vector#(n_clients, FIFOF#(BankedMemoryRequest_t#(
            addr_w, data_w, mask_w))) f_client_request <-
            replicateM(mkSizedFIFOF(cfg.outstanding_reads));
        Vector#(n_banks, Vector#(n_memory_ports, Vector#(n_clients, FIFOF#(
            BankedMemoryRequest_t#(
                bank_addr_w, data_w, mask_w))))) f_bank_request <-
            replicateM(replicateM(replicateM(mkSizedFIFOF(cfg.outstanding_reads))));

        Vector#(n_clients, FIFOF#(Bit#(TLog#(n_banks)))) f_response_bank <-
            replicateM(mkSizedFIFOF(cfg.outstanding_reads));
        Vector#(n_banks, Vector#(n_memory_ports, FIFOF#(
            Bit#(TLog#(n_clients))))) f_response_owner <-
            replicateM(replicateM(mkSizedFIFOF(cfg.outstanding_reads)));
        Vector#(n_banks, Vector#(n_memory_ports, Vector#(n_clients, FIFOF#(
            Bit#(data_w))))) f_bank_response <-
            replicateM(replicateM(replicateM(mkSizedFIFOF(cfg.outstanding_reads))));

        Vector#(n_banks, Vector#(n_memory_ports, Reg#(
            Bit#(TLog#(n_clients))))) rg_next_client <-
            replicateM(replicateM(mkReg(0)));

        function Bit#(TLog#(n_clients)) next_client(Bit#(TLog#(n_clients)) client);
            return client == fromInteger(valueof(n_clients) - 1) ? 0 : client + 1;
        endfunction

        function Bit#(TLog#(n_clients)) add_wrapped_client(
                Bit#(TLog#(n_clients)) base, Integer offset
            );
            Bit#(TAdd#(TLog#(n_clients), 1)) sum = zeroExtend(base) + fromInteger(offset);
            if(sum >= fromInteger(valueof(n_clients)))
                sum = sum - fromInteger(valueof(n_clients));
            return truncate(sum);
        endfunction

        for(Integer c = 0; c < valueof(n_clients); c = c + 1) begin
            Integer memory_port_index = c % valueof(n_memory_ports);

            rule r_route_client_request;
                let req = f_client_request[c].first;
                let access = i_mapper.map_address(req.address);
                f_client_request[c].deq;
                f_bank_request[access.bank][memory_port_index][c].enq(BankedMemoryRequest_t {
                    address   : access.address,
                    data      : req.data,
                    write_mask: req.write_mask,
                    write     : req.write
                });
            endrule
        end

        for(Integer b = 0; b < valueof(n_banks); b = b + 1) begin
            for(Integer p = 0; p < valueof(n_memory_ports); p = p + 1) begin
                rule r_issue_bank_request;
                    let start = rg_next_client[b][p];
                    Maybe#(Bit#(TLog#(n_clients))) selected = tagged Invalid;

                    for(Integer offset = 0; offset < valueof(n_clients); offset = offset + 1) begin
                        let client = add_wrapped_client(start, offset);
                        let assigned_port = client % fromInteger(valueof(n_memory_ports));
                        if(!isValid(selected) && assigned_port == fromInteger(p) &&
                                f_bank_request[b][p][client].notEmpty)
                            selected = tagged Valid client;
                    end

                    if(selected matches tagged Valid .client) begin
                        let req = f_bank_request[b][p][client].first;
                        f_bank_request[b][p][client].deq;
                        memory[b].port[p].request(req);
                        if(!req.write)
                            f_response_owner[b][p].enq(client);
                        rg_next_client[b][p] <= next_client(client);
                    end
                endrule

                rule r_receive_bank_response;
                    let client = f_response_owner[b][p].first;
                    f_response_owner[b][p].deq;
                    let data <- memory[b].port[p].response;
                    f_bank_response[b][p][client].enq(data);
                endrule
            end
        end

        function BankedMemoryRWPort_ifc#(addr_w, data_w, mask_w) make_buffered_port(
                Integer client_index
            );
            Integer memory_port_index = client_index % valueof(n_memory_ports);

            return interface BankedMemoryRWPort_ifc;
                method Action request(BankedMemoryRequest_t#(addr_w, data_w, mask_w) req)
                        if(f_client_request[client_index].notFull &&
                            f_response_bank[client_index].notFull);
                    let access = i_mapper.map_address(req.address);
                    f_client_request[client_index].enq(req);
                    if(!req.write)
                        f_response_bank[client_index].enq(access.bank);
                endmethod

                method ActionValue#(Bit#(data_w)) response();
                    let bank = f_response_bank[client_index].first;
                    let data = f_bank_response[bank][memory_port_index][client_index].first;
                    f_response_bank[client_index].deq;
                    f_bank_response[bank][memory_port_index][client_index].deq;
                    return data;
                endmethod
            endinterface;
        endfunction

        access_ports = genWith(make_buffered_port);
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
