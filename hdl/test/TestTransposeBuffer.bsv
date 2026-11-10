package TestTransposeBuffer;

import StmtFSM :: *;
import ClientServer :: *;
import GetPut :: *;
import Connectable :: *;
import List :: *;
import Vector :: *;

import BDPI :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;
import SimRAM_AXI :: *;
import TransposeBuffer :: *;

module [Module] mkTestTransposeBuffer(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t1 <- mkTestCase;
    let t2 <- mkTestCaseOpt;

    Stmt s = seq
        print_s("Testing mkTransposeBuffer...", BLUE);
        t1.go();
        while(!t1.done()) action endaction
        print_s("Testing mkTransposeBufferOpt...", BLUE);
        t2.go();
        while(!t2.done()) action endaction
    endseq;

    FSM i_test_fsm <- mkFSM(s);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

module [Module] mkTestCase(TestHandler_ifc)
    provisos(
        NumAlias#(8, mcu_w),
        NumAlias#(8, mcu_h),
        Mul#(mcu_w, mcu_h, pixels_in_mcu)
    );

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    TransposeBuffer_ifc#(Int#(16), mcu_w, mcu_h) dut <- mkTransposeBuffer(False);

    Reg#(UInt#(32)) rg_iter      <- mkReg(0);
    Reg#(Bit#(32))  rg_count_in  <- mkReg(0);
    Reg#(Bit#(32))  rg_count_out <- mkReg(0);

    Reg#(DU_t#(Int#(16), mcu_w, mcu_h)) rg_input_mcu  <- mkRegU;
    Reg#(DU_t#(Int#(16), mcu_h, mcu_w)) rg_output_mcu <- mkRegU;

    Stmt s = seq
        while(rg_iter < 10) seq
            dut.rewind();
            action
                Vector#(mcu_h, Vector#(mcu_w, Int#(16))) block = newVector;
                for(Integer y=0; y<valueof(mcu_h); y=y+1) begin
                    for(Integer x=0; x<valueof(mcu_w); x=x+1) begin
                        let v <- rand_i16(0, 127);
                        block[y][x] = unpack(v);
                    end
                end
                rg_input_mcu <= DU_t { block: block };
            endaction

            action
                print_du(rg_input_mcu, "Input MCU", YELLOW);
            endaction

            rg_count_in <= 0;
            rg_count_out <= 0;

            par
                while(rg_count_in < fromInteger(valueof(pixels_in_mcu))) action
                    let x = rg_count_in % fromInteger(valueof(mcu_w));
                    let y = rg_count_in / fromInteger(valueof(mcu_w));
                    dut.original.put(rg_input_mcu.block[y][x]);
                    rg_count_in <= rg_count_in + 1;
                endaction
                while(rg_count_out < fromInteger(valueof(pixels_in_mcu))) action
                    let v <- dut.transposed.get();
                    let x = rg_count_out % fromInteger(valueof(mcu_h));
                    let y = rg_count_out / fromInteger(valueof(mcu_h));

                    let block = rg_output_mcu.block;
                    block[y][x] = v;
                    rg_output_mcu <= DU_t { block: block };

                    rg_count_out <= rg_count_out + 1;
                endaction
            endpar

            action
                Bool match_ = True;
                for(Integer x=0; x<valueof(mcu_w); x=x+1)
                    for(Integer y=0; y<valueof(mcu_h); y=y+1) begin
                        //check for transpose: Output[y][x] should equal Input[x][y]
                        if(rg_input_mcu.block[y][x] != rg_output_mcu.block[x][y]) match_ = False;
                    end

                print_du(rg_output_mcu, "Output MCU", CYAN);
                if(match_) print_s("Iteration Passed", GREEN);
                else begin
                    print_s("Iteration Failed", RED);
                end
            endaction

            rg_iter <= rg_iter + 1;
        endseq
        print_s("Finished all tests", BLUE);
    endseq;

    FSM i_test_fsm <- mkFSM(s);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

module [Module] mkTestCaseOpt(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    TransposeBufferOpt_ifc#(Int#(16)) dut <- mkTransposeBufferOpt;

    Reg#(UInt#(32)) rg_iter      <- mkReg(0);
    Reg#(Bit#(4))   rg_count_in  <- mkReg(0);
    Reg#(Bit#(4))   rg_count_out <- mkReg(0);

    Reg#(DU_t#(Int#(16), 8, 8)) rg_input_mcu  <- mkRegU;
    Reg#(DU_t#(Int#(16), 8, 8)) rg_output_mcu <- mkRegU;

    Stmt s = seq
        dut.rewind();
        while(rg_iter < 10) seq
            action
                Vector#(8, Vector#(8, Int#(16))) block = newVector;
                for(Integer y=0; y<8; y=y+1) begin
                    for(Integer x=0; x<8; x=x+1) begin
                        let v <- rand_i16(0, 127);
                        block[y][x] = unpack(v);
                    end
                end
                rg_input_mcu <= DU_t { block: block };
            endaction

            action
                print_du(rg_input_mcu, "Input MCU", YELLOW);
            endaction

            rg_count_in <= 0;
            rg_count_out <= 0;

            par
                while(rg_count_in < 8) action
                    dut.original.put(rg_input_mcu.block[rg_count_in]);
                    rg_count_in <= rg_count_in + 1;
                endaction
                while(rg_count_out < 8) action
                    let v     <- dut.transposed.get();
                    let block = rg_output_mcu.block;
                    block[rg_count_out] = v;
                    rg_output_mcu <= DU_t { block: block };

                    rg_count_out <= rg_count_out + 1;
                endaction
            endpar

            action
                Bool match_ = True;
                for(Integer x=0; x<8; x=x+1)
                    for(Integer y=0; y<8; y=y+1) begin
                        //check for transpose: Output[y][x] should equal Input[x][y]
                        if(rg_input_mcu.block[y][x] != rg_output_mcu.block[x][y]) match_ = False;
                    end

                print_du(rg_output_mcu, "Output MCU", CYAN);
                if(match_) print_s("Iteration Passed", GREEN);
                else print_s("Iteration Failed", RED);
            endaction

            rg_iter <= rg_iter + 1;
        endseq
        print_s("Finished all tests", BLUE);
    endseq;

    FSM i_test_fsm <- mkFSM(s);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

endpackage