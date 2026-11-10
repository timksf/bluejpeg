package TestDCT1D;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import BuildVector :: *;
import ClientServer :: *;

import BDPI :: *;
import EncoderUtil :: *;
import DCT1D :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;

function ActionValue#(Bit#(64)) dct_1d_i8_ref(Bit#(64) in, Bool scale) = actionvalue
    Bit#(65) in_padded = {1'b0, in};
    let v <- dct_1d_i8_ref_raw(in_padded, scale);
    return v[63:0];
endactionvalue;

function UInt#(32) sum_abs_error(
    Vector#(8, Int#(16)) reference,
    Vector#(8, Int#(16)) actual
);
    UInt#(32) total = 0;
    for(Integer i = 0; i < 8; i = i + 1) begin
        Int#(17)  delta     = signExtend(actual[i]) - signExtend(reference[i]);
        UInt#(17) magnitude = unpack(pack(delta < 0 ? -delta : delta));
        total = total + zeroExtend(magnitude);
    end
    return total;
endfunction

module [Module] mkTestDCT1D(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    NumProxy_t#(12) f_scale = ?;
    DCT1D_ifc#(16)  dut     <- mkDCT1D_rigid(f_scale, True, False);

    Reg#(Bit#(32))  rg_sent     <- mkReg(0);
    Reg#(Bit#(32))  rg_counter  <- mkReg(0);
    Reg#(UInt#(32)) rg_errors   <- mkReg(0);
    Reg#(UInt#(8))  rg_watchdog <- mkReg(0);
    Reg#(Bool)      rg_started  <- mkReg(False);
    Reg#(Bool)      rg_timeout  <- mkReg(False);

    FIFO#(Vector#(8, Int#(16))) f_tv <- mkSizedFIFO(8);

    Stmt test_seq = seq
        while(rg_sent < 8) seq
            action
                Vector#(8, Int#(16)) row = newVector;

                for(Integer i=0; i<8; i=i+1) begin
                    let pix <- rand_pix();
                    Int#(16) pix_i16 = unpack(zeroExtend(pack(pix)));
                    row[i] = truncate(pix_i16 - 128);
                end

                print_fmt($format("ROW ") + fshow(row), CYAN);
                dut.data.request.put(row);
                f_tv.enq(row);
                rg_sent <= rg_sent + 1;
            endaction
        endseq

        delay(20); //fill the pipeline and apply output backpressure

        while(rg_counter < 8) action
            let input_row = f_tv.first; f_tv.deq;
            Vector#(8, Int#(16)) ext_row = map(signExtend, input_row);
            let ref_out_packed <- dct_1d_i16_ref(pack(ext_row), True);
            Vector#(8, Int#(16)) ref_wide = unpack(ref_out_packed);
            Vector#(8, Int#(16)) ref_out  = map(truncate, ref_wide);

            let res         <- dut.data.response.get();
            let row_error   = sum_abs_error(ref_out, res);
            let total_error = rg_errors + row_error;

            print_fmt($format("REF ") + fshow(ref_out), GREEN);
            print_fmt($format("RES ") + fshow(res) +
                $format(" SAE %0d CUM_SAE %0d", row_error, total_error), GREEN);

            rg_errors <= total_error;
            rg_counter <= rg_counter + 1;
        endaction

        print_fmt($format("DCT1D cumulative SAE: %0d", rg_errors), GREEN);
    endseq;

    FSM i_test_fsm <- mkFSM(test_seq);

    rule r_watchdog (rg_started && !i_test_fsm.done && !rg_timeout);
        if(rg_watchdog == 100) begin
            print_fmt($format("ERROR: DCT1D timeout after receiving %0d of %0d results, cumulative SAE %0d",
                rg_counter, rg_sent, rg_errors), RED);
            rg_timeout <= True;
        end else begin
            rg_watchdog <= rg_watchdog + 1;
        end
    endrule

    method Action go();
        rg_started <= True;
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done() || rg_timeout;
    endmethod

endmodule

endpackage
