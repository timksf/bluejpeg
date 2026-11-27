package TestBitAccuracy;

import FIFO :: *;
import Clocks :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import ClientServer :: *;

import BDPI :: *;
import EncoderUtil :: *;
import Types :: *;
import DUProc :: *;
import PrintUtil :: *;
import TestHelper :: *;
import TableStorage :: *;

import "BDPI" function ActionValue#(Bit#(1024)) mcu_proc_ref(Bit#(1024) input_flat, Bool luma_not_chroma, Bool optimized_dct);

typedef 8  PixelWidth;
typedef 16 DCTWidth;

//
//bit-accuracy regression test
//
//feeds pixel blocks through the HW DUProc pipeline (DCT->Quant->Zigzag)
//and through the C++ bit-accurate model (mcu_proc_ref, which uses the
//shared jpeg_fixedpoint:: kernels from jpeg_fixed_point.hpp)
//
//asserts an exact match (max_diff == 0) for every coefficient
//tests both Luma and Chroma paths, with random and deterministic data
//

module [Module] mkTestBitAccuracy(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    //clock setup (matches HW instantiation)
    Clock fast_clock <- mkAbsoluteClock(100, 50);
    Reset fast_reset <- mkAsyncResetFromCR(2, fast_clock);

    Clock slow_clock <- mkAbsoluteClock(100, 400);
    Reset slow_reset <- mkAsyncResetFromCR(2, slow_clock);

    NumProxy_t#(12) dct_scale   = ?;
    NumProxy_t#(12) quant_scale = ?;

    let dut_cfg = DUProcCfg_t {
        slow_clock       : slow_clock,
        slow_reset       : slow_reset,
        buffer_in        : True,
        _dct_scale       : dct_scale,
        scale_in_dct     : False,
        transpose_in_dct : False,
        _q_scale         : quant_scale,
        debug            : False,
        dct_safe_arith   : False,
        shallow_dct      : False
    };

    DUProcLegacy_ifc#(PixelWidth, DCTWidth) dut      <- mkDUProc(dut_cfg, clocked_by fast_clock, reset_by fast_reset);
    TableStorage_ifc#(12)                   i_tables <- mkTableStorage(quant_scale, True, clocked_by fast_clock, reset_by fast_reset);

    //synchronization
    SyncPulseIfc      i_start        <- mkSyncPulseFromCC(fast_clock);
    SyncPulseIfc      i_stopped      <- mkSyncPulseToCC(fast_clock, fast_reset);
    SyncBitIfc#(Bool) i_sync_started <- mkSyncBitToCC(fast_clock, fast_reset);

    //counters and state
    Reg#(Bit#(32)) rg_test_num <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(32)) rg_errors   <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(32)) rg_total    <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);

    Reg#(Bit#(7)) rg_count_in  <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(7)) rg_count_out <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);

    Reg#(Vector#(64, UInt#(PixelWidth))) rg_mcu_in     <- mkRegU(clocked_by fast_clock, reset_by fast_reset);
    Reg#(Vector#(64, Int#(DCTWidth)))    rg_mcu_out    <- mkRegU(clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(1024))                     rg_input_flat <- mkRegU(clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bool)                           rg_is_luma    <- mkReg(True, clocked_by fast_clock, reset_by fast_reset);

    mkConnection(dut.qtable, i_tables.quant_scaled);

    //run one block through HW + reference and compare
    function Stmt test_one_block(Bool is_luma);
        return seq
            action
                dut.du_mode.put(is_luma ? Luma : Chroma);
                rg_is_luma <= is_luma;
            endaction

            //generate random block data
            action
                Vector#(64, UInt#(PixelWidth)) block_1d  = newVector;
                Vector#(64, Int#(16))          ref_input = newVector;
                for(Integer i = 0; i < 64; i = i + 1) begin
                    let pix <- rand_pix();
                    Int#(16) pix_i16 = unpack(zeroExtend(pack(pix)));
                    block_1d[i] = truncate(pix);
                    ref_input[i] = pix_i16;
                end
                rg_mcu_in    <= block_1d;
                rg_input_flat <= pack(ref_input);
            endaction

            rg_count_in  <= 0;
            rg_count_out <= 0;

            //feed HW and collect results in parallel
            par
                while(rg_count_in < 64) action
                    dut.data.request.put(rg_mcu_in[rg_count_in]);
                    rg_count_in <= rg_count_in + 1;
                endaction
                while(rg_count_out < 64) action
                    let res <- dut.data.response.get();
                    let mcu = rg_mcu_out;
                    mcu[rg_count_out] = res;
                    rg_mcu_out <= mcu;
                    rg_count_out <= rg_count_out + 1;
                endaction
            endpar

            //compare HW output vs C++ reference (bitwise exact)
            action
                let ref_packed <- mcu_proc_ref(rg_input_flat, rg_is_luma, !dut_cfg.dct_safe_arith);
                Vector#(64, Int#(16)) ref_out = unpack(ref_packed);

                //compute max absolute difference
                Int#(DCTWidth) max_diff       = 0;
                Bit#(32)       mismatch_count = 0;
                for(Integer i = 0; i < 64; i = i + 1) begin
                    Int#(DCTWidth) hw_val  = rg_mcu_out[i];
                    Int#(DCTWidth) ref_val = truncate(ref_out[i]);
                    Int#(DCTWidth) diff    = (hw_val > ref_val) ? hw_val - ref_val : ref_val - hw_val;
                    if(diff > max_diff) max_diff = diff;
                    if(diff != 0) mismatch_count = mismatch_count + 1;
                end

                String comp_str = rg_is_luma ? "Luma" : "Chroma";

                if(max_diff == 0) begin
                    print_fmt($format("Test %0d PASS (bitwise exact)", rg_test_num), GREEN);
                end else begin
                    print_fmt($format("Test %0d FAIL max_diff=%0d mismatches=%0d/64",
                        rg_test_num, max_diff, mismatch_count), RED);

                    //print first few mismatching coefficients for debugging
                    for(Integer i = 0; i < 64; i = i + 1) begin
                        Int#(DCTWidth) hw_v  = rg_mcu_out[i];
                        Int#(DCTWidth) ref_v = truncate(ref_out[i]);
                        if(hw_v != ref_v)
                            print_fmt($format("  [%0d] hw=%0d ref=%0d", i, hw_v, ref_v), YELLOW);
                    end

                    rg_errors <= rg_errors + 1;
                end

                rg_test_num <= rg_test_num + 1;
                rg_total <= rg_total + 1;
            endaction
        endseq;
    endfunction

    Integer num_random_tests = 50;

    Reg#(Bit#(32)) rg_iter <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);

    Stmt main_test = seq
        i_sync_started.send(True);
        await(i_tables.ready);
        print_s("=== Bit-Accuracy Regression Test ===", WHITE);
        print_fmt($format("Running %0d random blocks per component (Luma + Chroma)", num_random_tests), WHITE);

        //luma random blocks
        rg_iter <= 0;
        while(rg_iter < fromInteger(num_random_tests)) seq
            test_one_block(True);
            rg_iter <= rg_iter + 1;
        endseq

        //chroma random blocks
        rg_iter <= 0;
        while(rg_iter < fromInteger(num_random_tests)) seq
            test_one_block(False);
            rg_iter <= rg_iter + 1;
        endseq

        //summary
        action
            if(rg_errors == 0)
                print_fmt($format("=== ALL %0d TESTS PASSED (bitwise exact) ===", rg_total), GREEN);
            else
                print_fmt($format("ERROR: FAILED: %0d/%0d tests had mismatches ===", rg_errors, rg_total), RED);
        endaction
    endseq;

    FSM i_fsm <- mkFSM(main_test, clocked_by fast_clock, reset_by fast_reset);

    rule r_start (i_start.pulse());
        i_fsm.start();
    endrule

    rule r_stopped (i_fsm.done());
        i_stopped.send();
    endrule

    method go   = i_start.send;
    method done = i_stopped.pulse && i_sync_started.read;

endmodule

endpackage
