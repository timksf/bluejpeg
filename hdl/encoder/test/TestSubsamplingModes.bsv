package TestSubsamplingModes;

import Connectable :: *;
import GetPut :: *;
import StmtFSM :: *;

import ChromaBlockReorder :: *;
import ChromaSubsampler :: *;
import DUDispatcher :: *;
import PrintUtil :: *;
import TestHelper :: *;
import Types :: *;
import YBlockReorder :: *;

function UInt#(8) input_pixel(UInt#(11) index);
    UInt#(16) block = zeroExtend(index >> 6);
    UInt#(16) pixel = zeroExtend(index & 63);
    UInt#(16) row = (block >> 2) * 8 + (pixel >> 3);
    UInt#(16) col = (block & 3) * 8 + (pixel & 7);
    return truncate(row * 32 + col);
endfunction

function UInt#(8) expected_pixel(SubsamplingMode_t mode, UInt#(11) index);
    UInt#(16) block = zeroExtend(index >> 6);
    UInt#(16) pixel = zeroExtend(index & 63);
    UInt#(16) row = 0;
    UInt#(16) col = 0;
    UInt#(16) expected = 0;

    case(mode)
        YCBCR_444: begin
            row = (block >> 2) * 8 + (pixel >> 3);
            col = (block & 3) * 8 + (pixel & 7);
            expected = row * 32 + col;
        end
        YCBCR_422: begin
            row = (block >> 1) * 8 + (pixel >> 3);
            col = (block & 1) * 16 + (pixel & 7) * 2;
            expected = row * 32 + col + 1;
        end
        YCBCR_420: begin
            row = (block >> 1) * 16 + (pixel >> 3) * 2;
            col = (block & 1) * 16 + (pixel & 7) * 2;
            expected = row * 32 + col + 17;
        end
    endcase

    return truncate(expected);
endfunction

module [Module] mkSubsamplingModeTest#(
        SubsamplingMode_t mode,
        UInt#(11) expected_count
    )(TestHandler);

    function print_fmt = print_mod_pre_color_t_f;

    NumProxy#(8) _prx_block_width = ?;
    NumProxy#(4) _prx_block_cols = ?;

    ChromaSubsampler_ifc i_subsampler <- mkChromaSubsampler(_prx_block_width);
    ChromaBlockReorder_ifc i_reorder <- mkChromaBlockReorder(_prx_block_cols);
    mkConnection(i_subsampler.pixel_out, i_reorder.pixel_in);

    Reg#(UInt#(11)) rg_input_count  <- mkReg(0);
    Reg#(UInt#(11)) rg_output_count <- mkReg(0);
    Reg#(Bool)      rg_failed       <- mkReg(False);

    Stmt test = seq
        action
            rg_input_count  <= 0;
            rg_output_count <= 0;
            rg_failed       <= False;
            i_subsampler.configure(mode);
            i_reorder.configure(mode, 4);
        endaction

        par
            while(rg_input_count < 1024) action
                i_subsampler.pixel_in.put(input_pixel(rg_input_count));
                rg_input_count <= rg_input_count + 1;
            endaction

            while(rg_output_count < expected_count) action
                let actual <- i_reorder.pixel_out.get();
                let expected = expected_pixel(mode, rg_output_count);
                if(actual != expected) begin
                    print_fmt($format("ERROR: mode %0d output %0d: got %0d, expected %0d",
                        mode, rg_output_count, actual, expected), RED);
                    rg_failed <= True;
                    $fatal();
                end
                rg_output_count <= rg_output_count + 1;
            endaction
        endpar

        if(!rg_failed)
            print_fmt($format("Subsampling mode %0d passed (%0d pixels)", mode, expected_count), GREEN);
    endseq;

    FSM fsm_test <- mkFSM(test);

    method Action go();
        fsm_test.start();
    endmethod

    method Bool done();
        return fsm_test.done();
    endmethod

endmodule

module [Module] mkDUDispatcherModeTest#(
        SubsamplingMode_t mode,
        UInt#(3) y_blocks
    )(TestHandler);

    function print_fmt = print_mod_pre_color_t_f;

    DUDispatcher_ifc i_dispatcher <- mkDUDispatcher;

    Reg#(UInt#(9)) rg_y_count      <- mkReg(0);
    Reg#(UInt#(7)) rg_cb_count     <- mkReg(0);
    Reg#(UInt#(7)) rg_cr_count     <- mkReg(0);
    Reg#(UInt#(9)) rg_output_count <- mkReg(0);
    Reg#(Bool)     rg_failed       <- mkReg(False);

    UInt#(9) y_pixel_count = zeroExtend(y_blocks) * 64;
    UInt#(9) output_count = (zeroExtend(y_blocks) + 2) * 64;

    Stmt test = seq
        action
            rg_y_count      <= 0;
            rg_cb_count     <= 0;
            rg_cr_count     <= 0;
            rg_output_count <= 0;
            rg_failed       <= False;
            i_dispatcher.set_mode(mode);
        endaction

        par
            while(rg_y_count < y_pixel_count) action
                i_dispatcher.y.put(truncate(rg_y_count));
                rg_y_count <= rg_y_count + 1;
            endaction

            while(rg_cb_count < 64) action
                i_dispatcher.cb.put(160 + zeroExtend(rg_cb_count));
                rg_cb_count <= rg_cb_count + 1;
            endaction

            while(rg_cr_count < 64) action
                i_dispatcher.cr.put(224 + zeroExtend(rg_cr_count));
                rg_cr_count <= rg_cr_count + 1;
            endaction

            while(rg_output_count < output_count) action
                let actual <- i_dispatcher.pix.get();
                UInt#(3) block = truncate(rg_output_count >> 6);
                UInt#(8) pixel = truncate(rg_output_count & 63);
                UInt#(8) expected = block < y_blocks ?
                    truncate(rg_output_count) :
                    (block == y_blocks ? 160 + pixel : 224 + pixel);
                if(actual != expected) begin
                    print_fmt($format("ERROR: dispatcher mode %0d output %0d: got %0d, expected %0d",
                        mode, rg_output_count, actual, expected), RED);
                    rg_failed <= True;
                    $fatal();
                end
                rg_output_count <= rg_output_count + 1;
            endaction
        endpar

        if(!rg_failed)
            print_fmt($format("DU dispatcher mode %0d passed (%0d blocks)", mode, y_blocks + 2), GREEN);
    endseq;

    FSM fsm_test <- mkFSM(test);

    method Action go();
        fsm_test.start();
    endmethod

    method Bool done();
        return fsm_test.done();
    endmethod

endmodule

function UInt#(8) y_input_pixel(UInt#(11) index);
    UInt#(16) block = zeroExtend(index >> 6);
    UInt#(16) pixel = zeroExtend(index & 63);
    return truncate(block * 29 + pixel);
endfunction

function UInt#(8) y_expected_pixel(UInt#(11) index);
    UInt#(5) output_block = truncate(index >> 6);
    UInt#(5) block_pair_base = (output_block >> 3) * 8;
    UInt#(5) source_block = block_pair_base + case(output_block & 7)
        0: 0;
        1: 1;
        2: 4;
        3: 5;
        4: 2;
        5: 3;
        6: 6;
        default: 7;
    endcase;
    UInt#(11) source_index = zeroExtend(source_block) * 64 + (index & 63);
    return y_input_pixel(source_index);
endfunction

module [Module] mkYBlockReorder420Test(TestHandler);

    function print_fmt = print_mod_pre_color_t_f;

    NumProxy#(4) _prx_block_cols = ?;
    YBlockReorder_ifc i_reorder <- mkYBlockReorder(_prx_block_cols, False);

    Reg#(UInt#(11)) rg_input_count  <- mkReg(0);
    Reg#(UInt#(11)) rg_output_count <- mkReg(0);
    Reg#(Bool)      rg_failed       <- mkReg(False);

    Stmt test = seq
        action
            rg_input_count  <= 0;
            rg_output_count <= 0;
            rg_failed       <= False;
            i_reorder.configure(YCBCR_420, 4);
        endaction

        par
            while(rg_input_count < 1024) action
                i_reorder.pixel_in.put(y_input_pixel(rg_input_count));
                rg_input_count <= rg_input_count + 1;
            endaction

            while(rg_output_count < 1024) action
                let actual <- i_reorder.pixel_out.get();
                let expected = y_expected_pixel(rg_output_count);
                if(actual != expected) begin
                    print_fmt($format("ERROR: 4:2:0 luma reorder output %0d: got %0d, expected %0d",
                        rg_output_count, actual, expected), RED);
                    rg_failed <= True;
                    $fatal();
                end
                rg_output_count <= rg_output_count + 1;
            endaction
        endpar

        if(!rg_failed)
            print_fmt($format("4:2:0 luma block reorder passed (1024 pixels)"), GREEN);
    endseq;

    FSM fsm_test <- mkFSM(test);

    method Action go();
        fsm_test.start();
    endmethod

    method Bool done();
        return fsm_test.done();
    endmethod

endmodule

module [Module] mkTestSubsamplingModes(TestHandler);

    let test_444 <- mkSubsamplingModeTest(YCBCR_444, 1024);
    let test_422 <- mkSubsamplingModeTest(YCBCR_422, 512);
    let test_420 <- mkSubsamplingModeTest(YCBCR_420, 256);
    let test_y_420 <- mkYBlockReorder420Test;
    let test_dispatch_444 <- mkDUDispatcherModeTest(YCBCR_444, 1);
    let test_dispatch_422 <- mkDUDispatcherModeTest(YCBCR_422, 2);
    let test_dispatch_420 <- mkDUDispatcherModeTest(YCBCR_420, 4);

    Stmt test = seq
        test_444.go();
        await(test_444.done());
        test_422.go();
        await(test_422.done());
        test_420.go();
        await(test_420.done());
        test_y_420.go();
        await(test_y_420.done());
        test_dispatch_444.go();
        await(test_dispatch_444.done());
        test_dispatch_422.go();
        await(test_dispatch_422.done());
        test_dispatch_420.go();
        await(test_dispatch_420.done());
    endseq;

    FSM fsm_test <- mkFSM(test);

    method Action go();
        fsm_test.start();
    endmethod

    method Bool done();
        return fsm_test.done();
    endmethod

endmodule

endpackage
