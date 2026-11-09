package Util;

import BRAM :: *;
import GetPut :: *;
import Vector :: *;
import Gearbox :: *;
import BuildVector :: *;

import BDPI :: *;
import Types :: *;
import PrintUtil :: *;

function ReadOnly#(t) reg_to_read_only(Reg#(t) r) = regToReadOnly(r);

interface ClearOnRead_ifc#(type t);
    method ActionValue#(t) _read();
endinterface

function ClearOnRead_ifc#(t) reg_to_clear_on_read(Reg#(t) r)
    provisos(
        Bits#(t, _sz),
        Literal#(t)
    );
    return (interface ClearOnRead_ifc
        method _read = actionvalue
            r <= 0;
            return r._read;
        endactionvalue;
    endinterface);
endfunction

function WriteOnly#(a) reg_to_write_only(Reg#(a) r);
    return (interface WriteOnly
        method _write = r._write;
    endinterface);
endfunction

function Bool is_power_of_2(Integer v);
    Bit#(64) x = fromInteger(v);
    return (x > 0) && ((x & (x-1)) == 0);
endfunction

function Action write_to_bram(BRAMServer#(addr, data) bram_port, addr a, data d);
    action
        BRAMRequest#(addr, data) req = BRAMRequest {
            write: True,
            responseOnWrite: False,
            address: a,
            datain: d
        };
        bram_port.request.put(req);
    endaction
endfunction

function Action read_req_to_bram(BRAMServer#(addr, data) bram_port, addr a);
    action
        BRAMRequest#(addr, data) req = BRAMRequest {
            write: False,
            responseOnWrite: ?,
            address: a,
            datain: ?
        };
        bram_port.request.put(req);
    endaction
endfunction

function ActionValue#(UInt#(8)) rand_pix() = actionvalue
    let v <- rand_i16(0, 255);
    return truncate(unpack(v));
endactionvalue;

/*
* Intended for testbenches. Transposes the given mcu and returns the transposed result.
*/
function DU_t#(t, h, w) transpose_mcu(DU_t#(t, w, h) mcu);
    DU_t#(t, h, w) transposed = DU_t { block: newVector };
    for(Integer y=0; y<valueof(h); y=y+1) begin
        for(Integer x=0; x<valueof(w); x=x+1) begin
            transposed.block[x][y] = mcu.block[y][x];
        end
    end
    return transposed;
endfunction

/*
* This function multiplies an integer of `bits` length with a compile-time
* constant Integer that was scaled by 2^`bits_frac`. The constant is stored as
* signed Q1.bits_frac, so values in [-2, 2) keep their integer bit instead of
* truncating into the fractional field.
*/
function Int#(bits) scaled_mul_s(Bool sat, Bool round, NumProxy_t#(bits_frac) _proxy, Int#(bits) val, Integer f)
    provisos(
        Add#(bits_frac, 2, coeff_bits),
        Add#(bits, coeff_bits, bits_mul)
    );
    Int#(coeff_bits) f_const = fromInteger(f);
    Int#(bits_mul)   prod    = signedMul(val, f_const);

    //rounding: add 2^(bits_frac-1) before shifting
    Int#(bits_mul) prod_m = ?;
    if(round) begin
        //saturation only important when rounding is applied
        if(sat)
            prod_m = satPlus(Sat_Bound, prod, (1 << fromInteger(valueOf(bits_frac) - 1)));
        else
            prod_m = prod + (1 << fromInteger(valueOf(bits_frac) - 1));
    end else begin
        prod_m = prod;
    end

    return truncate(prod_m >> valueOf(bits_frac));
endfunction

/*
* Runtime variant: multiplies Int#(bits) by a runtime Int#(bits_frac) multiplier
* that was pre-scaled by 2^bits_frac. Rounds and removes the scaling factor.
*/
function Int#(bits) scaled_mul_rt(Bool sat, Bool round, NumProxy_t#(bits_frac) _proxy, Int#(bits) val, Int#(bits_frac) f)
    provisos(
        Add#(bits_frac, 2, coeff_bits),
        Add#(bits, coeff_bits, bits_mul)
    );
    Int#(coeff_bits) f_const = signExtend(f);
    Int#(bits_mul)   prod    = signedMul(val, f_const);

    //rounding: add 2^(bits_frac-1) before shifting
    Int#(bits_mul) prod_m = ?;
    if(round) begin
        //saturation only important when rounding is applied
        if(sat)
            prod_m = satPlus(Sat_Bound, prod, (1 << fromInteger(valueOf(bits_frac) - 1)));
        else
            prod_m = prod + (1 << fromInteger(valueOf(bits_frac) - 1));
    end else begin
        prod_m = prod;
    end
    return truncate(prod_m >> valueOf(bits_frac));
endfunction

//fast input gearbox Put instance
function Put#(t) gearbox_fast_put(Gearbox#(1, out, t) gearb);
    return interface Put;
        method Action put(t v) = gearb.enq(vec(v));
    endinterface;
endfunction

//slow input gearbox Put instance
function Put#(Vector#(in, t)) gearbox_slow_put(Gearbox#(in, out, t) gearb);
    return interface Put;
        method put = gearb.enq;
    endinterface;
endfunction

//fast output gearbox Get instance
function Get#(t) gearbox_fast_get(Gearbox#(in, 1, t) gearb);
    return interface Get;
        method get = actionvalue
            gearb.deq;
            return gearb.first[0];
        endactionvalue;
    endinterface;
endfunction

//slow output gearbox Get instance
function Get#(Vector#(out, t)) gearbox_slow_get(Gearbox#(in, out, t) gearb);
    return interface Get;
        method get = actionvalue
            gearb.deq;
            return gearb.first;
        endactionvalue;
    endinterface;
endfunction

function ActionValue#(Bit#(w1)) clz_pow2(Bit#(w) value)
    provisos(
        //these provisos will ensure the input has a width with power of 2
        //and simultaneously set the output counter width
        Log#(w, _a),
        Add#(TExp#(_a), 0, w),
        Add#(_a, 1, w1)
    );
    actionvalue
    Bit#(w1) result = 0;
    if(value != 0) begin
        for(Integer i = valueof(w1) - 2; i >= 0; i = i - 1) begin
            Integer b            = 2**(i+1)-1;
            Integer a            = 2**i;
            Bit#(w) intermediate = value[2**(i+1)-1:2**i];
            if(intermediate == 0) begin
                result[i] = 1;
            end else begin
                value = intermediate; //value >> 2**i;
            end
        end
    end else
        result = fromInteger(valueof(w));
    return result;
    endactionvalue
endfunction

function ActionValue#(Bit#(w1)) clz_gen(Bit#(w) value)
    provisos(
        Log#(w, _a),                    //ceil(log2(w)) = _a
        Add#(w, _b, TExp#(_a)),         //exp2(_a) = w + _b
        Add#(w, _b, new_width),         //new_width = w + _b
        Log#(new_width, _c),            //ceil(log2(new_width)) = _c
        Add#(TExp#(_c), 0, new_width),  //exp2(_c) = new_width
        Add#(_c, 1, w1)                 //w1 = _c + 1
    );
    //NOTE: for widths that are not a power of 2,
    //the output width is 1 too large as the input
    //gets extended to the next highest power of 2
    actionvalue
        Bit#(w1) res = 0;
        if(value != 0) begin
            Bit#(new_width) val = extend(value) << fromInteger(valueof(_b));
            res <- clz_pow2(val);
        end else begin
            res = fromInteger(valueof(w));
        end
        return res;
    endactionvalue
endfunction

function ActionValue#(Bit#(w1)) flog2(Bit#(w) x)
    provisos(
        Add#(w, a__, TExp#(TLog#(w))),
        Add#(TLog#(w), 1, w1)
    );
    actionvalue
        let      lz  <- clz_gen(x);
        Bit#(w1) res = fromInteger(valueof(w)) - lz - 1;
        return res;
    endactionvalue
endfunction

function Action print_du(DU_t#(t, w, h) mcu, String name, TermColor c)
    provisos(
        FShow#(t)
    );
    action
        print_mod_pre_color_t_s(name, c);
        for(Integer y=0; y<valueof(h); y=y+1) begin
            Fmt line = $format("");
            for(Integer x=0; x<valueof(w); x=x+1) begin
                line = line + fshow(mcu.block[y][x]) + $format("\t");
            end
            print_mod_pre_color_t_f(line, c);
        end
    endaction
endfunction

function Get#(t) guard_get(Get#(t) source, Bool cond);
    return (interface Get;
        method get if(cond) = source.get;
    endinterface);
endfunction

function Put#(t) guard_put(Put#(t) sink, Bool cond);
    return (interface Put;
        method put if(cond) = sink.put;
    endinterface);
endfunction

function Put#(t) expand_put(Put#(t) sink, Action a);
    return (interface Put;
        method Action put(t x);
            sink.put(x);
            a;
        endmethod
    endinterface);
endfunction

endpackage