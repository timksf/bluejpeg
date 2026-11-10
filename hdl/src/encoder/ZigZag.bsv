package ZigZag;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import RegFile :: *;
import BuildVector :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import Types :: *;

function Vector#(64, Integer) zigzag_indices(Bool transposed);
    //default zizag coordinates
    Vector#(64, Integer) z = vec(
        0,  1,  8, 16,  9,  2,  3, 10,
       17, 24, 32, 25, 18, 11,  4,  5,
       12, 19, 26, 33, 40, 48, 41, 34,
       27, 20, 13,  6,  7, 14, 21, 28,
       35, 42, 49, 56, 57, 50, 43, 36,
       29, 22, 15, 23, 30, 37, 44, 51,
       58, 59, 52, 45, 38, 31, 39, 46,
       53, 60, 61, 54, 47, 55, 62, 63
    );

    Vector#(64, Integer) res = newVector;
    for(Integer i = 0; i < 64; i = i + 1) begin
        Integer idx = z[i];
        Integer r   = idx / 8;
        Integer c   = idx % 8;
        //for transposed zigzag, decompose into r, c and convert to transposed linear index
        res[i] = transposed ? (c * 8 + r) : idx;
    end

    return res;
endfunction

interface Zigzag_ifc#(numeric type bits);
    interface Server#(Int#(bits), Int#(bits)) data;
endinterface

module mkZigZag#(Bool buffer_in, Bool transposed)(Zigzag_ifc#(bits))
    provisos(
        Bits#(Int#(bits), _sz)
    );

    FIFO#(Int#(bits)) f_in;
    FIFO#(Int#(bits)) f_out <- mkFIFO;

    if(buffer_in)
        f_in <- mkFIFO;
    else
        f_in <- mkBypassFIFO;

    //ping-pong buffer, one for writing one for reading
    Vector#(64, Reg#(Int#(bits))) i_buf0 <- replicateM(mkRegU);
    Vector#(64, Reg#(Int#(bits))) i_buf1 <- replicateM(mkRegU);

    Reg#(Bit#(6)) rg_write_idx <- mkReg(0);
    Reg#(Bit#(6)) rg_read_idx  <- mkReg(0);

    //state
    Reg#(Bit#(1)) rg_write_bank <- mkReg(0);
    Reg#(Bit#(1)) rg_read_bank  <- mkReg(0);

    //prevent under or overflow
    Reg#(Bit#(2)) rg_blocks_written <- mkReg(0);
    Reg#(Bit#(2)) rg_blocks_read    <- mkReg(0);

    Vector#(64, Integer) zigzag_map = zigzag_indices(transposed);

    Bit#(2) blocks_rdy = rg_blocks_written - rg_blocks_read;

    (* descending_urgency = "r_read_out, r_write_in" *)
    rule r_write_in (blocks_rdy < 2);
        let val = f_in.first; f_in.deq;

        if(rg_write_bank == 0) i_buf0[rg_write_idx] <= val;
        else                    i_buf1[rg_write_idx] <= val;

        if(rg_write_idx == 63) begin
            rg_write_idx    <= 0;
            rg_write_bank   <= ~rg_write_bank;
            rg_blocks_written <= rg_blocks_written + 1;
        end else begin
            rg_write_idx    <= rg_write_idx + 1;
        end
    endrule

    rule r_read_out (blocks_rdy > 0);
        Integer read_idx = zigzag_map[rg_read_idx];

        Int#(bits) val = (rg_read_bank == 0) ? i_buf0[read_idx] : i_buf1[read_idx];
        f_out.enq(val);

        if(rg_read_idx == 63) begin
            rg_read_idx     <= 0;
            rg_read_bank    <= ~rg_read_bank;
            rg_blocks_read  <= rg_blocks_read + 1;
        end else begin
            rg_read_idx     <= rg_read_idx + 1;
        end
    endrule

    interface data = toGPServer(f_in, f_out);

endmodule

//this is essentially the same module but it uses mkRegFile to infer LUTRAMs
module mkZigZag_Opt#(Bool buffer_in, Bool transposed)(Zigzag_ifc#(bits))
    provisos(
        Bits#(Int#(bits), _sz)
    );

    FIFO#(Int#(bits)) f_in;
    FIFO#(Int#(bits)) f_out <- mkFIFO;

    if(buffer_in)
        f_in <- mkFIFO;
    else
        f_in <- mkBypassFIFO;

    //ping-pong buffer using RegFile to infer LUTRAMs
    RegFile#(Bit#(6), Int#(bits)) i_buf0 <- mkRegFileWCF(0, 63);
    RegFile#(Bit#(6), Int#(bits)) i_buf1 <- mkRegFileWCF(0, 63);

    Reg#(Bit#(6)) rg_write_idx <- mkReg(0);
    Reg#(Bit#(6)) rg_read_idx  <- mkReg(0);

    //state
    Reg#(Bit#(1)) rg_write_bank <- mkReg(0);
    Reg#(Bit#(1)) rg_read_bank  <- mkReg(0);

    //prevent under or overflow
    Reg#(Bit#(2)) rg_blocks_rdy    <- mkReg(0);
    PulseWire     pw_block_written <- mkPulseWire;
    PulseWire     pw_block_read    <- mkPulseWire;

    function Bit#(6) to_bit6(Integer x) = fromInteger(x);
    Vector#(64, Bit#(6)) zigzag_map = map(to_bit6, zigzag_indices(transposed));

    rule r_update_blocks (pw_block_written || pw_block_read);
        rg_blocks_rdy <= rg_blocks_rdy + (pw_block_written ? 1 : 0) - (pw_block_read ? 1 : 0);
    endrule

    rule r_write_in (rg_blocks_rdy < 2);
        let val = f_in.first; f_in.deq;

        if(rg_write_bank == 0) i_buf0.upd(rg_write_idx, val);
        else                    i_buf1.upd(rg_write_idx, val);

        if(rg_write_idx == 63) begin
            rg_write_idx    <= 0;
            rg_write_bank   <= ~rg_write_bank;
            pw_block_written.send();
        end else begin
            rg_write_idx    <= rg_write_idx + 1;
        end
    endrule

    rule r_read_out (rg_blocks_rdy > 0);
        Bit#(6) read_idx = zigzag_map[rg_read_idx];

        Int#(bits) val = (rg_read_bank == 0) ? i_buf0.sub(read_idx) : i_buf1.sub(read_idx);
        f_out.enq(val);

        if(rg_read_idx == 63) begin
            rg_read_idx     <= 0;
            rg_read_bank    <= ~rg_read_bank;
            pw_block_read.send();
        end else begin
            rg_read_idx     <= rg_read_idx + 1;
        end
    endrule

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage
