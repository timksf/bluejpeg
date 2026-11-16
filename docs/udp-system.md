# DDR3/UDP system

The UDP system runs the encoder on the PA200T board (Artix-7 `xc7a200tfbg484-2`) with a frame store
in DDR3 and Gigabit Ethernet for input and output. A host loads raster YCbCr frames over UDP, the
system reads a frame back, encodes it and returns the JPEG as numbered UDP datagrams. Frames can be
encoded once or repeatedly, which makes the system a throughput test bench for the encoder as well
as a demonstration. The board-independent part lives in `hdl/src/system_udp`, the board top with
clocks, pins and constraints in `hdl/src/fpga/pa200t_udp`.

## Build variants

| Variant | Make options | Frame store | Clocking |
| --- | --- | --- | --- |
| DDR3 | `SYSTEM=udp` | DDR3 through MIG | Everything on the MIG user clock, 81.25 MHz |
| BRAM | `SYSTEM=udp UDP_MEMORY=bram` | BRAM holding the 192 × 192 test pattern | Everything on 83.333 MHz |
| Split clocks | `SYSTEM=udp UDP_DEMO_200=1` | DDR3 behind a clock crossing | Encoder 200 MHz, DCT 25 MHz, system 125 MHz, memory 81.25 MHz |

The split-clock variant reaches 1080p30 and is described in [1080p30-demo.md](1080p30-demo.md). In
all variants the RGMII MAC runs on 125 MHz transmit clocks, including a 90 degree shifted copy, and
crosses into the application clock through its own asynchronous frame FIFOs. The MAC from
`hdl/libraries/ethernet` adds synchronizers for its enable controls and its inter-frame gap setting
for that purpose, and the RGMII input delay cells use their own `IODELAY_GROUP` next to the one of
the MIG.

The MIG project in `hdl/src/fpga/pa200t_udp/ip` uses the 325 MHz DDR setting, the closest the wizard
offers for the board's 200 MHz input clock. Its generated RTL specifies a 5000 ps input period with
a PLL multiplier of 13 and a divider of 2, so the physical 200 MHz board clock is used exactly, and
the build checks that parameter. The MIG also supplies all DDR pin constraints.

## Data path

```text
JTAG bus master -> AXI4-Lite bus -> SYS, MDIO, ETH and JPEG registers

UDP RX -> loader -----------+
JTAG peek and poke ---------+-> frame store (AXI4 master) -> DDR3
frame reader <--------------+
     | 24-bit pixels
     v
BlueJPEG (1920 wide, 4:4:4, 12-bit precision, double-buffered tiler)
     | JPEG bytes
     v
packetizer -> UDP TX -> RGMII MAC -> PHY
```

The frame store gives the memory to one client at a time. The reader fetches a frame in INCR bursts
of up to 256 words that never cross a 4 KiB boundary, keeps at most two bursts in flight and buffers
them in a 512-entry BRAM FIFO, so DDR3 latency does not reach the encoder. Verification reads a
frame and computes two wrapping 32-bit sums, the sum of all words and the sum of the running sums,
which the host compares with its own values. Loader writes and single-word peek and poke accesses
complete only after the AXI write response. A frame word is `{8'h00, Y, Cb, Cr}`, and its word
address is the pixel index in raster order plus `BASE`.

The loader validates a whole datagram before it writes anything, including its length, the stream
side-band and the pixel range. A rejected datagram is drained without touching memory, so repeated
datagrams are harmless and malformed ones have no effect. The packetizer collects up to 1024 JPEG
bytes per datagram in a 2048-byte BRAM FIFO, so the next packet is collected while the previous one
is transmitted, and it publishes a packet only once all its bytes are stored.

## Wire formats

Loader datagrams go to UDP port 5000. Their payload starts with the index of the first pixel as a
32-bit big-endian number, followed by 1 to 480 pixels of three bytes each, `Y`, `Cb`, `Cr`.
Datagrams are accepted only while `CTRL.LOADEN` is set and the system is idle.

JPEG datagrams go to UDP port 5001 and carry an eight-byte header followed by 1 to 1024 JPEG bytes.

| Byte | Field |
| --- | --- |
| 0 | Magic `0x4A` |
| 1 | Flags, bit 0 marks the last packet of a frame |
| 2 and 3 | Frame number, big-endian, wraps |
| 4 and 5 | Sequence number within the frame, big-endian, starting at 0 |
| 6 and 7 | JPEG payload length, big-endian |

## Bus map and registers

| Base | Size | Target |
| --- | --- | --- |
| `0x0000` | `0x1000` | SYS, the system registers in `JpegUdpRegs.bsv` (module ID 3) |
| `0x1000` | `0x1000` | MDIO controller |
| `0x2000` | `0x1000` | ETH, the UDP/IP endpoint registers |
| `0x4000` | `0x2000` | JPEG, the encoder registers listed in the top-level README (module ID 1) |

| Offset | Register | Contents |
| --- | --- | --- |
| `0x00` | MIV | Module ID and version |
| `0x04` | CTRL | Bit 0 START requests one frame and clears itself, bit 1 REPEAT encodes frame after frame while set, bit 2 LOADEN accepts loader datagrams, bit 3 VERIFY computes the checksums and clears itself |
| `0x08` | STS | Bit 0 frame running, bit 1 DDR3 calibrated, bit 2 verify done, bit 3 reader active, bit 4 loader active, bit 5 sticky AXI memory error |
| `0x0c` | NPIX | Pixels per frame, 2,073,600 after reset |
| `0x10` | BASE | Word address of the frame |
| `0x14` | MEMADDR | Word address for MEMDATA |
| `0x18` | MEMDATA | Reads and writes the word at MEMADDR, with byte strobes, and returns SLVERR while busy or out of range |
| `0x20`, `0x24` | CHK1, CHK2 | Verification sums |
| `0x28`, `0x2c`, `0x30` | LDPKT, LDPIX, LDDROP | Accepted loader datagrams, written pixels and dropped datagrams |
| `0x40` | FRAMES | Frames completed since reset, counted when the last packet crosses the UDP interface |
| `0x44`, `0x48` | INCYC, INSTL | Input window from the first to the last accepted pixel, and its cycles with a pixel offered but not accepted |
| `0x4c` | OUTB | JPEG bytes of the frame |
| `0x50`, `0x54` | OUTCYC, OUTSTL | Output window from the first to the last JPEG byte, and its cycles with a byte offered but not accepted |
| `0x58` | TOTAL | Frame start to the last JPEG byte |
| `0x5c` | PKTS | UDP packets of the frame |
| `0x60` | PERIOD | Cycles between the last two frame starts |

The system does not configure the encoder. The host writes the encoder's `IMSZ` and `IRQE` once, and
the system then starts frames through the encoder's `start_frame` method. LED0 shows the encoder
interrupt and LED1 DDR3 calibration.

## Building and simulating

All commands run from the repository root inside the Nix shell (`nix develop ./nix`), which supplies
Bluespec, GCC, Icarus Verilog, OpenOCD and Tcl. Bitstreams also need Vivado on the path. The pinned
BSVTools version needs `hdl/patches/bsvtools-vivado-exit.patch` so that Vivado failures stop the
build.

```sh
git -C dep/BSVTools apply ../../hdl/patches/bsvtools-vivado-exit.patch
make -C hdl sim RUN_TEST=TestJpegUdpSystem                     # 192 × 192 end-to-end test
make -C hdl sim RUN_TEST=TestJpegUdpSystem UDP_TEST_1080P=1 BUILDDIR=build/TestJpegUdpSystem1080   # 1920 × 1080
make -C hdl sim RUN_TEST=TbUdpPacketizer                       # packet lengths, stalls, overlap
python3 -m unittest discover -s hdl/test/host/udp -p 'test_*.py' -v
make -C hdl/libraries/ethernet/test test
make -C hdl bitstream SYSTEM=udp                               # DDR3 variant
make -C hdl bitstream SYSTEM=udp UDP_MEMORY=bram               # BRAM variant
```

`TestJpegUdpSystem` loads a frame over the modelled UDP interface, including a duplicate and a
malformed datagram, checks peek and poke and both checksums, encodes one frame and two repeated
frames and compares every JPEG byte with the C++ reference. The 1080p fixture is a crop of
`assets/sample_1920x1280.bmp`.

## Running on the board

The FPGA is configured through the board's FT232H into SRAM, the configuration flash is not
written. Register access goes through a J-Link on the custom JTAG header. The session scripts reset
and initialize the PHY, set up the UDP endpoint, configure the encoder once and keep OpenOCD running
with Tcl RPC on port 6666. The network addresses default to those in `bluejpeg_udp_jlink.tcl` and
can be overridden through the `udp_*` variables.

```sh
openocd -f hdl/test/host/udp/pa200t_load.tcl -c 'pld load 0 /path/to/image.bit' -c shutdown
openocd -f hdl/test/host/udp/bluejpeg_udp_jlink.tcl
```

The BRAM variant needs the frame size and counter clock overridden.

```sh
openocd -c 'set udp_width 192' -c 'set udp_height 192' -c 'set bluejpeg_udp_hz 83333333.333333' -f hdl/test/host/udp/bluejpeg_udp_jlink.tcl
```

For the DDR3 variants, `load_frame.py` crops a BMP to 1920 × 1080, converts it to YCbCr with the same
float32 arithmetic as the C++ reference, sends it in paced datagrams, triggers VERIFY and resends the
whole frame if the checksums differ. `--prepare-only` checks the crop and conversion without network
or JTAG access. `recv_jpeg.py` reassembles datagrams by frame and sequence number, reports gaps,
handles duplicates, writes `frame_<number>.jpg` and with `--expect` requires an exact byte match.
Start the receiver before requesting frames. The 1080p simulation above produces the reference JPEG.

```sh
python3 hdl/test/host/udp/recv_jpeg.py --output udp-rx --expect hdl/build/TestJpegUdpSystem1080/udp_capture.jpg --count 100
python3 hdl/test/host/udp/load_frame.py assets/sample_1920x1280.bmp
```

The OpenOCD console then starts single frames or repeat mode and prints the counters. Clearing REPEAT
lets the current frame finish.

```tcl
bluejpeg_udp_start pa200t.tap
bluejpeg_udp_repeat pa200t.tap 1
bluejpeg_udp_repeat pa200t.tap 0
bluejpeg_udp_report pa200t.tap
```

## Results

Both single-clock variants meet timing, the DDR3 variant at 81.25 MHz with +0.343 ns setup and
+0.008 ns hold slack and the BRAM variant at 83.333 MHz with +0.306 ns setup slack. The complete
DDR3 design uses 19,917 LUTs, 18,759 registers, 33 BRAM tiles and 11 DSPs, of which the encoder
takes the share listed in [udp-encoder-analysis.md](udp-encoder-analysis.md). On the board the PHY
links at 1 Gb/s full duplex, DDR3 calibrates and loaded frames verify against the host checksums.
Single frames and runs of 100 repeated frames matched the C++ reference byte for byte for both the
192 × 192 pattern and the 1920 × 1080 frame, the latter at 290,450 bytes in 284 packets per frame,
without lost packets or protocol errors.
