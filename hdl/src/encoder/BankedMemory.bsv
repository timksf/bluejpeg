package BankedMemory;

import Assert :: *;
import BRAM :: *;
import RegFile :: *;
import RWire :: *;
import Vector :: *;

typedef enum {
    BANK_MAP_INTERLEAVED,
    BANK_MAP_CONTIGUOUS
} BankedMemoryMap_t deriving(Bits, Eq, FShow);

typedef struct {
    Integer           address_base;
    Integer           memory_size;
    Integer           bank_depth;
    BankedMemoryMap_t mapping;
} BankedMemoryConfig_t;

typedef struct {
    Bit#(aw) address;
    Bit#(dw) data;
    Bit#(mw) write_mask;
    Bool     write;
} BankedMemoryRequest_t#(
    numeric type aw,
    numeric type dw,
    numeric type mw
) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(TLog#(n_banks)) bank;
    Bit#(bank_aw)        address;
} BankedMemoryAccess_t#(
    numeric type n_banks,
    numeric type bank_aw
) deriving(Bits, Eq, FShow);

typedef Bit#(TLog#(n_clients)) BankedMemoryClientId_t#(numeric type n_clients);

interface BankedAddressMapper_ifc#(
    numeric type n_banks,
    numeric type aw,
    numeric type bank_aw
);
    method Bool in_range(Bit#(aw) address);
    method BankedMemoryAccess_t#(n_banks, bank_aw) map_address(Bit#(aw) address);
endinterface

interface BankedMemoryRWPort_ifc#(
    numeric type aw,
    numeric type dw,
    numeric type mw
);
    method Action request(BankedMemoryRequest_t#(aw, dw, mw) req);
    method ActionValue#(Bit#(dw)) response();
endinterface

interface BankedMemoryPhysicalRWPort_ifc#(
    numeric type aw,
    numeric type dw,
    numeric type mw
);
    method Bool request_ready();
    method ActionValue#(Maybe#(Bit#(dw))) request(
        BankedMemoryRequest_t#(aw, dw, mw) req);
    method ActionValue#(Bit#(dw)) response();
endinterface

/*
 * One physical memory bank with P independently usable ports. Read latency is
 * fixed for a backend: 0 is combinational and 1 is the standard BRAM adapter.
 */
interface BankedMemoryPort_ifc#(
    numeric type n_memory_ports,
    numeric type read_latency,
    numeric type aw,
    numeric type dw,
    numeric type mw
);
    interface Vector#(n_memory_ports, BankedMemoryPhysicalRWPort_ifc#(
        aw, dw, mw)) port;
endinterface

/* N logical request ports sharing the configured banks. */
interface BankedMemoryAccessor_ifc#(
    numeric type n_clients,
    numeric type aw,
    numeric type dw,
    numeric type mw
);
    interface Vector#(n_clients, BankedMemoryRWPort_ifc#(aw, dw, mw)) port;
    method Bool in_range(Bit#(aw) address);
endinterface

module mkBankedAddressMapper#(
        BankedMemoryConfig_t cfg
    )(BankedAddressMapper_ifc#(n_banks, aw, bank_aw))
    provisos(
        Add#(1, banks_minus_one__, n_banks),
        Add#(bank_index_pad__, TLog#(n_banks), aw),
        Add#(bank_aw, bank_addr_pad__, aw),
        Add#(bank_index_ext_pad__, TLog#(n_banks), TAdd#(aw, 1)),
        Add#(bank_aw, bank_addr_ext_pad__, TAdd#(aw, 1))
    );

    staticAssert(cfg.address_base >= 0, "Banked memory address_base must be non-negative");
    staticAssert(cfg.memory_size > 0, "Banked memory memory_size must be greater than zero");
    staticAssert(cfg.bank_depth > 0, "Banked memory bank_depth must be greater than zero");
    staticAssert(cfg.address_base + cfg.memory_size <= 2 ** valueof(aw),
        "Banked memory address range does not fit aw");
    staticAssert(cfg.bank_depth <= 2 ** valueof(bank_aw),
        "Banked memory bank_depth does not fit bank_aw");
    staticAssert(cfg.memory_size <= valueof(n_banks) * cfg.bank_depth,
        "Banked memory mapping exceeds physical bank capacity");

    method Bool in_range(Bit#(aw) address);
        Bit#(TAdd#(aw, 1)) extended_address = zeroExtend(address);
        return extended_address >= fromInteger(cfg.address_base) &&
            extended_address < fromInteger(cfg.address_base + cfg.memory_size);
    endmethod

    method BankedMemoryAccess_t#(n_banks, bank_aw) map_address(Bit#(aw) address);
        Bit#(TAdd#(aw, 1)) offset        = zeroExtend(address) - fromInteger(cfg.address_base);
        Bit#(TAdd#(aw, 1)) bank          = 0;
        Bit#(TAdd#(aw, 1)) local_address = 0;

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

/* Combinational-read, single-port inferred memory. */
module mkBankedMemoryLUTRAM1Port(
        BankedMemoryPort_ifc#(1, 0, aw, dw, 1)
    );

    RegFile#(Bit#(aw), Bit#(dw)) i_memory <- mkRegFileFull;

    function BankedMemoryPhysicalRWPort_ifc#(aw, dw, 1) make_port(Integer port_index);
        return interface BankedMemoryPhysicalRWPort_ifc;
            method request_ready = True;

            method ActionValue#(Maybe#(Bit#(dw))) request(
                    BankedMemoryRequest_t#(aw, dw, 1) req
                );
                if(req.write)
                    i_memory.upd(req.address, req.data);
                return req.write ? tagged Invalid : tagged Valid i_memory.sub(req.address);
            endmethod

            method ActionValue#(Bit#(dw)) response();
                return ?;
            endmethod
        endinterface;
    endfunction

    interface port = genWith(make_port);

endmodule

/* Combinational-read inferred memory with write masks. */
module mkBankedMemoryLUTRAM1PortBE(
        BankedMemoryPort_ifc#(1, 0, aw, dw, mw)
    )
    provisos(
        Div#(dw, mw, chunk_w),
        Mul#(chunk_w, mw, dw)
    );

    RegFile#(Bit#(aw), Bit#(dw)) i_memory <- mkRegFileFull;

    function Bit#(dw) merge_write(Bit#(dw) old_data, Bit#(dw) new_data, Bit#(mw) write_mask);
        Vector#(mw, Bit#(chunk_w)) old_chunks = unpack(old_data);
        Vector#(mw, Bit#(chunk_w)) new_chunks = unpack(new_data);
        Vector#(mw, Bit#(chunk_w)) result     = old_chunks;
        for(Integer chunk = 0; chunk < valueof(mw); chunk = chunk + 1) begin
            if(write_mask[chunk] == 1)
                result[chunk] = new_chunks[chunk];
        end
        return pack(result);
    endfunction

    function BankedMemoryPhysicalRWPort_ifc#(aw, dw, mw) make_port(Integer port_index);
        return interface BankedMemoryPhysicalRWPort_ifc;
            method request_ready = True;

            method ActionValue#(Maybe#(Bit#(dw))) request(
                    BankedMemoryRequest_t#(aw, dw, mw) req
                );
                if(req.write)
                    i_memory.upd(req.address,
                        merge_write(i_memory.sub(req.address), req.data, req.write_mask));
                return req.write ? tagged Invalid : tagged Valid i_memory.sub(req.address);
            endmethod

            method ActionValue#(Bit#(dw)) response();
                return ?;
            endmethod
        endinterface;
    endfunction

    interface port = genWith(make_port);

endmodule

/* Attach a fixed latency contract to custom SRAM or macro ports. */
module mkBankedMemoryPortAdapter#(
        Vector#(n_memory_ports, BankedMemoryPhysicalRWPort_ifc#(aw, dw, mw)) ports
    )(BankedMemoryPort_ifc#(n_memory_ports, read_latency, aw, dw, mw));

    interface port = ports;

endmodule

module mkBankedMemoryBRAM1Port#(
        BRAM_Configure cfg
    )(BankedMemoryPort_ifc#(1, 1, aw, dw, 1));

    BRAM1Port#(Bit#(aw), Bit#(dw)) i_bram <- mkBRAM1Server(cfg);

    function BankedMemoryPhysicalRWPort_ifc#(aw, dw, 1) make_port(Integer port_index);
        return interface BankedMemoryPhysicalRWPort_ifc;
            method request_ready = True;

            method ActionValue#(Maybe#(Bit#(dw))) request(
                    BankedMemoryRequest_t#(aw, dw, 1) req
                );
                i_bram.portA.request.put(BRAMRequest {
                    write          : req.write,
                    responseOnWrite: False,
                    address        : req.address,
                    datain         : req.data
                });
                return tagged Invalid;
            endmethod

            method response = i_bram.portA.response.get;
        endinterface;
    endfunction

    interface port = genWith(make_port);

endmodule

module mkBankedMemoryBRAM1PortBE#(
        BRAM_Configure cfg
    )(BankedMemoryPort_ifc#(1, 1, aw, dw, mw))
    provisos(
        Div#(dw, mw, chunk_w),
        Mul#(chunk_w, mw, dw)
    );

    BRAM1PortBE#(Bit#(aw), Bit#(dw), mw) i_bram <- mkBRAM1ServerBE(cfg);

    function BankedMemoryPhysicalRWPort_ifc#(aw, dw, mw) make_port(Integer port_index);
        return interface BankedMemoryPhysicalRWPort_ifc;
            method request_ready = True;

            method ActionValue#(Maybe#(Bit#(dw))) request(
                    BankedMemoryRequest_t#(aw, dw, mw) req
                );
                i_bram.portA.request.put(BRAMRequestBE {
                    writeen        : req.write ? req.write_mask : 0,
                    responseOnWrite: False,
                    address        : req.address,
                    datain         : req.data
                });
                return tagged Invalid;
            endmethod

            method response = i_bram.portA.response.get;
        endinterface;
    endfunction

    interface port = genWith(make_port);

endmodule

module mkBankedMemoryBRAM2Port#(
        BRAM_Configure cfg
    )(BankedMemoryPort_ifc#(2, 1, aw, dw, 1));

    BRAM2Port#(Bit#(aw), Bit#(dw)) i_bram <- mkBRAM2Server(cfg);

    function BankedMemoryPhysicalRWPort_ifc#(aw, dw, 1) make_port(Integer port_index);
        return interface BankedMemoryPhysicalRWPort_ifc;
            method request_ready = True;

            method ActionValue#(Maybe#(Bit#(dw))) request(
                    BankedMemoryRequest_t#(aw, dw, 1) req
                );
                BRAMRequest#(Bit#(aw), Bit#(dw)) bram_req = BRAMRequest {
                    write          : req.write,
                    responseOnWrite: False,
                    address        : req.address,
                    datain         : req.data
                };
                if(port_index == 0)
                    i_bram.portA.request.put(bram_req);
                else
                    i_bram.portB.request.put(bram_req);
                return tagged Invalid;
            endmethod

            method ActionValue#(Bit#(dw)) response();
                Bit#(dw) data = ?;
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
    )(BankedMemoryPort_ifc#(2, 1, aw, dw, mw))
    provisos(
        Div#(dw, mw, chunk_w),
        Mul#(chunk_w, mw, dw)
    );

    BRAM2PortBE#(Bit#(aw), Bit#(dw), mw) i_bram <- mkBRAM2ServerBE(cfg);

    function BankedMemoryPhysicalRWPort_ifc#(aw, dw, mw) make_port(Integer port_index);
        return interface BankedMemoryPhysicalRWPort_ifc;
            method request_ready = True;

            method ActionValue#(Maybe#(Bit#(dw))) request(
                    BankedMemoryRequest_t#(aw, dw, mw) req
                );
                BRAMRequestBE#(Bit#(aw), Bit#(dw), mw) bram_req = BRAMRequestBE {
                    writeen        : req.write ? req.write_mask : 0,
                    responseOnWrite: False,
                    address        : req.address,
                    datain         : req.data
                };
                if(port_index == 0)
                    i_bram.portA.request.put(bram_req);
                else
                    i_bram.portB.request.put(bram_req);
                return tagged Invalid;
            endmethod

            method ActionValue#(Bit#(dw)) response();
                Bit#(dw) data = ?;
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

/* Bank-centric, bypassing router with one conflict skid per client. */
module mkBankedMemoryAccessor#(
        Vector#(n_banks, BankedMemoryPort_ifc#(
            n_memory_ports, read_latency, bank_aw, dw, mw)) memory,
        BankedMemoryConfig_t cfg
    )(BankedMemoryAccessor_ifc#(n_clients, aw, dw, mw))
    provisos(
        Add#(1, banks_minus_one__, n_banks),
        Add#(1, clients_minus_one__, n_clients),
        Add#(1, memory_ports_minus_one__, n_memory_ports),
        Add#(bank_index_pad__, TLog#(n_banks), aw),
        Add#(bank_aw, bank_addr_pad__, aw),
        Add#(bank_index_ext_pad__, TLog#(n_banks), TAdd#(aw, 1)),
        Add#(bank_aw, bank_addr_ext_pad__, TAdd#(aw, 1))
    );

    BankedAddressMapper_ifc#(n_banks, aw, bank_aw) i_mapper <-
        mkBankedAddressMapper(cfg);

    Vector#(n_clients, RWire#(BankedMemoryRequest_t#(aw, dw, mw))) w_client_request <-
        replicateM(mkRWire);
    Vector#(n_clients, Reg#(Maybe#(BankedMemoryRequest_t#(aw, dw, mw)))) rg_pending_request <-
        replicateM(mkReg(tagged Invalid));

    Vector#(n_clients, Reg#(Bool)) rg_read_busy <- replicateM(mkReg(False));
    Vector#(n_clients, Reg#(Maybe#(Bit#(dw)))) rg_response <-
        replicateM(mkReg(tagged Invalid));
    Vector#(n_clients, RWire#(Bit#(dw))) w_returned_data   <- replicateM(mkRWire);
    Vector#(n_clients, PulseWire)        pw_response_taken <- replicateM(mkPulseWire);

    Vector#(n_banks, Reg#(BankedMemoryClientId_t#(n_clients))) rg_next_client <- replicateM(mkReg(0));
    Vector#(n_banks, Vector#(n_memory_ports, Vector#(read_latency,
        Reg#(Maybe#(BankedMemoryClientId_t#(n_clients)))))) rg_response_owner <-
        replicateM(replicateM(replicateM(mkReg(tagged Invalid))));

    function BankedMemoryClientId_t#(n_clients) next_client(
            BankedMemoryClientId_t#(n_clients) client
        );
        return client == fromInteger(valueof(n_clients) - 1) ? 0 : client + 1;
    endfunction

    function BankedMemoryClientId_t#(n_clients) add_wrapped_client(
            BankedMemoryClientId_t#(n_clients) base, Integer offset
        );
        Bit#(TAdd#(TLog#(n_clients), 1)) sum = zeroExtend(base) + fromInteger(offset);
        if(sum >= fromInteger(valueof(n_clients)))
            sum = sum - fromInteger(valueof(n_clients));
        return truncate(sum);
    endfunction

    rule r_route_requests;
        Vector#(n_clients, Maybe#(BankedMemoryRequest_t#(aw, dw, mw))) active_request =
            replicate(tagged Invalid);
        Vector#(n_clients, Bool)             granted       = replicate(False);
        Vector#(n_clients, Bool)             issued_read   = replicate(False);
        Vector#(n_clients, Maybe#(Bit#(dw))) returned_data = replicate(tagged Invalid);

        for(Integer c = 0; c < valueof(n_clients); c = c + 1) begin
            active_request[c] = isValid(rg_pending_request[c]) ?
                rg_pending_request[c] : w_client_request[c].wget;
        end

        for(Integer b = 0; b < valueof(n_banks); b = b + 1) begin
            BankedMemoryClientId_t#(n_clients)         start        = rg_next_client[b];
            Maybe#(BankedMemoryClientId_t#(n_clients)) final_winner = tagged Invalid;

            for(Integer p = 0; p < valueof(n_memory_ports); p = p + 1) begin
                Maybe#(BankedMemoryClientId_t#(n_clients)) selected = tagged Invalid;

                if(memory[b].port[p].request_ready) begin
                    for(Integer offset = 0; offset < valueof(n_clients); offset = offset + 1) begin
                        let client  = add_wrapped_client(start, offset);
                        let request = active_request[client];
                        if(!isValid(selected) && !granted[client]) begin
                            if(request matches tagged Valid .req &&&
                                    (req.write || (valueof(read_latency) == 0 ?
                                        !isValid(rg_response[client]) :
                                        !rg_read_busy[client])) &&
                                    i_mapper.map_address(req.address).bank == fromInteger(b))
                                selected = tagged Valid client;
                        end
                    end
                end

                if(selected matches tagged Valid .client) begin
                    let req    = fromMaybe(?, active_request[client]);
                    let access = i_mapper.map_address(req.address);
                    BankedMemoryRequest_t#(bank_aw, dw, mw) bank_request = BankedMemoryRequest_t {
                        address   : access.address,
                        data      : req.data,
                        write_mask: req.write_mask,
                        write     : req.write
                    };

                    let immediate_data <- memory[b].port[p].request(bank_request);
                    granted[client] = True;
                    final_winner = selected;

                    if(!req.write) begin
                        issued_read[client] = True;
                        if(valueof(read_latency) == 0) begin
                            returned_data[client] = immediate_data;
                        end else begin
                            rg_response_owner[b][p][0] <= tagged Valid client;
                        end
                    end else if(valueof(read_latency) != 0) begin
                        rg_response_owner[b][p][0] <= tagged Invalid;
                    end
                end else if(valueof(read_latency) != 0) begin
                    rg_response_owner[b][p][0] <= tagged Invalid;
                end
            end

            if(final_winner matches tagged Valid .client)
                rg_next_client[b] <= next_client(client);
        end

        for(Integer c = 0; c < valueof(n_clients); c = c + 1) begin
            if(active_request[c] matches tagged Valid .req) begin
                if(granted[c]) begin
                    if(isValid(rg_pending_request[c]))
                        rg_pending_request[c] <= tagged Invalid;
                end else if(!isValid(rg_pending_request[c])) begin
                    rg_pending_request[c] <= tagged Valid req;
                end
            end

            if(valueof(read_latency) != 0) begin
                Bool next_read_busy = rg_read_busy[c];
                if(pw_response_taken[c])
                    next_read_busy = False;
                if(issued_read[c])
                    next_read_busy = True;
                rg_read_busy[c] <= next_read_busy;
            end

            if(returned_data[c] matches tagged Valid .data)
                w_returned_data[c].wset(data);
        end
    endrule

    if(valueof(read_latency) != 0) begin
        rule r_return_responses;
            Vector#(n_clients, Maybe#(Bit#(dw))) returned_data = replicate(tagged Invalid);

            for(Integer b = 0; b < valueof(n_banks); b = b + 1) begin
                for(Integer p = 0; p < valueof(n_memory_ports); p = p + 1) begin
                    let owner = rg_response_owner[b][p][valueof(read_latency) - 1];
                    if(owner matches tagged Valid .client) begin
                        let data <- memory[b].port[p].response;
                        returned_data[client] = tagged Valid data;
                    end

                    for(Integer stage = 1; stage < valueof(read_latency); stage = stage + 1)
                        rg_response_owner[b][p][stage] <= rg_response_owner[b][p][stage - 1];
                end
            end

            for(Integer c = 0; c < valueof(n_clients); c = c + 1) begin
                if(returned_data[c] matches tagged Valid .data)
                    w_returned_data[c].wset(data);
            end
        endrule
    end

    for(Integer c = 0; c < valueof(n_clients); c = c + 1) begin
        rule r_update_response;
            let returned_data = w_returned_data[c].wget;
            if(returned_data matches tagged Valid .data) begin
                if(!pw_response_taken[c])
                    rg_response[c] <= tagged Valid data;
            end else if(pw_response_taken[c]) begin
                rg_response[c] <= tagged Invalid;
            end
        endrule
    end

    function BankedMemoryRWPort_ifc#(aw, dw, mw) make_client_port(Integer client_index);
        return interface BankedMemoryRWPort_ifc;
            method Action request(BankedMemoryRequest_t#(aw, dw, mw) req)
                    if(!isValid(rg_pending_request[client_index]));
                w_client_request[client_index].wset(req);
            endmethod

            method ActionValue#(Bit#(dw)) response()
                    if(isValid(rg_response[client_index]) ||
                        isValid(w_returned_data[client_index].wget));
                pw_response_taken[client_index].send;
                return isValid(rg_response[client_index]) ?
                    fromMaybe(?, rg_response[client_index]) :
                    fromMaybe(?, w_returned_data[client_index].wget);
            endmethod
        endinterface;
    endfunction

    Vector#(n_clients, BankedMemoryRWPort_ifc#(aw, dw, mw)) access_ports =
        genWith(make_client_port);

    interface port = access_ports;
    method in_range = i_mapper.in_range;

endmodule

/* Direct dual-port BRAM accessor used by single-bank clients such as the tiler. */
module mkBankedMemoryBRAM2Accessor#(
        BRAM_Configure bram_cfg
    )(BankedMemoryAccessor_ifc#(2, aw, dw, 1));

    //each client owns one physical port, so no bank or response-owner mux is needed
    BankedMemoryPort_ifc#(2, 1, aw, dw, 1) i_bank <- mkBankedMemoryBRAM2Port(bram_cfg);

    function BankedMemoryRWPort_ifc#(aw, dw, 1) make_port(Integer port_index);
        return interface BankedMemoryRWPort_ifc;
            method Action request(BankedMemoryRequest_t#(aw, dw, 1) req);
                let unused <- i_bank.port[port_index].request(req);
            endmethod
            method response = i_bank.port[port_index].response;
        endinterface;
    endfunction

    interface port = genWith(make_port);
    method Bool in_range(Bit#(aw) address);
        Bit#(TAdd#(aw, 1)) extended_address = zeroExtend(address);
        return extended_address < fromInteger(bram_cfg.memorySize);
    endmethod

endmodule

endpackage
