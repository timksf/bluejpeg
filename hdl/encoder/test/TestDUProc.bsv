package TestDUProc;

import FIFO :: *;
import Clocks :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import BuildVector :: *;
import ClientServer :: *;

import BDPI :: *;
import Util :: *;
import Types :: *;
import DUProc :: *;
import PrintUtil :: *;
import TestHelper :: *;
import TableStorage :: *;

import "BDPI" function ActionValue#(Bit#(1024)) mcu_proc_ref(Bit#(1024) input_flat, Bool luma_not_chroma, Bool optimized_dct);

typedef 8  PixelWidth;
typedef 14 DCTWidth;

module [Module] mkTestDUProc(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    Clock fast_clock <- mkAbsoluteClock(100, 50);
    Reset fast_reset <- mkAsyncResetFromCR(2, fast_clock);

    Clock slow_clock <- mkAbsoluteClock(100, 400);
    Reset slow_reset <- mkAsyncResetFromCR(2, slow_clock);

    NumProxy#(12) dct_scale     = ?;
    NumProxy#(12) quant_scale   = ?;

    let dut_cfg = DUProcCfg {
        slow_clock       : slow_clock,
        slow_reset       : slow_reset,
        buffer_in        : True,
        _dct_scale       : dct_scale,
        scale_in_dct     : False,
        transpose_in_dct : False,
        _q_scale         : quant_scale,
        debug            : True,
        dct_safe_arith   : False
    };

    DUProcLegacy_t#(PixelWidth, DCTWidth) dut <- mkDUProc(dut_cfg, clocked_by fast_clock, reset_by fast_reset);
    TableStorage_ifc#(12) tables <- mkTableStorage(quant_scale, True, clocked_by fast_clock, reset_by fast_reset);

    //synchronization of FSM start and stop
    Bool                verbose         = False;
    SyncPulseIfc        pStart          <- mkSyncPulseFromCC(fast_clock);
    SyncPulseIfc        pStopped        <- mkSyncPulseToCC(fast_clock, fast_reset);
    SyncBitIfc#(Bool)   syncStarted     <- mkSyncBitToCC(fast_clock, fast_reset);

    Reg#(Bit#(32)) rg_counter <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(32)) rg_errors  <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);

    Reg#(Bit#(7)) rg_count_in  <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(7)) rg_count_out <- mkReg(0, clocked_by fast_clock, reset_by fast_reset);

    Reg#(Vector#(64, UInt#(PixelWidth))) rg_mcu_in  <- mkRegU(clocked_by fast_clock, reset_by fast_reset);
    Reg#(Vector#(64, Int#(DCTWidth)))    rg_mcu_out <- mkRegU(clocked_by fast_clock, reset_by fast_reset);
    Reg#(Bit#(1024))            input_flat <- mkRegU(clocked_by fast_clock, reset_by fast_reset);

    mkConnection(dut.qtable, tables.quant_scaled);

    Stmt s = seq
        syncStarted.send(True);
        await(tables.ready);
        while(rg_counter < 10) seq
            dut.du_mode.put(Luma);
            action
                Vector#(64, UInt#(PixelWidth)) block_1d = newVector;
                Vector#(64, Int#(16)) ref_input = newVector;

                // block_1d = vec(
                //     110,  101,  120,  126,  213,  182,   99,  114,
                //     117,  115,  113,  108,  102,  249,  164,   91,
                //     112,   93,   98,  123,   93,  119,  248,  162,
                //     100,  122,  111,  101,  123,  120,  140,  246,
                //     105,  102,  116,   96,  110,  104,  103,  151,
                //     115,  113,  113,  124,  106,   99,  106,  116,
                //     106,  118,  100,   98,  111,  100,  118,  107,
                //     115,   94,  120,  106,  107,  107,  109,  106
                // );

                // ref_input = vec(
                //     110,  101,  120,  126,  213,  182,   99,  114,
                //     117,  115,  113,  108,  102,  249,  164,   91,
                //     112,   93,   98,  123,   93,  119,  248,  162,
                //     100,  122,  111,  101,  123,  120,  140,  246,
                //     105,  102,  116,   96,  110,  104,  103,  151,
                //     115,  113,  113,  124,  106,   99,  106,  116,
                //     106,  118,  100,   98,  111,  100,  118,  107,
                //     115,   94,  120,  106,  107,  107,  109,  106
                // );

                for(Integer i=0; i<64; i=i+1) begin
                    let pix <- rand_pix();

                    Int#(16) pix_i16    = unpack(zeroExtend(pack(pix)));
                    block_1d[i]         = truncate(pix);
                    ref_input[i]        = pix_i16;
                end
                
                rg_mcu_in   <= block_1d;
                input_flat  <= pack(ref_input);
            endaction
            
            rg_count_in <= 0;
            rg_count_out <= 0;
            
            par
                while(rg_count_in < 64) action
                    dut.data.request.put(rg_mcu_in[rg_count_in]);
                    rg_count_in <= rg_count_in + 1;
                endaction
                while(rg_count_out < 64) action
                    let res <- dut.data.response.get();
                    let mcu_out = rg_mcu_out;
                    mcu_out[rg_count_out] = res;
                    rg_mcu_out      <= mcu_out;
                    rg_count_out    <= rg_count_out + 1;
                endaction
            endpar
            
            //calculate reference and compare
            action
                let ref_out_packed <- mcu_proc_ref(input_flat, True, !dut_cfg.dct_safe_arith);
                Vector#(64, Int#(16)) ref_out = unpack(ref_out_packed);
                
                function Int#(DCTWidth) calc_diff(Integer i);
                    Int#(DCTWidth) hw_val     = rg_mcu_out[i];
                    Int#(DCTWidth) ref_val    = truncate(ref_out[i]);
                    return (hw_val > ref_val) ? hw_val - ref_val : ref_val - hw_val;
                endfunction
                Vector#(64, Int#(DCTWidth)) diffs = genWith(calc_diff);
                function Int#(DCTWidth) max_func(Int#(DCTWidth) a, Int#(DCTWidth) b) = (a > b) ? a : b;
                Int#(DCTWidth) max_diff = fold(max_func, diffs);

                print_mod_pre_color_t_f($format("Test %0d, max error: %0d", rg_counter, max_diff), WHITE);
                
                if (max_diff > 5 || verbose) begin
                    Vector#(8, Vector#(8, UInt#(PixelWidth))) blk_in = newVector;
                    for (Integer r = 0; r < 8; r = r + 1) begin
                        for (Integer c = 0; c < 8; c = c + 1) begin
                            blk_in[r][c] = rg_mcu_in[r * 8 + c];
                        end
                    end

                    Vector#(64, Int#(DCTWidth)) ref_out_dct = map(truncate, ref_out);
                    print_du(DU_t { block: blk_in }, "Input MCU", BLUE);
                    print_fmt($format("Reference : ") + fshow(ref_out_dct), CYAN);
                    print_fmt($format("DUT Output: ") + fshow(rg_mcu_out), YELLOW);
                end
                
                if (max_diff > 20) begin
                    print_fmt($format("Error>20 at iteration %d", rg_counter), RED);
                    rg_errors <= rg_errors + 1;
                end
            endaction
            rg_counter <= rg_counter + 1;
        endseq
        
        if (rg_errors == 0) print_s("PASSED", GREEN);
        else print_fmt($format("FAILED with %d errors", rg_errors), RED);
    endseq;

    FSM f <- mkFSM(s, clocked_by fast_clock, reset_by fast_reset);

    rule start if(pStart.pulse());
        f.start();
    endrule

    rule stopped if(f.done());
        pStopped.send();
    endrule

    method go   = pStart.send;
    method done = pStopped.pulse && syncStarted.read;

endmodule

endpackage
