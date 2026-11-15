# PA200T JPEG UDP system

The UDP system is separate from the existing UART design. It loads raster YCbCr
pixels into a frame store, encodes 4:4:4 JPEG, and sends numbered UDP packets.
The default FPGA build uses the board's DDR3 through MIG. A BRAM variant retains
the 192×192 pattern for Ethernet validation.

The experimental 200 MHz encoder / 125 MHz UDP DDR3 build and 1080p30 tests are described
in [1080p30 demonstration](1080p30-demo.md). That split-clock image is now
running at 31.95 fps on the board, with a live frame-counter preview.

Enter the development environment from the repository root:

```sh
nix develop ./nix
```

The flake supplies Bluespec, GCC, Icarus Verilog, OpenOCD and Tcl. Vivado must also
be on PATH. The system compiler outside this shell is too old for these builds.

The native BSVTools `vivado_tcl` path needed a fix to propagate Tcl failures and
Vivado exit status. It is applied locally in `dep/BSVTools` and preserved in
`hdl/patches/bsvtools-vivado-exit.patch`. On a fresh checkout of the pinned dependency:

```sh
git -C dep/BSVTools apply ../../hdl/patches/bsvtools-vivado-exit.patch
```

No commits are created by the build or validation flow.

## Build and simulate

```sh
make -C hdl sim RUN_TEST=TestJpegUdpSystem
make -C hdl sim RUN_TEST=TestJpegUdpSystem UDP_TEST_1080P=1 BUILDDIR=build/TestJpegUdpSystem1080Opt CXX_NO_OPT= PARALLEL_SIM_LINK=1
python3 -m unittest discover -s hdl/test/host/udp -p 'test_*.py' -v
make -C hdl/libraries/ethernet/test test
make -C hdl bitstream SYSTEM=udp UDP_MEMORY=bram
make -C hdl bitstream SYSTEM=udp
```

The 1080p simulation crops the top rows of `assets/sample_1920x1280.bmp` into a
build-local fixture. It checks the loader, a duplicate and a malformed datagram,
peek/poke, both checksums, one frame and two repeat frames. Every JPEG byte is
compared with the C++ reference. PERIOD is checked against observed start edges.

The FPGA variants have separate build directories:

| Variant | Directory | Application clock |
| --- | --- | --- |
| BRAM | `hdl/build/BlueJPEG_PA200T_UDP_bram/BlueJPEG_PA200T_UDP/` | 83.333 MHz |
| DDR3 | `hdl/build/BlueJPEG_PA200T_UDP_mig/BlueJPEG_PA200T_UDP/` | 81.25 MHz |

Both use 125 MHz GTX clocks, including a 90 degree TX clock, and the MAC's own
asynchronous frame FIFOs. The copied MAC adds synchronizers for enable controls
and stable IFG configuration. RGMII IDELAY cells have their own IODELAY_GROUP.

The MIG wizard's exact 3000 ps setting cannot use this board's 200 MHz input.
The checked-in project uses its supported 325 MHz DDR setting. Its canonical XML
frequency is rounded to 199.995 MHz, but generated RTL specifies a 5000 ps input
and PLL multiply 13, divide 2. This uses the physical 200 MHz board clock exactly.
The build checks that input parameter. All 71 DDR pin assignments match the vendor
project. MIG supplies the DDR constraints, so there is no duplicate DDR XDC.

## Board sessions

Programming and hardware access require explicit user approval. Configuration uses
the on-board FT232H and loads FPGA SRAM. It does not write configuration flash.

```sh
openocd -f hdl/test/host/udp/pa200t_load.tcl -c 'pld load 0 /absolute/path/to/image.bit' -c shutdown
```

Registers use a separate J-Link connected to the custom JTAG header. The BRAM
session must override the frame dimensions and report clock:

```sh
openocd -c 'set udp_width 192' -c 'set udp_height 192' -c 'set bluejpeg_udp_hz 83333333.333333' -f hdl/test/host/udp/bluejpeg_udp_jlink.tcl
```

For the DDR3 image, use the default 1920×1080 session:

```sh
openocd -f hdl/test/host/udp/bluejpeg_udp_jlink.tcl
```

These sessions initialize the PHY and endpoint, configure the encoder once, and
leave OpenOCD running. Tcl RPC is on port 6666. The default FPGA address is
192.168.178.250 and the peer is 192.168.178.23. Override the `udp_*` variables
before sourcing the session file when using a different network.

Start the receiver before requesting a frame. For the BRAM image, the reference
is `hdl/build/TestJpegUdpSystem/udp_capture.jpg`:

```sh
python3 hdl/test/host/udp/recv_jpeg.py --output /tmp/bluejpeg-rx --expect hdl/build/TestJpegUdpSystem/udp_capture.jpg --count 1
```

In OpenOCD's Tcl console:

```tcl
bluejpeg_udp_start pa200t.tap
bluejpeg_udp_report pa200t.tap
```

For DDR3, load and verify the image first:

```sh
python3 hdl/test/host/udp/load_frame.py assets/sample_1920x1280.bmp --write-crop /tmp/bluejpeg-1080.bmp
python3 hdl/test/host/udp/recv_jpeg.py --output /tmp/bluejpeg-rx --expect hdl/build/TestJpegUdpSystem1080Opt/udp_capture.jpg --count 100
```

The loader paces packets, triggers VERIFY through OpenOCD, compares CHK1/CHK2, and
resends the complete frame on mismatch. It uses Python's standard library and
rounds each color-conversion operation to float32 like `rgb2ycbcr_ref`. Cropped
BMP output is compatible with the C++ reference encoder. `--prepare-only` checks
the crop and conversion without network or JTAG access.

```tcl
bluejpeg_udp_repeat pa200t.tap 1
bluejpeg_udp_repeat pa200t.tap 0
bluejpeg_udp_report pa200t.tap
```

Clearing REPEAT lets the current frame finish. The receiver detects gaps,
reorders packets, handles identical duplicates, and saves complete frames as
`frame_<number>.jpg`. `--expect` requires an exact byte match.

## Registers and wire formats

The complete register and protocol tables are in
[the implementation plan](udp-system-plan.md). The board map is SYS at 0x0000,
MDIO at 0x1000, ETH at 0x2000 and JPEG at 0x4000. SYS module ID is 3 and JPEG ID
is 1. BASE and MEMADDR are word addresses. A frame word is `{0, Y, Cb, Cr}`.
MEMDATA accesses wait for an AXI response and support write strobes. Busy or
out-of-range debug accesses return SLVERR. STS bit 5 latches an AXI memory error.

Loader UDP destination port is 5000. Each payload starts with a big-endian pixel
index followed by 1–480 three-byte pixels. The complete packet is validated before
writes begin. Disabled, malformed and out-of-range packets are consumed and dropped.

JPEG destination port is 5001. Each payload has an eight-byte header containing
magic 0x4A, final-packet flag, frame number, sequence and JPEG payload length.
Packets contain 1–1024 JPEG bytes. FRAMES advances when the final packet crosses
the UDP boundary. TOTAL ends at the last JPEG byte accepted from the encoder.

## Verified results

- All 16 encoder regressions in the plan passed in Nix.
- The UART bitstream built with +1.380 ns setup slack.
- The 192×192 system test passed with three identical 3,560-byte JPEGs.
- The 1920×1080 system test passed with three identical 290,450-byte JPEGs,
  284 packets per frame, and matching VERIFY sums.
- The revised 1080p run reported INCYC 8,584,287, OUTSTL 647,949, TOTAL 8,704,140
  and PERIOD 8,705,650 cycles. These are simulation results, not measured board fps.
- All six copied Ethernet library regressions passed, including independent-clock
  RGMII loopback, MDIO, checksum generation and line-rate traffic.
- Six host/build tests passed, including 10,472 C++ conversion comparisons and
  failure propagation from Vivado.
- The final BRAM image met timing at 83.333 MHz with +0.306 ns setup and +0.020 ns
  hold. An earlier +0.260 ns image was loaded through FT232H with user approval.
- The board PHY linked at 1 Gb/s full duplex. One 3,560-byte JPEG and 100 consecutive
  repeat frames matched the C++ reference exactly, with four UDP packets per frame.
  Warm-cache PERIOD was 148,706 cycles, or 560.39 frames/s for this small pattern.
  The initial frame included approximately two seconds of address-resolution delay.
- The final MIG image met timing at 81.25 MHz with +0.343 ns setup and +0.008 ns
  hold. Timing reports have no failing or unconstrained internal endpoints.
  It uses 19,917 LUTs, 18,759 registers, 33 BRAM tiles and 11 DSPs.
- DDR3 calibrated on the board. Full-word peek/poke and byte strobes passed.
  The loaded frame verified as CHK1 `a8b8c3b7` and CHK2 `b4f30067`. One missing
  packet during the initial load was recovered by the loader's automatic full-frame
  resend. The second pass matched both checksums.
- One DDR3-backed 1080p frame and exactly 100 repeat frames matched the C++ reference,
  all 290,450 bytes and 284 packets per frame, with no lost egress packets. Repeat
  was disabled during the final frame and FRAMES ended at 101 including the single run.
  The repeat test had no protocol errors, TX underflows or FIFO overflows.
- Measured continuous PERIOD is 8,341,457 cycles at 81.25 MHz, or 102.664 ms and
  **9.7405 fps**. The loaded image remains in volatile FPGA configuration and repeat is off.

| Hardware counter | Last 1080p repeat frame |
| --- | ---: |
| INCYC | 8,230,178 |
| INSTL | 6,156,578 |
| OUTB | 290,450 |
| OUTCYC | 8,340,782 |
| OUTSTL | 273,213 |
| TOTAL | 8,340,786 |
| PKTS | 284 |
| PERIOD | 8,341,457 |

Captures and machine-readable counters are under `hdl/build/board_udp_1080/`.
The JPEG SHA-256 is `1382540698d9494fec8bdabfe190ec3e5e7ada5d6d0b22e19e5d9f22a687f067`.

See [encoder resource, timing and throughput analysis](udp-encoder-analysis.md)
for the standalone encoder counts, routed critical paths and continuous fps limits.
