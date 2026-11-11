package TestJpegUdpSystem;

import Connectable :: *;
import DefaultValue :: *;
import GetPut :: *;
import StmtFSM :: *;

import AXI4_Lite_Master :: *;
import AXI4_Lite_Types :: *;
import AXI4_Stream :: *;
import BlueCSRCore :: *;
import BlueCSRTb :: *;
import EthernetTypes :: *;
import UdpRgmiiCsr :: *;

import BDPI :: *;
import BlueJPEGRegs :: *;
import BlueJPEGTestHelper :: *;
import JpegUdpRegs :: *;
import JpegUdpSystem :: *;
import SimRAM_AXI :: *;
import TestHelper :: *;
import UdpModel :: *;

import "BDPI" function Action prepare_udp_test_image(String path, Bool full_size);

`ifdef UDP_TEST_1080P
typedef 1920 UdpTestWidth;
typedef 1080 UdpTestHeight;
String udp_input_image = `ASSETS_DIR + "/sample_1920x1280.bmp";
Bool   udp_large_test  = True;
`else
typedef 192 UdpTestWidth;
typedef 192 UdpTestHeight;
String udp_input_image = `ASSETS_DIR + "/sample_192x192.bmp";
Bool   udp_large_test  = False;
`endif

//the package name follows the repository test selector
module [Module] mkTestJpegUdpSystem(TestHandler_ifc);
    JpegUdpSystem_ifc                       i_dut <- mkJpegUdpSystem(True);
    SimRAM_AXI4_ifc#(3000000, 30, 32, 4, 0) i_ram <- mkSimRAM_AXI(False);
    UdpModel_ifc                            i_udp <- mkUdpModel;
    mkConnection(i_dut.m_mem_rd, i_ram.fab_rd);
    mkConnection(i_dut.m_mem_wr, i_ram.fab_wr);
    mkConnection(i_udp.rx_header, i_dut.rx_header);
    mkConnection(i_udp.rx_payload, i_dut.rx_payload);
    mkConnection(i_dut.tx_header, i_udp.tx_header);
    mkConnection(i_dut.tx_payload, i_udp.tx_payload);

    let                          defs_jpeg  <- build_blue_csr_tb_lookup(blue_jpeg_csrs);
    let                          defs_sys   <- build_blue_csr_tb_lookup(jpeg_udp_regs);
    AXI4_Lite_Master_Rd#(32, 32) i_jpeg_rd  <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_jpeg_wr  <- mkAXI4_Lite_Master_Wr(4);
    AXI4_Lite_Master_Rd#(32, 32) i_sys_rd   <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_sys_wr   <- mkAXI4_Lite_Master_Wr(4);
    let                          i_jpeg_acc <- mkBlueCSRTbAccessorAXI4Lite(defs_jpeg, i_jpeg_rd, i_jpeg_wr);
    let                          i_sys_acc  <- mkBlueCSRTbAccessorAXI4Lite(defs_sys, i_sys_rd, i_sys_wr);
    mkConnection(i_dut.s_jpeg_rd, i_jpeg_rd.fab);
    mkConnection(i_dut.s_jpeg_wr, i_jpeg_wr.fab);
    mkConnection(i_dut.s_sys_rd, i_sys_rd.fab);
    mkConnection(i_dut.s_sys_wr, i_sys_wr.fab);

    UInt#(32)       npix                = fromInteger(valueOf(UdpTestWidth) * valueOf(UdpTestHeight));
    UInt#(32)       base                = 1009;
    Reg#(UInt#(64)) rg_source           <- mkReg(0);
    Reg#(UInt#(64)) rg_reference        <- mkReg(0);
    Reg#(UInt#(32)) rg_reference_length <- mkReg(0);
    Reg#(Bit#(32))  rg_rsp              <- mkReg(0);
    Reg#(UInt#(32)) rg_packet_base      <- mkReg(0);
    Reg#(UInt#(32)) rg_packet_pixels    <- mkReg(0);
    Reg#(UInt#(32)) rg_byte             <- mkReg(0);
    Reg#(UInt#(32)) rg_pixel_index      <- mkReg(0);
    Reg#(Bit#(32))  rg_sum1             <- mkReg(0);
    Reg#(Bit#(32))  rg_sum2             <- mkReg(0);
    Reg#(Bit#(32))  rg_frame_sum1       <- mkReg(0);
    Reg#(Bit#(32))  rg_frame_sum2       <- mkReg(0);
    Reg#(UInt#(32)) rg_rx_frame         <- mkReg(0);
    Reg#(UInt#(32)) rg_rx_count         <- mkReg(0);
    Reg#(UInt#(16)) rg_sequence         <- mkReg(0);
    Reg#(Bit#(64))  rg_header           <- mkReg(0);
    Reg#(UInt#(16)) rg_packet_length    <- mkReg(0);
    Reg#(Bool)      rg_last             <- mkReg(False);
    Reg#(Bool)      rg_frame_done       <- mkReg(False);
    Reg#(UInt#(32)) rg_packets          <- mkReg(0);
    Reg#(UInt#(32)) rg_first_packets    <- mkReg(0);
    Reg#(File)      rg_file             <- mkRegU;
    Reg#(UInt#(32)) rg_watchdog         <- mkReg(0);
    Reg#(Bool)      rg_prev_busy        <- mkReg(False);
    Reg#(Bit#(32))  rg_start_cycle      <- mkReg(0);
    Reg#(Bit#(32))  rg_expected_period  <- mkReg(0);
    Reg#(UInt#(32)) rg_starts           <- mkReg(0);

    rule r_start_monitor;
        rg_prev_busy <= i_dut.busy;
        if(i_dut.busy && !rg_prev_busy) begin
            rg_start_cycle     <= pack(rg_watchdog);
            rg_expected_period <= pack(rg_watchdog) - rg_start_cycle;
            rg_starts          <= rg_starts + 1;
        end
    endrule

    rule r_watchdog;
        rg_watchdog <= rg_watchdog + 1;
        if(rg_watchdog == 65000000) begin
            $display("ERROR: UDP test timeout, frame %0d, bytes %0d", rg_rx_frame, rg_rx_count);
            $finish(1);
        end
    endrule

    function Action check(Bool condition, Fmt message);
        action
            if(!condition) begin
                $display("ERROR: ", message);
                $finish(1);
            end
        endaction
    endfunction

    function Stmt read_reg(String name);
        return seq
            if(name == "MEMDATA")
                i_sys_rd.request.put(AXI4_Lite_Read_Rq_Pkg {
                    addr: 'h18,
                    prot: UNPRIV_SECURE_DATA
                });
            else i_sys_acc.read_reg_req(name);
            action
                let response <- i_sys_acc.read_reg_rsp;
                check(tpl_2(response) == CSR_OKAY, $format("read %s failed", name));
                rg_rsp <= tpl_1(response);
            endaction
        endseq;
    endfunction

    function Stmt write_reg(String name, Bit#(32) value);
        return seq
            if(name == "MEMDATA")
                i_sys_wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                    addr: 'h18,
                    data: value,
                    strb: '1,
                    prot: UNPRIV_SECURE_DATA
                });
            else i_sys_acc.write_reg_req(name, value);
            bjpeg_expect_wr_ok(i_sys_acc);
        endseq;
    endfunction

    function Stmt send_packet(Bool malformed);
        return seq
            action
                UdpRxHeader header = unpack(0);
                header.dest_port = 5000;
                header.length    = truncate(pack(12 + 3 * rg_packet_pixels + (malformed ? 1 : 0)));
                i_udp.send_header.put(header);
                rg_byte        <= 0;
                rg_pixel_index <= 0;
            endaction
            while(rg_byte < 4) action
                Bit#(32) index = pack(rg_packet_base);
                Bit#(8)  data  = truncate(index >> ((3 - rg_byte) * 8));
                i_udp.send_byte.put(AXI4_Stream_Pkg {
                    data: data,
                    keep: 1,
                    user: 0,
                    dest: 0,
                    id  : 0,
                    last: False
                });
                rg_byte <= rg_byte + 1;
            endaction
            while(rg_pixel_index < rg_packet_pixels) seq
                for(rg_byte <= 0; rg_byte < 3; rg_byte <= rg_byte + 1) action
                    let      rgb   <- read_word_SimRAM(rg_source, extend(rg_packet_base + rg_pixel_index));
                    Bit#(32) word  = pack(truncate(rgb));
                    Bit#(32) pixel = rgb2ycbcr_ref(unpack(word[23:16]), unpack(word[15:8]), unpack(word[7:0]));
                    Bit#(8)  data  = truncate(pixel >> ((2 - rg_byte) * 8));
                    Bool     last  = rg_pixel_index + 1 == rg_packet_pixels && rg_byte == 2 && !malformed;
                    i_udp.send_byte.put(AXI4_Stream_Pkg {
                        data: data,
                        keep: 1,
                        user: 0,
                        dest: 0,
                        id  : 0,
                        last: last
                    });
                endaction
                rg_pixel_index <= rg_pixel_index + 1;
            endseq
            if(malformed) i_udp.send_byte.put(AXI4_Stream_Pkg {
                data: 0,
                keep: 1,
                user: 0,
                dest: 0,
                id  : 0,
                last: True
            });
            //wait for the final write response before changing the command or frame configuration
            delay(32);
            read_reg("STS");
            while(rg_rsp[4] == 1) read_reg("STS");
            delay(32);
        endseq;
    endfunction

    Stmt receive_frame = seq
        rg_rx_count   <= 0;
        rg_sequence   <= 0;
        rg_packets    <= 0;
        rg_frame_done <= False;
        action
            let file <- $fopen("udp_capture.jpg", "wb");
            check(file != InvalidFile, $format("cannot open JPEG output"));
            rg_file <= file;
        endaction
        while(!rg_frame_done) seq
            action
                let header <- i_udp.receive_header.get;
                check(header.payload_length > 8 && header.payload_length <= 1032 && header.checksum == 0, $format("invalid UDP transmit request"));
                rg_packet_length <= unpack(header.payload_length) - 8;
                rg_header        <= 0;
                rg_packets       <= rg_packets + 1;
            endaction
            for(rg_byte <= 0; rg_byte < 8; rg_byte <= rg_byte + 1) action
                let beat <- i_udp.receive_byte.get;
                check(!beat.last && beat.keep == 1 && beat.user == 0 && beat.dest == 0 && beat.id == 0, $format("invalid packet header sidebands"));
                rg_header <= (rg_header << 8) | zeroExtend(beat.data);
            endaction
            action
                check(rg_header[63:56] == 'h4a && rg_header[55:49] == 0, $format("packet magic or flags"));
                check(rg_header[47:32] == truncate(pack(rg_rx_frame)) && rg_header[31:16] == pack(rg_sequence), $format("frame or sequence mismatch"));
                check(rg_header[15:0] == pack(rg_packet_length), $format("payload length mismatch"));
                rg_last <= unpack(rg_header[48]);
            endaction
            for(rg_byte <= 0; rg_byte < zeroExtend(rg_packet_length); rg_byte <= rg_byte + 1) action
                let beat     <- i_udp.receive_byte.get;
                let expected <- read_word_SimRAM(rg_reference, extend(rg_rx_count));
                check(rg_rx_count < rg_reference_length && beat.data == truncate(pack(expected)), $format("frame %0d byte %0d differs from reference", rg_rx_frame, rg_rx_count));
                check(beat.last == (rg_byte + 1 == zeroExtend(rg_packet_length)), $format("UDP tlast mismatch"));
                check(beat.keep == 1 && beat.user == 0 && beat.dest == 0 && beat.id == 0, $format("invalid payload sidebands"));
                $fwrite(rg_file, "%c", beat.data);
                rg_rx_count <= rg_rx_count + 1;
            endaction
            action
                rg_sequence <= rg_sequence + 1;
                if(rg_last) begin
                    check(rg_rx_count == rg_reference_length, $format("wrong frame length"));
                    rg_frame_done <= True;
                end
            endaction
        endseq
        $fclose(rg_file);
        $display("UDP frame %0d: %0d bytes, %0d packets, identical to C++ reference", rg_rx_frame, rg_rx_count, rg_packets);
    endseq;

    Stmt main = seq
        prepare_udp_test_image(udp_input_image, udp_large_test);
        action
            let source    <- create_SimRAM(3000000, 4);
            let reference <- create_SimRAM(3000000, 4);
            rg_source    <= source;
            rg_reference <= reference;
        endaction
        action
            let image <- create_ImageLoader("udp_test_image.bmp");
            write_to_mem_interleaved_ImageLoader(image, rg_source, 0);
        endaction
        action
            let length <- jpeg_encode_ref("udp_test_image.bmp", 0, rg_reference, 0);
            check(length > 0, $format("empty C++ reference"));
            rg_reference_length <= length;
        endaction
        bjpeg_wait_tables_ready(i_jpeg_acc, rg_rsp);
        i_jpeg_acc.write_reg_req("IMSZ", {fromInteger(valueOf(UdpTestHeight)), Bit#(16)'(fromInteger(valueOf(UdpTestWidth)))});
        bjpeg_expect_wr_ok(i_jpeg_acc);
        i_jpeg_acc.write_reg_req("IRQE", 1);
        bjpeg_expect_wr_ok(i_jpeg_acc);
        write_reg("BASE", pack(base));
        write_reg("NPIX", pack(npix));
        write_reg("MEMADDR", 7);
        write_reg("MEMDATA", 'h12345678);
        read_reg("MEMDATA");
        check(rg_rsp == 'h12345678, $format("peek/poke mismatch"));
        write_reg("CTRL", 4);
        rg_packet_base <= 0;
        while(rg_packet_base < npix) seq
            rg_packet_pixels <= min(480, npix - rg_packet_base);
            send_packet(False);
            rg_packet_base <= rg_packet_base + rg_packet_pixels;
        endseq
        rg_packet_base   <= 0;
        rg_packet_pixels <= 7;
        send_packet(False);
        send_packet(True);
        rg_pixel_index <= 0;
        while(rg_pixel_index < npix) action
            let      rgb   <- read_word_SimRAM(rg_source, extend(rg_pixel_index));
            Bit#(32) word  = pack(truncate(rgb));
            let      pixel = rgb2ycbcr_ref(unpack(word[23:16]), unpack(word[15:8]), unpack(word[7:0]));
            let      sum   = rg_sum1 + pixel;
            rg_sum1        <= sum;
            rg_sum2        <= rg_sum2 + sum;
            rg_pixel_index <= rg_pixel_index + 1;
        endaction
        write_reg("CTRL", 8);
        read_reg("STS");
        while(rg_rsp[2] == 0) read_reg("STS");
        read_reg("CHK1");
        check(rg_rsp == rg_sum1, $format("CHK1 mismatch: %08x expected %08x", rg_rsp, rg_sum1));
        read_reg("CHK2");
        check(rg_rsp == rg_sum2, $format("CHK2 mismatch"));
        read_reg("LDPKT");
        check(unpack(rg_rsp) == (npix + 479) / 480 + 1, $format("LDPKT mismatch"));
        read_reg("LDPIX");
        check(unpack(rg_rsp) == npix + 7, $format("LDPIX mismatch"));
        read_reg("LDDROP");
        check(rg_rsp == 1, $format("LDDROP mismatch"));
        i_udp.hold_tx(True);
        write_reg("CTRL", 1);
        delay(5000);
        i_udp.hold_tx(False);
        receive_frame;
        rg_first_packets <= rg_packets;
        await(!i_dut.busy);
        read_reg("FRAMES");
        check(rg_rsp == 1, $format("single frame count"));
        read_reg("OUTB");
        check(unpack(rg_rsp) == rg_reference_length, $format("OUTB mismatch"));
        read_reg("PERIOD");
        check(rg_rsp == 0, $format("first PERIOD must be zero"));
        write_reg("CTRL", 2);
        rg_rx_frame <= 1;
        receive_frame;
        rg_rx_frame <= 2;
        //stop repeat during the second repeat frame, so precisely three frames finish
        write_reg("CTRL", 0);
        receive_frame;
        await(!i_dut.busy);
        delay(32);
        read_reg("FRAMES");
        check(rg_rsp == 3, $format("repeat frame count"));
        read_reg("PERIOD");
        check(rg_rsp == rg_expected_period && rg_starts == 3, $format("PERIOD must match the observed start interval"));
        read_reg("PKTS");
        check(unpack(rg_rsp) == rg_first_packets, $format("PKTS mismatch"));
        read_reg("STS");
        check(rg_rsp[5] == 0 && rg_rsp[0] == 0, $format("memory error or busy at completion"));
        read_reg("INCYC"); $display("INCYC %0d", rg_rsp);
        read_reg("INSTL"); $display("INSTL %0d", rg_rsp);
        read_reg("OUTB"); $display("OUTB %0d", rg_rsp);
        read_reg("OUTCYC"); $display("OUTCYC %0d", rg_rsp);
        read_reg("OUTSTL"); $display("OUTSTL %0d", rg_rsp);
        read_reg("TOTAL"); $display("TOTAL %0d", rg_rsp);
        read_reg("PERIOD"); $display("PERIOD %0d", rg_rsp);
        $display("TestJpegUdpSystem PASSED (%0dx%0d)", valueOf(UdpTestWidth), valueOf(UdpTestHeight));
    endseq;
    FSM i_fsm <- mkFSM(main);
    method go   = i_fsm.start;
    method done = i_fsm.done;
endmodule

endpackage
