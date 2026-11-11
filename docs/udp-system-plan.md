# Implementation plan: 1080p JPEG test system with DDR3 frame store and UDP egress

Status: complete. Milestones 0 through 5 pass. Both FPGA variants meet timing. DDR3
calibration, full and partial peek/poke, UDP loading and VERIFY pass on the PA200T.
One 1080p frame and 100 consecutive repeat frames match the C++ reference byte for byte
with no lost egress packets. Continuous performance is 9.7405 fps at 81.25 MHz.
See `docs/udp-system.md` for commands and validation results. Written 2026-11-10.

## 1. Goal and scope

Build a second, fully separate PA200T test system next to the existing UART one:

- A 1920x1080 YCbCr frame is held in the board's DDR3 (Xilinx MIG).
- The host loads the frame over UDP. Loading has no real-time constraint.
- The encoder reads the frame from DDR3 at its own pace and sends the JPEG over UDP,
  once or repeatedly.
- Registers are reached through the JTAG bus master, as in the UART system.
- The whole design runs on one clock, the MIG `ui_clk`. The user approved running the DDR3
  below 400 MHz for this.

Out of scope: chroma subsampling, the synthesis sweep, changes to the UART system, any
encoder throughput work (see section 9).

## 2. Ground rules

- Load the `bluespec-style` skill before any `.bsv` edit. No semicolons in comments,
  description strings or Markdown. Start a new sentence or bind with a word.
- The UART system must keep working unchanged: `hdl/src/system/`, `hdl/src/fpga/pa200t/`,
  `make sim RUN_TEST=TestJpegSystem`, `make bitstream`. Only `hdl/src/encoder/` is shared.
- Use the native BSVTools `vivado_tcl` target at the checked-out commit. Patch only if it fails.
- Each register has one owning rule. Other rules send pulses (see `perf_counter` in
  `hdl/src/encoder/BlueJPEGRegs.bsv` and the `r_rewind` rules). No new bsc warnings from our sources.
- A failing test must print `ERROR` (this is what fails `make sim`).
- Do not commit unless the user asks. Do not load a bitstream or touch the board unless the user asks.
- Recover a failed milestone with local fixes and rerun its acceptance checks when no major
  architectural change is needed. Report and discuss failures that require a major change
  to the agreed design or scope before proceeding with that change.
- Use the repository Nix flake for builds and tests: `nix develop ./nix --command make -C hdl ...`.
  The host PATH contains an older, incompatible Bluespec installation. The flake may be
  extended when tools or dependencies needed for this implementation are missing.

## 3. What exists (verified on this machine)

| Item | Location | Notes |
| --- | --- | --- |
| Encoder core | `hdl/src/encoder/` | `mkBlueJPEG`, AXI4-Stream in (24-bit `{Y, Cb, Cr}`), 8-bit JPEG out, CSRs in `BlueJPEGRegs.bsv`, outputs `irq` and `busy` |
| UART test system | `hdl/src/system/`, `hdl/src/fpga/pa200t/` | Template for structure, counters, pins, PLL, JTAG, constraints, `synth.tcl` |
| Makefile | `hdl/Makefile` | `sim`, `rom`, `bitstream`, `SYNTH=ooc`. Per-test build dirs. Was edited by the user after the last agent session, read it first |
| AXI RAM model | `hdl/test/SimRAM_AXI.bsv`, `hdl/test/bdpi/SimRAM.*` | Bluesim AXI4 slave backed by C++, used by `TestAXIMM2S` |
| AXI stream reader reference | `hdl/src/encoder/AXIMM2S.bsv` | Old reference for an AXI4 read master to stream, do not reuse as is |
| C++ reference encoder | `hdl/test/bdpi/jpeg_encode_ref.cpp`, `sw/` | `jpeg_encode_ref(path, 0, ram, addr)` gives the expected JPEG bytes |
| Ethernet library | `../pa200t/hdl/libraries/ethernet/` | BVI wrappers around `verilog-ethernet` (commit `77320a9`), README documents interfaces and CSR map |
| Board Ethernet module | `../pa200t/hdl/src/PA200T_ETH.bsv` | `mkPA200T_UDP`, `mkPA200T_MDIO`, RGMII pads with IDELAYE2 and IDELAYCTRL |
| Ethernet constraints | `../pa200t/hdl/src/constr/rgmii.xdc`, `mdio.xdc`, `cdc.xdc` | Pins and RTL8211F timing |
| Ethernet flow | `../pa200t/hdl/src/script/synth.tcl` | Sources the `verilog-ethernet` Tcl constraint scripts after synthesis |
| Host bring-up | `../pa200t/hdl/test/helpers.tcl`, `pa200t_udp_setup.tcl`, `udp_bitrate.py` | MDIO init, link wait, address setup at MDIO `0x1000` and ETH `0x2000` |
| Vendor MIG project | `../pa200t/PA200T-Starlite/05.Tutorials and Source Code/1_FPGA/1_FPGA/3_8_PZ_DDR/` | `ddr3_test.srcs/sources_1/ip/mig_7series_0/mig_a.prj` and `PL_DDR_XDC.ucf`. 2x MT41K256M16 (1 GB, 32-bit DQ), 200 MHz system clock "No Buffer", reference clock "Use System Clock", native interface, tCK 2500 ps |
| Xilinx IP pattern | `../alibabacloud/as02mc04/hdl/src/ip/pcie.tcl`, `src/script/as02mc04.tcl`, `src/PCIe.bsv` | Tcl creates the IP and runs its OOC synthesis, a BVI module imports a checked-in wrapper |
| Test image | `assets/sample_1920x1280.bmp` | Crop to 1920x1080 (top rows) for this system |
| Host network | `enp5s0` = 192.168.178.23/24 | Matches the peer address in `pa200t_udp_setup.tcl`, FPGA is 192.168.178.250 |

Board facts: FPGA `xc7a200tfbg484-2`, 200 MHz differential clock on R4/T4 (bank 34, 1.5 V),
reset `RST_N` on R14, LEDs W22/Y22 (active high, confirmed), JTAG header TAP as in
`hdl/src/fpga/pa200t/constr/jtag.xdc`.

## 4. Measured facts that drive the design

- Encoder throughput: 3.98 cycles per pixel at 4:4:4 (0.251 pixels per cycle), measured on the
  board. A 1080p frame is 2,073,600 pixels, so about 8.25 M cycles per frame.
- Critical path of the encoder at the 50 MHz build: 11.3 ns, 12 logic levels, 68 % routing,
  inside the image tiler (`rg_buf_threshold` compare, through `f_line`, to the line buffer BRAM
  write address in `i_pixels`). That allows roughly 85 MHz without changes.
- Frame size in RAM: one pixel per 32-bit word, 8.3 MB. JPEG output is expected at 100 to
  600 kB per frame.

Clock update from implementation: the MIG wizard rejects a 3000 ps period with the fixed
200 MHz board input and substitutes 205.128 MHz. Use its nearby supported setting instead:
`TimePeriod = 3077`, canonical XML `InputClkFreq = 199.995`, and `MMCM_VCO = 650`.
The generated RTL uses `CLKIN_PERIOD = 5000`, PLL multiply 13, input divide 2 and memory
output divide 4. The physical input is exactly 200 MHz, DDR is 325 MHz, and `ui_clk` is
81.25 MHz at 4:1. The build checks the generated 5000 ps input parameter. The fractional
XML input value encodes the wizard's rounding and does not change the physical clock.
The BRAM test uses the original 83.33 MHz PLL clock. Expected frame rate remains 9 to 10 fps.

## 5. Architecture

```
200 MHz pins -> IBUFDS -> BUFG -+-> MIG sys_clk_i (No Buffer) and reference clock
                                +-> PLL: 125 MHz and 125 MHz + 90 degrees (RGMII MAC only)

ui_clk domain (everything else):
  JTAG bus master -> AXI4-Lite bus -> SYS regs, MDIO, ETH regs, JPEG regs
  UDP RX -> loader ----------------+
  JTAG peek/poke ------------------+-> AXI4 master -> MIG -> DDR3
  frame reader <-------------------+
       | 24-bit pixel stream
       v
  mkBlueJPEG (1920 wide, scale 12, 4:4:4, double-buffered tiler, DCT on ui_clk)
       | 8-bit JPEG stream
       v
  packetizer -> UDP TX -> RGMII MAC (own FIFOs cross to 125 MHz) -> PHY
```

The UDP stack's application side runs on `ui_clk`. The MAC FIFOs inside `eth_mac_1g_rgmii_fifo`
do the crossing, so `mkUdpRgmiiAxiLite` is instantiated in the `ui_clk` domain with the PLL
clocks passed as `gtx_clk` and `gtx_clk90` and a reset synchronous to `gtx_clk`.

### 5.1 Layout

```
hdl/libraries/ethernet/           copy of ../pa200t/hdl/libraries/ethernet (not a submodule there)
dep/verilog-ethernet/             submodule, alexforencich/verilog-ethernet at 77320a9
hdl/src/system_udp/               board-independent system
    JpegUdpRegs.bsv               register map
    UdpFrameStore.bsv             AXI4 master: loader writes, reader, verify, peek/poke
    UdpPatternRam.bsv             BRAM-backed AXI slave for milestone 3
    UdpPacketizer.bsv             JPEG byte stream -> UDP packets
    UdpLoader.bsv                 UDP packets -> pixel write commands
    JpegUdpSystem.bsv             ties it together
hdl/src/fpga/pa200t_udp/
    PA200T_UDP_JPEG.bsv           top, clocks, bus map, pins
    PA200T_UDP_PLL.bsv            125 / 125+90 PLL
    PA200T_UDP_ETH.bsv            adapted from ../pa200t/hdl/src/PA200T_ETH.bsv, no traffic generator
    UdpMig.bsv                    BVI import of the MIG wrapper
    ip/mig.prj, ip/mig.tcl, ip/mig_wrapper.v
    constr/{system,jtag,rgmii,mdio,ddr3,cdc}.xdc
    script/synth.tcl
hdl/test/TestJpegUdpSystem.bsv    Bluesim end-to-end test
hdl/test/UdpModel.bsv             test-only UDP endpoint model
hdl/test/host/udp/                load_frame.py, recv_jpeg.py, bluejpeg_udp.tcl, bluejpeg_udp_jlink.tcl
```

`Ethernet.mk` finds `verilog-ethernet` at `../../../dep` relative to the library, which
resolves to `bluejpeg/dep/verilog-ethernet` after the copy. Keep `rtl/udp_checksum_gen.v`
(patched copy) with the library. Add a short README note in the copy that states its origin
and the pa200t commit. The Makefile's library glob then picks it up. Check that the UART
bitstream still builds afterwards (the extra Verilog must not break `make bitstream`).
If it does, include `Ethernet.mk` only for the UDP system.

Makefile: add a selector `SYSTEM=udp` that switches `MAIN_MODULE` to
`fpga/pa200t_udp/PA200T_UDP_JPEG`, `TOP_MODULE` to `mkPA200T_UDP_JPEG_Top`, `PROJECT_NAME` to
`BlueJPEG_PA200T_UDP`, `SCRIPT` to the new `synth.tcl`, and add `system_udp` and
`fpga/pa200t_udp` to `EXTRA_BSV_LIBS`. Target: `make bitstream SYSTEM=udp`. The two systems'
package names must not collide (all new packages carry `Udp` or `UDP` in the name).

### 5.2 Encoder change (the only edit in `hdl/src/encoder/`)

Repeat mode needs to start frames without a JTAG write. Add to `BlueJPEG_ifc`:

```bsv
//request a frame, same effect as writing CTRL.START
method Action start_frame();
```

Implement it as a pulse ORed into the start condition of `r_start` (the CSR bit keeps
working, a request while a frame runs is dropped). Rerun the encoder regression (section 8).

### 5.3 Frame store (`UdpFrameStore.bsv`)

One AXI4 master (address 30 bits, data 32 bits, ID 4 bits, check the widths the MIG offers
and adapt) with these clients. Only one is active at a time, enforced by a small mode FSM:

- **Reader**: on `start(npix)` reads `npix` words from `BASE` in 256-beat INCR bursts and
  emits `AXI4_Stream_Pkg#(24, 0)` beats with `last` on the final pixel. Fully backpressured.
  Issue at most 2 bursts ahead and hold data in a FIFO sized for them (BRAM FIFO, 512 entries).
- **Loader port**: `Put#(Tuple2#(UInt#(32), Bit#(24)))` (pixel index, pixel). Writes single
  words or short bursts. Simple is fine, loading speed is not critical.
- **Verify**: on a register trigger reads `npix` words and computes two 32-bit sums,
  `s1 += word` and `s2 += s1` (both wrap). Exposes both and a done flag.
- **Peek/poke**: registers `MEMADDR`, `MEMDATA` for single word read and write over JTAG.

Word format: `{8'h00, Y, Cb, Cr}`, word index = pixel index in raster order.

### 5.4 Loader protocol (host -> FPGA, UDP destination port 5000)

Payload: 4 bytes big-endian first pixel index, then N x 3 bytes `Y, Cb, Cr`, N <= 480
(1444 bytes, inside the 1472-byte MTU limit). Packets are idempotent, so the host may resend.
`UdpLoader` accepts packets only while `CTRL.LOADEN` is set and the system is idle, drops
packets with a length that is not `4 + 3k`, and counts accepted packets, accepted pixels and
dropped packets. It must always consume both the RX header and the payload so the stack
keeps moving (see the Ethernet README).

### 5.5 Egress protocol (FPGA -> host, UDP destination port 5001)

Each packet: 8-byte header, then 1 to 1024 JPEG bytes.

| Byte | Field |
| --- | --- |
| 0 | magic `0x4A` |
| 1 | flags, bit 0 = last packet of the frame |
| 2..3 | frame number, big-endian, wraps |
| 4..5 | sequence number in the frame, big-endian, starts at 0 |
| 6..7 | payload length, big-endian |

`UdpPacketizer` collects bytes in a 1024-entry BRAM FIFO, and when it holds 1024 bytes or the
byte with `tlast`, sends `UdpTxRequest { payload_length: n + 8, checksum: 0 }`, then the
header, then the bytes with `last` on the final one. Stream beats follow the Ethernet README
(`keep = 1`, `dest = 0`, `id = 0`). The checksum generator buffers a whole packet, so check
that the `UdpParameters` FIFO depths hold 1032 bytes. Backpressure from the stack stalls the
encoder, which is safe because the source is RAM.

### 5.6 Register map of the system (`JpegUdpRegs.bsv`, module ID `0x003`)

| Offset | Register | Fields |
| --- | --- | --- |
| 0x00 | MIV | module ID 0x003, version |
| 0x04 | CTRL | `[0]` START (one frame, hardware clears), `[1]` REPEAT (frame after frame while set), `[2]` LOADEN, `[3]` VERIFY (trigger, hardware clears) |
| 0x08 | STS | `[0]` busy, `[1]` DDR3 calibration done, `[2]` verify done, `[3]` reader active, `[4]` loader active, `[5]` sticky AXI memory error |
| 0x0C | NPIX | pixels per frame, reset 2,073,600 |
| 0x10 | BASE | word address of the frame, reset 0 |
| 0x14 | MEMADDR | peek/poke word address |
| 0x18 | MEMDATA | read = peek, write = poke |
| 0x20 | CHK1 | verify sum s1 |
| 0x24 | CHK2 | verify sum s2 |
| 0x28 | LDPKT | loader packets accepted |
| 0x2C | LDPIX | loader pixels written |
| 0x30 | LDDROP | loader packets dropped |
| 0x40 | FRAMES | frames completed since reset |
| 0x44 | INCYC | input window of the last frame, first to last pixel |
| 0x48 | INSTL | input stalls in that window |
| 0x4C | OUTB | JPEG bytes of the last frame |
| 0x50 | OUTCYC | output window of the last frame |
| 0x54 | OUTSTL | cycles with a JPEG byte offered but the packetizer full |
| 0x58 | TOTAL | frame start to last JPEG byte |
| 0x5C | PKTS | UDP packets sent for the last frame |
| 0x60 | PERIOD | cycles between the last two frame starts (repeat mode) |

Counter semantics and implementation follow `hdl/src/system/JpegTestRegs.bsv` and the
`r_monitor` rule in `JpegTestSystem.bsv`. The encoder's own PERF0 to PERF6 stay available.
The system does not configure the encoder. The host writes `IMSZ` and `IRQE` in the
encoder map once, and the system only calls `start_frame`.

Frame sequence: START or REPEAT and idle -> `enc.start_frame`, reader `start(NPIX)`, counters
restart -> frame ends when the packetizer has sent the packet with the last flag -> FRAMES
increments, and with REPEAT set the next frame starts.

### 5.7 Bus map of the board top

| Base | Size | Target |
| --- | --- | --- |
| 0x0000 | 0x1000 | SYS (`JpegUdpRegs`) |
| 0x1000 | 0x1000 | MDIO (`mkPA200T_MDIO`) |
| 0x2000 | 0x1000 | ETH (UDP/IP endpoint registers) |
| 0x4000 | 0x2000 | JPEG (encoder) |

MDIO and ETH sit where the pa200t design has them, so `helpers.tcl` procedures
(`bluej_mdio_init`, `bluej_phy_wait_link`, `bluej_eth_setup`, `bluej_eth_status`) work
unchanged. Copy `helpers.tcl` completely this time (the UART system only has its first part).

LEDs: LED0 = encoder interrupt, LED1 = DDR3 calibration done.

### 5.8 MIG integration

1. Copy the vendor `mig_a.prj` to `ip/mig.prj` and change: `PortInterface` to `AXI`,
   `TimePeriod` to 3077 with the clock settings documented in section 4, AXI data width 32, AXI ID width 4, keep "No Buffer" system clock,
   "Use System Clock" reference, active-low reset, and the vendor pin selection. The simplest
   reliable way to get a valid AXI `.prj` is to open the MIG wizard once in a scratch Vivado
   project from the vendor `.prj`, change those settings and save. Verify the result still
   lists the same pins as `PL_DDR_XDC.ucf`.
2. `ip/mig.tcl` follows `as02mc04/hdl/src/ip/pcie.tcl`: `create_ip -name mig_7series`,
   `set_property CONFIG.XML_INPUT_FILE`, generate targets, run the IP's OOC synthesis.
   `script/synth.tcl` sources it before `synth_design`, as `as02mc04.tcl` does.
3. `ip/mig_wrapper.v`: fixed port names around the generated `mig_7series_0`, ties off
   `app_sr_req`, `app_ref_req`, `app_zq_req`, exports `ui_clk`, an active-low reset derived
   from `ui_clk_sync_rst`, `init_calib_complete`, and the AXI4 slave.
4. `UdpMig.bsv`: BVI import in the style of `as02mc04/hdl/src/PCIe.bsv`. `output_clock ui_clk`,
   `output_reset` on it, AXI slave methods in the `ui_clk` domain, DDR3 pins as `inout` and
   output ports that pass to the top. The DDR3 pins never go through BSV logic.
5. `constr/ddr3.xdc` is not needed if the MIG's own generated XDC is read with the IP
   (it carries pins and I/O standards). Do not duplicate it.
6. IDELAYCTRL: the MIG instantiates its own with an `IODELAY_GROUP`. The RGMII RX IDELAYE2
   cells and their IDELAYCTRL in `PA200T_UDP_ETH` need their own group, set with
   `set_property IODELAY_GROUP rgmii_rx_grp` on those cells in `rgmii.xdc`. Both use 200 MHz.
7. The 200 MHz BUFG feeds the MIG and the 125 MHz PLL. `cdc.xdc`: `ui_clk` domain, the two
   PLL clocks (one group, their 90 degree relation matters), `jtag_tck` and `clk_200` are
   asynchronous groups. Leave `rgmii_rxc` out of the groups, as the pa200t `cdc.xdc` explains.

### 5.9 Host tools (`hdl/test/host/udp/`)

- `bluejpeg_udp.tcl`: register helpers like `bluejpeg.tcl` for the new map (IDs, wait for
  calibration, encoder setup for 1920x1080 with `IRQE`, start, repeat on and off, verify,
  report with pixels per cycle, frame time and fps from `PERIOD`).
- `bluejpeg_udp_jlink.tcl`: J-Link session. PHY reset, link wait, address setup, then the helpers.
- `load_frame.py`: BMP -> crop to 1920x1080 -> YCbCr with exactly the reference conversion
  (the same arithmetic as `rgb2ycbcr_ref` in `hdl/test/bdpi/RGB2YCbCr.cpp`, so the FPGA result
  matches the C++ encoder byte for byte) -> paced UDP packets -> trigger VERIFY over OpenOCD,
  compare CHK1 and CHK2, resend on mismatch. Standard library only.
- `recv_jpeg.py`: listens on port 5001, reassembles by frame and sequence number, reports
  lost packets, writes `frame_<n>.jpg`, optional `--expect` byte comparison, prints fps.
- Reference JPEG for the board: build `sw/` (`encode_bitaccurate <bmp> <name> 444`) on the
  cropped image, or take it from the 1080p Bluesim run.

## 6. Simulation

`TestJpegUdpSystem` instantiates `mkJpegUdpSystem` with `SimRAM_AXI` as the RAM and
`UdpModel` on the UDP boundary (the real stack is Verilog and not in Bluesim). The boundary
uses the library's own types (`UdpTxRequest` from `UdpRgmiiCsr.bsv` and `UdpRxHeader` from
`EthernetTypes.bsv`, both pure BSV)
and byte stream fabrics, so the board top connects the real stack without glue.

The test: load a frame through the loader protocol (include one duplicated and one malformed
packet), run VERIFY and check the sums, start one frame, reassemble the packets, compare with
`jpeg_encode_ref`, then run two frames in repeat mode and check they are identical and that
FRAMES and PERIOD are right. Print all counters.

Frame size is a test parameter: 192x192 by default (fast), 1920x1080 with
`-D UDP_TEST_1080P` (about 25 M cycles including load, run it once per milestone).

## 7. Milestones and acceptance

| # | Deliverable | Accept when |
| --- | --- | --- |
| 0 | Repository check | `git submodule status` is clean. At the time of writing `dep/bluefabric`, `dep/bluej`, `dep/blueuart`, `dep/bluexlnx` show as untracked although `.gitmodules` lists them. Report this to the user before adding more submodules |
| 1 | Ethernet library copied, `dep/verilog-ethernet` added, encoder `start_frame` | Encoder regression passes, `make bitstream` (UART) still elaborates |
| 2 | `system_udp` with `TestJpegUdpSystem` | 192x192 and one 1080p run match the C++ reference byte for byte, no new warnings |
| 3 | Board top without MIG: RAM replaced by a BRAM-backed AXI slave holding the 192x192 pattern | Bitstream meets timing at 83.33 MHz (or the fallback). On the board, with user approval: link up, JPEG received over UDP and identical to the reference |
| 4 | MIG added | Bitstream meets timing, no critical warnings. On the board: calibration done (LED1), peek/poke works, load + VERIFY sums match |
| 5 | Full 1080p | Single frame identical to the reference, repeat mode runs for 100 frames with no lost packets, counters and fps reported |

Milestone 3 exists to prove Ethernet, the packetizer and the 83 MHz clock before the MIG
adds its own risks. For it, generate the system clock from a PLL at the target frequency.

## 8. Regression to rerun after touching shared code

`TestBlueJPEG`, `TestBlueJPEGGray`, `TestBlueJPEGConsecutive`, `TestBlueJPEGGrayConsecutive`,
`TestBlueJPEGGrayBackpressure`, `TestJPEGBitAccuracy`, `TestJpegSystem`, `TestQuantize`,
`TestRLE`, `TestJPEGBitstream`, `TestDCT2D`, `TestDUProc`, `TestZigZag`, `TestBitAccuracy`,
`TestDUDispatcher`, `TestImageTiling`. All pass at the time of writing.
`TestsMainTest` and `TestTransposeBuffer` are known broken and not part of it.
Tests build in separate directories, so they can run in parallel (3 at a time is safe with
Vivado idle, memory is tight while Vivado runs).

## 9. Risks and fallbacks

1. **Encoder timing.** Implementation now meets timing at 83.33 MHz with BRAM and 81.25 MHz
   with MIG. Any higher clock still needs a new implementation and timing check. Keep
   throughput changes separate from this system bring-up.
2. **MIG bring-up.** Calibration failure usually means a wrong `.prj` (pins, part, VCCAUX_IO)
   or clocking. Compare against the vendor example, which is known to work on this board.
3. **Two IDELAYCTRLs.** See 5.8 item 6. A DRC error about ungrouped IDELAY cells means the
   group property did not reach the RGMII cells.
4. **Packet loss on egress.** The receiver detects it. If it happens in repeat mode, raise the
   host socket buffer first, then add an inter-packet gap register.
5. **Throughput optimization is separate from bring-up.** The board measured 4.023 cycles
   per pixel and 9.7405 fps at 1080p. The user's follow-up requested resource and throughput
   analysis, recorded in [udp-encoder-analysis.md](udp-encoder-analysis.md). Changes to
   pipeline throughput still need their own implementation and regression work.

## 10. Open points for the user

- Whether the BRAM-backed pattern source of milestone 3 stays as a permanent option.
- Whether the Ethernet library should become a shared repository instead of a copy.
