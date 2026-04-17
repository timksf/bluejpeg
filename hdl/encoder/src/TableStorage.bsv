package TableStorage;

import Real :: *;
import FIFO :: *;
import GetPut :: *;
import Vector :: *;
import RegFile :: *;
import BuildVector :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import Types :: *;
import DefaultTables :: *;

typedef enum {
    QLuma,
    QChroma,
    QLumaScaled,
    QChromaScaled,
    HuffLumaDCVal,
    HuffLumaDCBits,
    HuffLumaACVal,
    HuffLumaACBits,
    HuffChromaDCVal,
    HuffChromaDCBits,
    HuffChromaACVal,
    HuffChromaACBits
} TableType_t deriving(Eq, Bits, FShow);

//huff table to index (in case bit encoding is unexpected)
function Bit#(2) huffTableIdx(HuffTableType_t htt);
    return case (htt)
        DC_Luma:    0;
        DC_Chroma:  1;
        AC_Luma:    2;
        AC_Chroma:  3;
    endcase;
endfunction

interface TableStorage_ifc#(numeric type qwidth);
    
    method Action generate_codes(HuffTableType_t htt);
    method Bool codegen_busy();
    method Bool ready();

    //unified table write interface (tables are never written at the same time)
    method Action write_table(TableType_t tt, Bit#(8) addr, Bit#(32) v);

    //combinational server interfaces for framewriter
    interface Server#(QuantTableIdx_t, UInt#(8)) quant_raw;
    interface Server#(HuffBitsIdx_t,   UInt#(8)) huff_bits_server;
    interface Server#(HuffValIdx_t,    UInt#(8)) huff_val_server;

    //combinational server interfaces for huff encoder
    interface Server#(HuffCodeDCIdx_t, HuffTableEntry_t) huff_code_dc_server;
    interface Server#(HuffCodeACIdx_t, HuffTableEntry_t) huff_code_ac_server;

    //combinational quant table interface (Int#(32) to not have width in interface type, gets optimized)
    interface Server#(QuantTableIdx_t, Int#(32)) quant_scaled;

endinterface

module mkTableStorage#(NumProxy#(qwidth) qp, Bool transposed)(TableStorage_ifc#(qwidth))
    provisos(
        Add#(qwidth, __a, 32) //qwidth <= 32
    );
    //tables are initialized to default values on startup for convenience, might have to remove that

    //unscaled quantization tables
    RegFile#(Bit#(6), UInt#(8)) quant_luma_raw   <- mkRegFileFull;
    RegFile#(Bit#(6), UInt#(8)) quant_chroma_raw <- mkRegFileFull;

    Vector#(64, Integer) luma_scaled_init   = quant_mult(std_LUMA_QUANT_c, qp, transposed);
    Vector#(64, Integer) chroma_scaled_init = quant_mult(std_CHROMA_QUANT_c, qp, transposed);

    //AAN-scaled tables for MCU datapath
    RegFile#(Bit#(6), Int#(qwidth)) quant_luma_scaled   <- mkRegFileFull;
    RegFile#(Bit#(6), Int#(qwidth)) quant_chroma_scaled <- mkRegFileFull;
    
    Wire#(QuantTableIdx_t) w_qidx <- mkWire;

    //wires for framewriter combinational server interfaces
    Wire#(QuantTableIdx_t) w_fw_qraw  <- mkWire;
    Wire#(HuffBitsIdx_t)   w_fw_hbits <- mkWire;
    Wire#(HuffValIdx_t)    w_fw_hval  <- mkWire;

    //wires for huff encoder combinational server interfaces
    Wire#(HuffCodeDCIdx_t) w_he_dc <- mkWire;
    Wire#(HuffCodeACIdx_t) w_he_ac <- mkWire;

    function Int#(32) read_quant_scaled();
        return signExtend(
            (w_qidx.pt == Luma) ? quant_luma_scaled.sub(w_qidx.idx) : quant_chroma_scaled.sub(w_qidx.idx)
        );
    endfunction

    function UInt#(8) read_quant_raw();
        return (w_fw_qraw.pt == Luma) ? quant_luma_raw.sub(w_fw_qraw.idx) : quant_chroma_raw.sub(w_fw_qraw.idx);
    endfunction

    //-------------------------------------------------------------------
    // Quantization table init-on-startup (runs after quant init completes)
    //-------------------------------------------------------------------
    Reg#(Bool)    rg_init_done <- mkReg(False);
    Reg#(Bit#(6)) rg_init_idx  <- mkReg(0);

    rule r_init_quant if (!rg_init_done);
        let i = rg_init_idx;
        quant_luma_raw.upd(i,       fromInteger(std_LUMA_QUANT_c[i]));
        quant_chroma_raw.upd(i,     fromInteger(std_CHROMA_QUANT_c[i]));
        quant_luma_scaled.upd(i,    fromInteger(luma_scaled_init[i]));
        quant_chroma_scaled.upd(i,  fromInteger(chroma_scaled_init[i]));
        if (i == 63)
            rg_init_done <= True;
        else
            rg_init_idx <= i + 1;
    endrule

    //huffman BITS/HUFFVAL tables
    //order: 0=DC_Luma, 1=DC_Chroma, 2=AC_Luma, 3=AC_Chroma
    Vector#(4, RegFile#(Bit#(4), UInt#(8))) huff_bits <- replicateM(mkRegFileFull);
    Vector#(4, RegFile#(Bit#(8), UInt#(8))) huff_val  <- replicateM(mkRegFileFull);

    //generated Huffman code/size tables for HuffEncoder
    //DC tables: indexed by magnitude, 0=Luma, 1=Chroma
    //AC tables: indexed by RRRRSSSS symbol, 0=Luma, 1=Chroma
    Vector#(2, RegFile#(Bit#(4), HuffTableEntry_t)) huff_code_dc <- replicateM(mkRegFileFull);
    Vector#(2, RegFile#(Bit#(8), HuffTableEntry_t)) huff_code_ac <- replicateM(mkRegFileFull);

    function HuffTableEntry_t read_huff_code_dc();
        return (w_he_dc.pt == Luma) ? huff_code_dc[0].sub(w_he_dc.idx) : huff_code_dc[1].sub(w_he_dc.idx);
    endfunction

    function HuffTableEntry_t read_huff_code_ac();
        return (w_he_ac.pt == Luma) ? huff_code_ac[0].sub(w_he_ac.idx) : huff_code_ac[1].sub(w_he_ac.idx);
    endfunction

    //-------------------------------------------------------------------
    // Huffman table init-on-startup (runs after quant init completes)
    //-------------------------------------------------------------------
    Reg#(Bool)     rg_huff_init_done <- mkReg(False);
    Reg#(UInt#(9)) rg_huff_init_idx  <- mkReg(0);

    rule r_init_huff if (rg_init_done && !rg_huff_init_done);
        let idx = rg_huff_init_idx;

        if (idx < 16) begin
            Bit#(4) i = truncate(pack(idx));
            huff_bits[0].upd(i, std_dc_luma_bits[i]);
            huff_bits[1].upd(i, std_dc_chroma_bits[i]);
            huff_bits[2].upd(i, std_ac_luma_bits[i]);
            huff_bits[3].upd(i, std_ac_chroma_bits[i]);
        end else begin
            Bit#(8) i = truncate(pack(idx - 16));
            huff_val[0].upd(i, (i < 12)  ? std_dc_val[i]        : 0);
            huff_val[1].upd(i, (i < 12)  ? std_dc_val[i]        : 0);
            huff_val[2].upd(i, (i < 162) ? std_ac_luma_val[i]   : 0);
            huff_val[3].upd(i, (i < 162) ? std_ac_chroma_val[i] : 0);
        end

        if (idx == 16 + 255)
            rg_huff_init_done <= True;
        rg_huff_init_idx <= idx + 1;
    endrule

    //Annex C.2 code generation FSM
    Reg#(Bool)             rg_cg_active <- mkReg(False);
    Reg#(HuffTableType_t)  rg_cg_table  <- mkRegU;
    Reg#(Bit#(5))          rg_cg_si     <- mkRegU; //current code length (1..16)
    Reg#(UInt#(8))         rg_cg_j      <- mkRegU; //counter within current length
    Reg#(Bit#(9))          rg_cg_k      <- mkRegU; //running HUFFVAL index
    Reg#(Bit#(16))         rg_cg_code   <- mkRegU; //running code value

    rule r_codegen if (rg_cg_active);
        //Steps:
        //1. retrieve number of symbols length rg_cg_si
        //2. build as many codes of that length as required
        //3. increase length and repeat until length 16

        let bits_count = huff_bits[huffTableIdx(rg_cg_table)].sub(truncate(rg_cg_si - 1));
        if (rg_cg_si > 16) begin
            //done
            rg_cg_active <= False;
            //could terminate size table with a 0 here
        end else if (rg_cg_j >= bits_count) begin
            //no more symbols at this length
            rg_cg_code <= rg_cg_code << 1;
            rg_cg_si   <= rg_cg_si + 1;
            rg_cg_j    <= 0;
        end else begin
            //write generated code into code table
            let tbl_idx = huffTableIdx(rg_cg_table);
            //symbol (index into huffman table) retrieved from huffval (contains symbols sorted by length)
            UInt#(8) symbol = huff_val[tbl_idx].sub(truncate(rg_cg_k));
            let entry = HuffTableEntry_t {
                code: rg_cg_code,
                size: truncate(rg_cg_si)
            };

            //DC_Luma -> huff_code_dc[0], DC_Chroma -> huff_code_dc[1]
            //AC_Luma -> huff_code_ac[0], AC_Chroma -> huff_code_ac[1]
            case (rg_cg_table)
                DC_Luma:    huff_code_dc[0].upd(truncate(pack(symbol)), entry);
                DC_Chroma:  huff_code_dc[1].upd(truncate(pack(symbol)), entry);
                AC_Luma:    huff_code_ac[0].upd(pack(symbol), entry);
                AC_Chroma:  huff_code_ac[1].upd(pack(symbol), entry);
            endcase

            //TODO stop if symbol 0?

            rg_cg_code <= rg_cg_code + 1;
            rg_cg_k    <= rg_cg_k + 1;
            rg_cg_j    <= rg_cg_j + 1;
        end
    endrule

    //table write interface, for SW configuration
    method Action write_table(TableType_t tt, Bit#(8) addr, Bit#(32) v);
        case (tt)
            QLuma:              quant_luma_raw.upd(truncate(addr), unpack(truncate(v)));
            QChroma:            quant_chroma_raw.upd(truncate(addr), unpack(truncate(v)));
            QLumaScaled:        quant_luma_scaled.upd(truncate(addr), unpack(truncate(v)));
            QChromaScaled:      quant_chroma_scaled.upd(truncate(addr), unpack(truncate(v)));
            HuffLumaDCBits:     huff_bits[0].upd(truncate(addr), unpack(truncate(v)));
            HuffChromaDCBits:   huff_bits[1].upd(truncate(addr), unpack(truncate(v)));
            HuffLumaACBits:     huff_bits[2].upd(truncate(addr), unpack(truncate(v)));
            HuffChromaACBits:   huff_bits[3].upd(truncate(addr), unpack(truncate(v)));
            HuffLumaDCVal:      huff_val[0].upd(addr, unpack(truncate(v)));
            HuffChromaDCVal:    huff_val[1].upd(addr, unpack(truncate(v)));
            HuffLumaACVal:      huff_val[2].upd(addr, unpack(truncate(v)));
            HuffChromaACVal:    huff_val[3].upd(addr, unpack(truncate(v)));
        endcase
    endmethod

    method Action generate_codes(HuffTableType_t htt) if (!rg_cg_active);
        rg_cg_active <= True;
        rg_cg_table  <= htt;
        rg_cg_si     <= 1;
        rg_cg_j      <= 0;
        rg_cg_k      <= 0;
        rg_cg_code   <= 0;
    endmethod

    method Bool codegen_busy    = rg_cg_active;
    method Bool ready           = rg_init_done && rg_huff_init_done;

    //to Quantizer / Huffencoder
    interface quant_scaled          = toGPServer(asReg(w_qidx),  read_quant_scaled);
    interface huff_code_dc_server   = toGPServer(asReg(w_he_dc), read_huff_code_dc);
    interface huff_code_ac_server   = toGPServer(asReg(w_he_ac), read_huff_code_ac);

    //to JPEGFileWriter
    interface quant_raw         = toGPServer(asReg(w_fw_qraw),  read_quant_raw);
    interface huff_bits_server  = toGPServer(asReg(w_fw_hbits), huff_bits[huffTableIdx(w_fw_hbits.htt)].sub(w_fw_hbits.idx));
    interface huff_val_server   = toGPServer(asReg(w_fw_hval),  huff_val[huffTableIdx(w_fw_hval.htt)].sub(w_fw_hval.idx));

endmodule

endpackage