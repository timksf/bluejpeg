package BankedMemory;

import BRAM :: *;
import FIFOF :: *;
import GetPut :: *;
import Vector :: *;

typedef enum {
    BANK_ARB_ROUND_ROBIN,
    BANK_ARB_FIXED_PRIORITY
} BankedMemoryArb_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(bank_w) bank;
    Bit#(addr_w) address;
    Bit#(data_w) data;
    Bit#(mask_w) write_mask;
    Bool write;
    Bit#(tag_w) tag;
} BankedMemoryRequest_t#(
    numeric type bank_w,
    numeric type addr_w,
    numeric type data_w,
    numeric type mask_w,
    numeric type tag_w
) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(data_w) data;
    Bit#(tag_w) tag;
} BankedMemoryResponse_t#(
    numeric type data_w,
    numeric type tag_w
) deriving(Bits, Eq, FShow);

/*
 * Buffered single-port backend. The signature intentionally matches the
 * request/response shape of BlueSRAM's RWIfc. A backend must retain a read
 * response until response() is called; use BlueSRAM's buffered mode.
 */
interface BankedMemoryPort_ifc#(
    numeric type addr_w,
    numeric type data_w,
    numeric type mask_w
);
    method Action request(Bit#(addr_w) address, Bit#(data_w) data,
                          Bit#(mask_w) write_mask, Bool write);
    method ActionValue#(Bit#(data_w)) response();
endinterface

interface BankedMemory_ifc#(
    numeric type n_banks,
    numeric type n_clients,
    numeric type addr_w,
    numeric type data_w,
    numeric type mask_w,
    numeric type tag_w
);
    interface Vector#(n_clients, Put#(BankedMemoryRequest_t#(
        TLog#(n_banks), addr_w, data_w, mask_w, tag_w))) request;
    interface Vector#(n_clients, Get#(BankedMemoryResponse_t#(
        data_w, tag_w))) response;
endinterface

typedef struct {
    Bit#(TLog#(n_clients)) client;
    Bit#(tag_w) tag;
} BankedMemoryOwner_t#(
    numeric type n_clients,
    numeric type tag_w
) deriving(Bits, Eq, FShow);

/* Adapter for the standard Bluespec single-port byte-enable BRAM. */
module mkBankedMemoryBRAMPort#(BRAM_Configure cfg)(BankedMemoryPort_ifc#(
        addr_w, data_w, mask_w
    )) provisos(
        Div#(data_w, mask_w, chunk_w),
        Mul#(chunk_w, mask_w, data_w)
    );

    BRAM1PortBE#(Bit#(addr_w), Bit#(data_w), mask_w) i_bram <- mkBRAM1ServerBE(cfg);

    method Action request(Bit#(addr_w) address, Bit#(data_w) data,
                          Bit#(mask_w) write_mask, Bool write);
        i_bram.portA.request.put(BRAMRequestBE {
            writeen        : write ? write_mask : 0,
            responseOnWrite: False,
            address        : address,
            datain         : data
        });
    endmethod

    method ActionValue#(Bit#(data_w)) response();
        let data <- i_bram.portA.response.get();
        return data;
    endmethod

endmodule

/*
 * Generic core. Requests to different banks proceed independently. Read
 * responses may return out of order across banks and are matched by tag.
 * The bank field must be smaller than n_banks.
 */
module mkBankedMemory#(
        Vector#(n_banks, BankedMemoryPort_ifc#(addr_w, data_w, mask_w)) memory,
        BankedMemoryArb_t arbitration,
        Integer queueDepth
    )(BankedMemory_ifc#(n_banks, n_clients, addr_w, data_w, mask_w, tag_w))
    provisos(
        Add#(1, banks_minus_one__, n_banks),
        Add#(1, clients_minus_one__, n_clients)
    );

    Vector#(n_clients, FIFOF#(BankedMemoryRequest_t#(
        TLog#(n_banks), addr_w, data_w, mask_w, tag_w))) f_client_req <-
        replicateM(mkSizedFIFOF(queueDepth));
    Vector#(n_clients, FIFOF#(BankedMemoryResponse_t#(
        data_w, tag_w))) f_client_rsp <-
        replicateM(mkSizedFIFOF(queueDepth));

    Vector#(n_banks, Vector#(n_clients, FIFOF#(BankedMemoryRequest_t#(
        TLog#(n_banks), addr_w, data_w, mask_w, tag_w)))) f_bank_req <-
        replicateM(replicateM(mkSizedFIFOF(queueDepth)));
    Vector#(n_banks, Vector#(n_clients, FIFOF#(BankedMemoryResponse_t#(
        data_w, tag_w)))) f_bank_rsp <-
        replicateM(replicateM(mkSizedFIFOF(queueDepth)));
    Vector#(n_banks, FIFOF#(BankedMemoryOwner_t#(
        n_clients, tag_w))) f_bank_owner <-
        replicateM(mkSizedFIFOF(queueDepth));

    Vector#(n_banks, Reg#(Bit#(TLog#(n_clients)))) rg_next_client <-
        replicateM(mkReg(0));
    Vector#(n_clients, Reg#(Bit#(TLog#(n_banks)))) rg_next_bank <-
        replicateM(mkReg(0));

    function Bit#(TLog#(n_clients)) nextClient(Bit#(TLog#(n_clients)) index);
        return index == fromInteger(valueof(n_clients) - 1) ? 0 : index + 1;
    endfunction

    function Bit#(TLog#(n_clients)) addWrappedClient(
            Bit#(TLog#(n_clients)) base, Integer offset
        );
        Bit#(TAdd#(TLog#(n_clients), 1)) sum = zeroExtend(base) + fromInteger(offset);
        if(sum >= fromInteger(valueof(n_clients)))
            sum = sum - fromInteger(valueof(n_clients));
        return truncate(sum);
    endfunction

    function Bit#(TLog#(n_banks)) nextBank(Bit#(TLog#(n_banks)) index);
        return index == fromInteger(valueof(n_banks) - 1) ? 0 : index + 1;
    endfunction

    function Bit#(TLog#(n_banks)) addWrappedBank(
            Bit#(TLog#(n_banks)) base, Integer offset
        );
        Bit#(TAdd#(TLog#(n_banks), 1)) sum = zeroExtend(base) + fromInteger(offset);
        if(sum >= fromInteger(valueof(n_banks)))
            sum = sum - fromInteger(valueof(n_banks));
        return truncate(sum);
    endfunction

    /* Route each client into independent per-bank arbitration queues. */
    for(Integer c = 0; c < valueof(n_clients); c = c + 1) begin
        rule r_route_client;
            let req = f_client_req[c].first;
            f_client_req[c].deq;
            f_bank_req[req.bank][c].enq(req);
        endrule
    end

    /* One request per bank and cycle. */
    for(Integer b = 0; b < valueof(n_banks); b = b + 1) begin
        rule r_issue_bank_request;
            Bit#(TLog#(n_clients)) start = arbitration == BANK_ARB_ROUND_ROBIN ?
                rg_next_client[b] : 0;
            Maybe#(Bit#(TLog#(n_clients))) selected = tagged Invalid;

            for(Integer offset = 0; offset < valueof(n_clients); offset = offset + 1) begin
                let client = addWrappedClient(start, offset);
                if(!isValid(selected) && f_bank_req[b][client].notEmpty)
                    selected = tagged Valid client;
            end

            if(selected matches tagged Valid .client) begin
                let req = f_bank_req[b][client].first;
                f_bank_req[b][client].deq;
                memory[b].request(req.address, req.data, req.write_mask, req.write);

                if(!req.write) begin
                    f_bank_owner[b].enq(BankedMemoryOwner_t {
                        client: client,
                        tag   : req.tag
                    });
                end

                if(arbitration == BANK_ARB_ROUND_ROBIN)
                    rg_next_client[b] <= nextClient(client);
            end
        endrule

        rule r_receive_bank_response;
            let owner = f_bank_owner[b].first;
            f_bank_owner[b].deq;
            let data <- memory[b].response();
            f_bank_rsp[b][owner.client].enq(BankedMemoryResponse_t {
                data: data,
                tag : owner.tag
            });
        endrule
    end

    /* Merge bank responses independently for each client. */
    for(Integer c = 0; c < valueof(n_clients); c = c + 1) begin
        rule r_collect_client_response;
            Bit#(TLog#(n_banks)) start = arbitration == BANK_ARB_ROUND_ROBIN ?
                rg_next_bank[c] : 0;
            Maybe#(Bit#(TLog#(n_banks))) selected = tagged Invalid;

            for(Integer offset = 0; offset < valueof(n_banks); offset = offset + 1) begin
                let bank = addWrappedBank(start, offset);
                if(!isValid(selected) && f_bank_rsp[bank][c].notEmpty)
                    selected = tagged Valid bank;
            end

            if(selected matches tagged Valid .bank) begin
                let rsp = f_bank_rsp[bank][c].first;
                f_bank_rsp[bank][c].deq;
                f_client_rsp[c].enq(rsp);
                if(arbitration == BANK_ARB_ROUND_ROBIN)
                    rg_next_bank[c] <= nextBank(bank);
            end
        endrule
    end

    interface request  = map(toPut, f_client_req);
    interface response = map(toGet, f_client_rsp);

endmodule

/* Convenience constructor using one standard single-port BRAM per bank. */
module mkBankedMemoryBRAM#(
        BRAM_Configure cfg,
        BankedMemoryArb_t arbitration,
        Integer queueDepth
    )(BankedMemory_ifc#(n_banks, n_clients, addr_w, data_w, mask_w, tag_w))
    provisos(
        Add#(1, banks_minus_one__, n_banks),
        Add#(1, clients_minus_one__, n_clients),
        Div#(data_w, mask_w, chunk_w),
        Mul#(chunk_w, mask_w, data_w)
    );

    Vector#(n_banks, BankedMemoryPort_ifc#(addr_w, data_w, mask_w)) memory <-
        replicateM(mkBankedMemoryBRAMPort(cfg));
    let ifc <- mkBankedMemory(memory, arbitration, queueDepth);
    return ifc;

endmodule

endpackage
