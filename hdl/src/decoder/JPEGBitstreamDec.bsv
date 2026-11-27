package JPEGBitstreamDec;

import FIFOF :: *;
import Vector :: *;
import GetPut :: *;

import DecoderTypes :: *;

interface JPEGBitstreamDec_ifc;
    interface Put#(EcsToken_t) ecs;

    //MSB-aligned bit window, valid once ready
    method Bit#(48) window;
    method Bool     ready;

    method Action consume(UInt#(6) n);
    method Action drain();
    method Bool   draining;
endinterface

/*
 * Bit reader, the inverse of the encoder's JPEGBitstream. rg_win holds
 * rg_cnt valid bits MSB first, the bits below are don't care. ready means 27
 * valid bits, the longest code (16) plus the longest magnitude (11).
 *
 * A cycle either consumes or refills, never both. consume shifts the window
 * by a bit count the consumer holds in a register. Every
 * other cycle inserts up to two bytes from a prefetch register below the
 * valid bits, at positions that depend only on registers. The Huffman decoder
 * never consumes in its lookahead cycle, so up to two bytes per symbol arrive
 * there.
 *
 * After the End token of a segment the window is padded with ones (T.81
 * F.2.2.5). The prefetch register then holds 0xFF bytes, so the refill
 * datapath is the same with and without padding. drain drops the window and
 * any segment bytes up to End, so the next scan starts clean.
 */
module mkJPEGBitstreamDec(JPEGBitstreamDec_ifc);

    FIFOF#(EcsToken_t) f_in <- mkFIFOF;

    Reg#(Bit#(48)) rg_win   <- mkReg(0);
    Reg#(UInt#(6)) rg_cnt   <- mkReg(0);
    Reg#(UInt#(6)) rg_pos   <- mkReg(40);
    Reg#(Bool)     rg_pad   <- mkReg(False);
    Reg#(Bool)     rg_drain <- mkReg(False);

    //prefetched segment bytes, rg_pre[0] is the older one
    Vector#(2, Reg#(Maybe#(Bit#(8)))) rg_pre <- replicateM(mkReg(tagged Invalid));

    RWire#(UInt#(6)) w_consume <- mkRWire;
    PulseWire        pw_drain  <- mkPulseWire;

    //drop segment bytes up to the End token
    rule r_drain (rg_drain);
        let t = f_in.first; f_in.deq;
        if(t matches tagged End) rg_drain <= False;
    endrule

    rule r_update (!rg_drain);
        Bit#(48)                    win = rg_win;
        UInt#(6)                    cnt = rg_cnt;
        Bool                        pad = rg_pad;
        Vector#(2, Maybe#(Bit#(8))) pre = readVReg(rg_pre);

        if(pw_drain) begin
            //once End was seen the segment is already consumed
            rg_drain <= !rg_pad;
            win = 0;
            cnt = 0;
            pad = False;
            pre = replicate(tagged Invalid);
        end else begin
            if(w_consume.wget matches tagged Valid .used) begin
                win = win << used;
                cnt = cnt - used;
            end else begin
                //bytes come from the prefetch register, which holds ones after End
                Bit#(8) b0 = fromMaybe(0, pre[0]);
                Bit#(8) b1 = fromMaybe(0, pre[1]);
                Bool    v0 = isValid(pre[0]);
                Bool    v1 = isValid(pre[1]);
                //rg_pos tracks 40 - rg_cnt so the insert shifts start from a register
                if(v0 && rg_cnt <= 40) begin
                    win = win | (zeroExtend(b0) << rg_pos);
                    if(v1 && rg_cnt <= 32) begin
                        win = win | (zeroExtend(b1) << (rg_pos - 8));
                        cnt = cnt + 16;
                        pre = replicate(tagged Invalid);
                    end else begin
                        cnt = cnt + 8;
                        pre[0] = pre[1];
                        pre[1] = tagged Invalid;
                    end
                end
            end

            //prefetch one segment byte per cycle into a free slot
            if(!rg_pad && f_in.notEmpty && !isValid(pre[1])) begin
                case(f_in.first) matches
                    tagged Byte .b: begin
                        f_in.deq;
                        if(isValid(pre[0])) pre[1] = tagged Valid b;
                        else                pre[0] = tagged Valid b;
                    end
                    tagged End: begin
                        //End only takes effect once the prefetched bytes are in the window
                        if(!isValid(pre[0])) begin
                            f_in.deq;
                            pad = True;
                        end
                    end
                endcase
            end

            //after End both slots refill with ones every cycle
            if(pad) pre = replicate(tagged Valid 'hFF);
        end

        rg_win <= win;
        rg_cnt <= cnt;
        rg_pos <= 40 - cnt;
        rg_pad <= pad;
        writeVReg(rg_pre, pre);
    endrule

    interface ecs = toPut(f_in);

    method window = rg_win;
    method ready  = rg_cnt >= 27 && !rg_drain;

    method Action consume(UInt#(6) n);
        w_consume.wset(n);
    endmethod

    method drain    = pw_drain.send;
    method draining = rg_drain;

endmodule

endpackage
