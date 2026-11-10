package TestJpegSystem;

import Clocks :: *;
import Connectable :: *;
import GetPut :: *;
import StmtFSM :: *;

import AXI4_Lite_Master :: *;
import BlueCSRCore :: *;
import BlueCSRTb :: *;
import UartRx :: *;

import BDPI :: *;
import BlueJPEGRegs :: *;
import BlueJPEGTestHelper :: *;
import JpegTestRegs :: *;
import JpegTestSystem :: *;
import PrintUtil :: *;
import TestHelper :: *;

String input_image_path = `ASSETS_DIR + "/sample_192x192.bmp";
String output_jpeg_path = "uart_capture.jpg";

//UART clocks per bit in simulation, kept short so a frame transfers in reasonable time
typedef 8 SimUartDiv;

/*
 * End-to-end test of the PA200T test system without the board shell: the encoder starts
 * through its register map, the pattern ROM streams in by itself, and the JPEG comes back
 * over the UART at 2.5 times the system clock. A UART receiver model decodes the serial
 * line, the bytes are compared with the C++ reference encoder and all counters are printed.
 */
module [Module] mkTestJpegSystem(TestHandler_ifc)
    provisos(
        NumAlias#(ram_words, 'd200_000)
    );
    function print_s   = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    Clock clk_uart <- mkAbsoluteClock(2, 4);
    Reset rst_uart <- mkAsyncResetFromCR(2, clk_uart);

    JpegTestSystem_ifc dut <- mkJpegTestSystem(clk_uart, rst_uart);

    //register access to both maps
    let defs_jpeg <- build_blue_csr_tb_lookup(blue_jpeg_csrs);
    let defs_test <- build_blue_csr_tb_lookup(jpeg_test_regs);

    AXI4_Lite_Master_Rd#(32, 32) i_jpeg_rd  <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_jpeg_wr  <- mkAXI4_Lite_Master_Wr(4);
    AXI4_Lite_Master_Rd#(32, 32) i_test_rd  <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_test_wr  <- mkAXI4_Lite_Master_Wr(4);
    let                          i_jpeg_acc <- mkBlueCSRTbAccessorAXI4Lite(defs_jpeg, i_jpeg_rd, i_jpeg_wr);
    let                          i_test_acc <- mkBlueCSRTbAccessorAXI4Lite(defs_test, i_test_rd, i_test_wr);

    mkConnection(dut.s_jpeg_rd, i_jpeg_rd.fab);
    mkConnection(dut.s_jpeg_wr, i_jpeg_wr.fab);
    mkConnection(dut.s_test_rd, i_test_rd.fab);
    mkConnection(dut.s_test_wr, i_test_wr.fab);

    //UART receiver model in the UART domain, bytes cross back through a synchronizing FIFO
    UartRx#(8)          i_uart_rx  <- mkUartRx(1, fromInteger(valueOf(SimUartDiv)), 16, clocked_by clk_uart, reset_by rst_uart);
    SyncFIFOIfc#(Bit#(8)) f_uart_rx <- mkSyncFIFOToCC(16, clk_uart, rst_uart);

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_uart_line;
        i_uart_rx.rx(dut.uart_tx);
        dut.uart_rx(1);
    endrule

    rule r_uart_byte;
        let b <- i_uart_rx.receive.get;
        f_uart_rx.enq(b);
    endrule

    Reg#(UInt#(64)) rg_ram_ptr   <- mkRegU;
    Reg#(UInt#(32)) rg_ref_bytes <- mkReg(0);
    Reg#(UInt#(32)) rg_rx_bytes  <- mkReg(0);
    Reg#(UInt#(32)) rg_mismatch  <- mkReg(0);
    Reg#(Bool)      rg_failed    <- mkReg(False);
    Reg#(Bit#(32))  rg_rsp       <- mkReg(0);
    Reg#(File)      rg_file      <- mkRegU;
    Reg#(UInt#(32)) rg_watchdog  <- mkReg(0);

    UInt#(64) ref_base = 0;

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_watchdog;
        if(rg_watchdog == 5_000_000) begin
            print_fmt($format("ERROR: timeout after %0d cycles, %0d of %0d UART bytes received", rg_watchdog, rg_rx_bytes, rg_ref_bytes), RED);
            $finish(1);
        end
        rg_watchdog <= rg_watchdog + 1;
    endrule

    function Action fail(Fmt msg);
        action
            print_fmt($format("ERROR: ") + msg, RED);
            rg_failed <= True;
        endaction
    endfunction

    //read a register through an accessor into rg_rsp
    function Stmt read_reg(BlueCSRTbAccessor_ifc#(32) acc, String name);
        return seq
            acc.read_reg_req(name);
            action
                let rsp <- acc.read_reg_rsp();
                rg_rsp <= tpl_1(rsp);
            endaction
        endseq;
    endfunction

    function Stmt report(BlueCSRTbAccessor_ifc#(32) acc, String name, String what);
        return seq
            read_reg(acc, name);
            print_fmt($format("  %s = %0d (", name, rg_rsp) + $format(what) + $format(")"), WHITE);
        endseq;
    endfunction

    Stmt collect_uart = seq
        action
            let fd <- $fopen(output_jpeg_path, "wb");
            rg_file <= fd;
        endaction
        while(rg_rx_bytes < rg_ref_bytes) action
            let b = f_uart_rx.first;
            f_uart_rx.deq;
            $fwrite(rg_file, "%c", b);
            let     word     <- read_word_SimRAM(rg_ram_ptr, ref_base + extend(rg_rx_bytes));
            Bit#(8) expected = truncate(pack(word));
            if(b != expected) begin
                if(rg_mismatch < 10)
                    print_fmt($format("ERROR: byte %0d: UART %02x, reference %02x", rg_rx_bytes, b, expected), RED);
                rg_mismatch <= rg_mismatch + 1;
            end
            rg_rx_bytes <= rg_rx_bytes + 1;
        endaction
        $fclose(rg_file);
    endseq;

    Stmt main = seq
        print_s("=== TestJpegSystem start ===", GREEN);

        action
            let ram <- create_SimRAM(fromInteger(valueOf(ram_words)), 4);
            rg_ram_ptr <= ram;
        endaction
        action
            let n <- jpeg_encode_ref(input_image_path, 0, rg_ram_ptr, ref_base);
            rg_ref_bytes <= n;
        endaction
        print_fmt($format("C++ reference: %0d bytes", rg_ref_bytes), GREEN);

        bjpeg_wait_tables_ready(i_jpeg_acc, rg_rsp);

        //test system: short UART bit time for simulation, stream enabled by default
        i_test_acc.write_reg_req("UDIV", fromInteger(valueOf(SimUartDiv)));
        bjpeg_expect_wr_ok(i_test_acc);
        read_reg(i_test_acc, "NPIX");
        if(rg_rsp != fromInteger(valueOf(PatternPixels))) fail($format("NPIX reset value %0d", rg_rsp));

        //encoder: 192x192 frame, frame-done interrupt enabled, then start
        i_jpeg_acc.write_reg_req("IMSZ", {16'd192, 16'd192});
        bjpeg_expect_wr_ok(i_jpeg_acc);
        i_jpeg_acc.write_reg_req("IRQE", 1);
        bjpeg_expect_wr_ok(i_jpeg_acc);
        i_jpeg_acc.write_reg_req("CTRL", 1);
        bjpeg_expect_wr_ok(i_jpeg_acc);

        par
            collect_uart;
            seq
                await(dut.irq);
                print_s("Encoder interrupt raised", GREEN);
            endseq
        endpar

        print_fmt($format("UART: %0d bytes received, %0d mismatches against the reference", rg_rx_bytes, rg_mismatch), rg_mismatch == 0 ? GREEN : RED);
        if(rg_mismatch != 0) rg_failed <= True;

        print_s("Encoder counters (system clock cycles):", YELLOW);
        report(i_jpeg_acc, "PERF0", "running cycles");
        report(i_jpeg_acc, "PERF1", "pixels accepted");
        report(i_jpeg_acc, "PERF2", "JPEG bytes produced");
        report(i_jpeg_acc, "PERF3", "running cycles without an input pixel");
        report(i_jpeg_acc, "PERF4", "flush: last data unit to frame done");
        report(i_jpeg_acc, "PERF5", "frame: start accepted to done");
        report(i_jpeg_acc, "PERF6", "boot: reset to tables ready");
        print_s("Test system counters (system clock cycles):", YELLOW);
        report(i_test_acc, "INCYC",  "input window, first to last pixel");
        report(i_test_acc, "INSTL",  "input stalls");
        report(i_test_acc, "OUTB",   "output bytes");
        report(i_test_acc, "OUTCYC", "output window, first to last byte");
        report(i_test_acc, "OUTSTL", "output stalls");
        report(i_test_acc, "TOTAL",  "frame start to last byte");

        read_reg(i_test_acc, "OUTB");
        if(unpack(rg_rsp) != rg_ref_bytes) fail($format("OUTB %0d does not match the reference length %0d", rg_rsp, rg_ref_bytes));
        read_reg(i_jpeg_acc, "PERF1");
        if(rg_rsp != fromInteger(valueOf(PatternPixels))) fail($format("encoder accepted %0d pixels", rg_rsp));
        read_reg(i_test_acc, "STS");
        if(rg_rsp[2:1] != 2'b11) fail($format("status %b, input and output should be done", rg_rsp[2:0]));

        if(rg_failed) print_s("ERROR: TestJpegSystem FAILED", RED);
        else print_s("=== TestJpegSystem PASSED ===", GREEN);
    endseq;

    FSM i_fsm <- mkFSM(main);

    method Action go();
        i_fsm.start();
    endmethod

    method Bool done();
        return i_fsm.done();
    endmethod
endmodule

endpackage
