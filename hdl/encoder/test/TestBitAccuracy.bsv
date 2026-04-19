package TestBitAccuracy;

import FIFO :: *;
import Clocks :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import ClientServer :: *;

import BDPI :: *;
import Util :: *;
import Types :: *;
import DUProc :: *;
import PrintUtil :: *;
import TestHelper :: *;
import TableStorage :: *;

import "BDPI" function ActionValue#(Bit#(1024)) mcu_proc_ref(Bit#(1024) input_flat, Bool luma_not_chroma);

typedef 16 DPw;

//
// Bit-accuracy regression test.
//
// Feeds pixel blocks through the HW DUProc pipeline (DCT→Quant→Zigzag)
// and through the C++ bit-accurate model (mcu_proc_ref, which uses the
// shared fixedpoint:: kernels from jpeg_fixed_point.hpp).
//
// Asserts **exact** match (max_diff == 0) for every coefficient.
// Tests both Luma and Chroma paths, with random and deterministic data.
//

module [Module] mkTestBitAccuracy(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    // --- Clock setup (matches HW instantiation) ---
    Clock fast_clock <- mkAbsoluteClock(100, 50);
    Reset fast_reset <- mkAsyncResetFromCR(2, fast_clock);

    Clock slow_clock <- mkAbsoluteClock(100, 400);
    Reset slow_reset <- mkAsyncResetFromCR(2, slow_clock);

    NumProxy#(12) dct_scale   = ?;
    NumProxy#(12) quant_scale = ?;

    let dut_cfg = DUProcCfg {
        slow_clock       : slow_clock,
        slow_reset       : slow_reset,
        buffer_in        : True,
        _dct_scale       : dct_scale,
        scale_in_dct     : False,
        transpose_in_dct : False,
        _q_scale         : quant_scale,
        debug            : False
    };

    DUProc_t#(DPw) dut <- mkDUProc(dut_cfg, clocked_by fast_clock, reset_by fast_reset);
    TableStorage_ifc#(12) tables <- mkTableStorage(quant_scale, True, clocked_by fast_clock, reset_by fast_reset);

    // --- Synchronization ---
    SyncPulseIfc        pStart      <- mkSyncPulseFromCC(fast_clock);
    SyncPulseIfc        pStopped    <- mkSyncPulseToCC(fast_clock, fast_reset);
    SyncBitIfc#(Bool)   syncStarted <- mkSyncBitToCC(fast_clock, fast_reset);

    // --- Counters and state ---
    Reg#(Bit#(32)) rg_test_num  <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(32)) rg_errors    <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(32)) rg_total     <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);

    Reg#(Bit#(7)) rg_count_in   <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(7)) rg_count_out  <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);

    Reg#(Vector#(64, Int#(DPw))) rg_mcu_in   <- mkRegU(clocked_by fast_clock, reset_by fast_reset);
    Reg#(Vector#(64, Int#(DPw))) rg_mcu_out  <- mkRegU(clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(1024))             rg_input_flat <- mkRegU(clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bool)                   rg_is_luma   <- mkReg(True, clocked_by fast_clock, reset_by fast_reset);

    mkConnection(dut.qtable, tables.quant_scaled);

    // Run one block through HW + reference and compare
    function Stmt test_one_block(Bool is_luma);
        return seq
            action
                dut.du_mode.put(is_luma ? Luma : Chroma);
                rg_is_luma <= is_luma;
            endaction

            // Generate random block data
            action
                Vector#(64, Int#(DPw)) block_1d = newVector;
                Vector#(64, Int#(16)) ref_input = newVector;
                for (Integer i = 0; i < 64; i = i + 1) begin
                    let pix <- rand_pix();
                    Int#(16) pix_i16 = unpack(zeroExtend(pack(pix)));
                    block_1d[i] = truncate(pix_i16);
                    ref_input[i] = pix_i16;
                end
                rg_mcu_in    <= block_1d;
                rg_input_flat <= pack(ref_input);
            endaction

            rg_count_in  <= 0;
            rg_count_out <= 0;

            // Feed HW and collect results in parallel
            par
                while (rg_count_in < 64) action
                    dut.data.request.put(rg_mcu_in[rg_count_in]);
                    rg_count_in <= rg_count_in + 1;
                endaction
                while (rg_count_out < 64) action
                    let res <- dut.data.response.get();
                    let mcu = rg_mcu_out;
                    mcu[rg_count_out] = res;
                    rg_mcu_out <= mcu;
                    rg_count_out <= rg_count_out + 1;
                endaction
            endpar

            // Compare HW output vs C++ reference (bitwise exact)
            action
                let ref_packed <- mcu_proc_ref(rg_input_flat, rg_is_luma);
                Vector#(64, Int#(16)) ref_out = unpack(ref_packed);

                // Compute max absolute difference
                Int#(DPw) max_diff = 0;
                Bit#(32) mismatch_count = 0;
                for (Integer i = 0; i < 64; i = i + 1) begin
                    Int#(DPw) hw_val  = rg_mcu_out[i];
                    Int#(DPw) ref_val = truncate(ref_out[i]);
                    Int#(DPw) diff = (hw_val > ref_val) ? hw_val - ref_val : ref_val - hw_val;
                    if (diff > max_diff) max_diff = diff;
                    if (diff != 0) mismatch_count = mismatch_count + 1;
                end

                String comp_str = rg_is_luma ? "Luma" : "Chroma";

                if (max_diff == 0) begin
                    print_fmt($format("Test %0d PASS (bitwise exact)", rg_test_num), GREEN);
                end else begin
                    print_fmt($format("Test %0d FAIL max_diff=%0d mismatches=%0d/64",
                        rg_test_num, max_diff, mismatch_count), RED);

                    // Print first few mismatching coefficients for debugging
                    for (Integer i = 0; i < 64; i = i + 1) begin
                        Int#(DPw) hw_v  = rg_mcu_out[i];
                        Int#(DPw) ref_v = truncate(ref_out[i]);
                        if (hw_v != ref_v)
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
        syncStarted.send(True);
        await(tables.ready);
        print_s("=== Bit-Accuracy Regression Test ===", WHITE);
        print_fmt($format("Running %0d random blocks per component (Luma + Chroma)", num_random_tests), WHITE);

        // --- Luma random blocks ---
        rg_iter <= 0;
        while (rg_iter < fromInteger(num_random_tests)) seq
            test_one_block(True);
            rg_iter <= rg_iter + 1;
        endseq

        // --- Chroma random blocks ---
        rg_iter <= 0;
        while (rg_iter < fromInteger(num_random_tests)) seq
            test_one_block(False);
            rg_iter <= rg_iter + 1;
        endseq

        // --- Summary ---
        action
            if (rg_errors == 0)
                print_fmt($format("=== ALL %0d TESTS PASSED (bitwise exact) ===", rg_total), GREEN);
            else
                print_fmt($format("=== FAILED: %0d/%0d tests had mismatches ===", rg_errors, rg_total), RED);
        endaction
    endseq;

    FSM f <- mkFSM(main_test, clocked_by fast_clock, reset_by fast_reset);

    rule start if (pStart.pulse());
        f.start();
    endrule

    rule stopped if (f.done());
        pStopped.send();
    endrule

    method go   = pStart.send;
    method done = pStopped.pulse && syncStarted.read;

endmodule

endpackage
