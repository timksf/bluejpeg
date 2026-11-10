## bluejpeg

A configurable JPEG encoder written in Bluespec SystemVerilog (BSV).
The goal is to provide a parameterizable encoder "generator" that can produce
synthesizable Verilog JPEG encoders tailored to specific hardware-budget and
image-size requirements - change a few compile-time parameters, rebuild, and get
a ready-to-use core.

[Hardware architecture diagram](assets/architecture/bluejpeg-architecture.pdf)

### Compile-time parameters

| Parameter       | Purpose                                            | Example    |
| --------------- | -------------------------------------------------- | ---------- |
| `max_img_width` | Maximum supported image width, sets BRAM sizing    | 1920       |
| `dct_scale`     | Internal DCT fixed-point bit width                 | 12, 14, 16 |
| `quant_scale`   | Quantization arithmetic bit width                  | 12, 14, 16 |
| `pixel_width`   | Input component sample width (currently JPEG: 8)   | 8          |

The hardware supports full-resolution 4:4:4 colour or compile-time grayscale.
The DU frontend is tiler → channel splitter → dispatcher.

### Runtime configuration (AXI4-Lite)

| Offset | Register | Description                                    |
| ------ | -------- | ---------------------------------------------- |
| 0x00   | MIV      | Module ID and version                          |
| 0x04   | CTRL     | `[0]` start                                    |
| 0x08   | STS      | `[0]` ready, `[1]` codegen busy, `[4]` done      |
| 0x0C   | IMSZ     | `[15:0]` width, `[31:16]` height                 |
| 0x14   | CGEN     | `[1:0]` table type, `[31]` trigger (only needed after writing custom Huffman tables, because default codes are generated after reset) |
| 0x18   | IRQP     | Pending, W1C: `[0]` frame done, `[1]` invalid config (latched even when disabled) |
| 0x1C   | IRQE     | Enable, same bit layout. Enabled pending bits drive the `irq` output |
| 0x30–0x38 | PERF0–2 | Running cycles, input pixels, output bytes    |
| 0x3C   | PERF3    | Running cycles without an accepted input pixel |
| 0x40   | PERF4    | Flush cycles, last data unit to frame done     |
| 0x44   | PERF5    | Frame cycles, accepted start to done (configure + running + flush) |
| 0x48   | PERF6    | Boot cycles, reset to tables ready (not cleared per frame) |
| 0x100+ | TABLE WR | Quantization / Huffman table data writes       |

---

### Implementation status

#### Pipeline

- [x] 8×8 block tiling - `mkImageTilingEngine` (BRAM line-buffer, configurable max width, optional double buffering)
- [x] Channel splitting - `mkChannelSplitter` (Y / Cb / Cr)
- [x] DU dispatch - `mkDUDispatcher` (one Y, Cb, Cr block per 8×8 MCU, internal chroma FIFOs)
- [x] Image Tiler optional (can be implemented with 2D DMA engines)

#### DU processing (`mkDUProc`)

- [x] 2D DCT (AAN algorithm) - `mkDCT1D`, `mkDCT2D`, `mkDCT2D_Opt`
  - Separated row/column 1D transforms, 5 multiplications
  - Optimized variant saves ~36 % LUTs / ~65 % registers
- [x] Quantization - `mkQuantize`, `mkQuantize_RT`
  - Compile-time or runtime tables, AAN scaling factors integrated
- [x] Zigzag reorder - `mkZigZag`, `mkZigZag_Opt`
  - Standard + LUTRAM-optimised variant

#### Entropy encoding

- [x] RLE - `mkRLE` (DC differential, ZRL 16×0 tokens, EOB)
- [x] Huffman encoding - `mkHuffEncoder` (dual DC/AC tables, per-component selection, on-chip code generation)
- [x] Bitstream packing - `mkJPEGBitstream` (64-bit accumulator, 0xFF byte-stuffing, final padding)
- [x] JFIF frame assembly - `mkJPEGFramewriter` (SOI, APP0, DQT×2, SOF0, DHT×4, SOS, scan data, EOI)

#### Interfaces & configuration

- [x] AXI4-Stream I/O - 24-bit YCbCr in ({Y, Cb, Cr}), 8-bit JPEG out
- [x] AXI4-Lite config register map - `blue_jpeg_csrs`
- [x] Standard quantization & Huffman tables - `DefaultTables` (ITU-T T.81 Annex K)

#### Utilities

- [x] Transpose buffer - `mkTransposeBuffer`, `mkTransposeBufferOpt` (register or BRAM-based)
- [x] [Banked memory](hdl/encoder/docs/BankedMemory.md) - configurable address mapping, fair same-bank arbitration, single/dual-port BRAM backends
- [x] RGB to YCbCr conversion - `mkRGB2YCbCrConv` (standalone, not wired into main pipeline)

#### Not yet completed

- [ ] Improve Image Tiler latency
- [ ] Allow removal of scaled quantization table writes, auto scale quant values upon configuration
- [ ] Working verilog simulation for all testbenches (VPI imports still fail)
- [x] Hardware verification on FPGA (PA200T: 192x192 frame over UART, byte-identical to the C++ reference)
- [ ] Better configuration mechanism (presets / config package instead of raw `numeric type` parameters)
- [x] Grayscale-only mode (`en_chroma=False`)
- [ ] Parallel MCU encoding (pipeline is serial)
- [ ] Arithmetic coding (Huffman only for now)

---

### Software reference

The `sw/` directory contains a C++23 reference JPEG encoder.  It is also used
during simulation for per-stage verification via Bluespec DPI (BDPI), see
`hdl/encoder/src/BDPI/jpeg_references.cpp`.

**Status:** work-in-progress. `TestJPEGBitAccuracy` checks byte-for-byte agreement
with the optimized hardware at DCT/quantization scales of 12, using 4:4:4 colour.

```sh
cd sw && mkdir build && cd build
cmake .. && make
./encode <input.bmp> <output.jpg>
```

---

### Repository layout

```
hdl/
  Makefile              BSVTools project: simulation, ROM generation, PA200T bitstream
  src/encoder/          encoder core (mkBlueJPEG and its pipeline)
  src/system/           board-independent test system: pattern ROM -> encoder -> UART
  src/fpga/pa200t/      PA200T-Starlite top, PLL, JTAG, constraints and Vivado script
  src/synth/            out-of-context synthesis variants of the core (SynthTest)
  test/                 Bluesim testbenches, test/bdpi holds the C++ reference models
  test/host/            OpenOCD and UART capture scripts for the board test
  rom/                  pattern ROM image (make rom)
  libraries/            BSVTools libraries, links into dep/ plus the vendored axis library
sw/                     C++ reference encoder
dep/                    submodules (BSVTools, bluecsr, bluefabric with BlueAXI, bluej, blueuart, bluexlnx, BlueLib, BlueSY, CImg)
docs/                   design notes
assets/                 diagrams, test images
```

### Building

All commands run in `hdl/` inside the Nix shell (Vivado on the path for bitstreams).

```sh
make sim                                  # Bluesim, RUN_TEST picks test/<name>.bsv (default TestBlueJPEG)
make sim RUN_TEST=TestJpegSystem          # full test system, UART output checked against the C++ reference
make rom                                  # regenerate rom/pattern_192x192.mem from assets/sample_192x192.bmp
make bitstream                            # PA200T bitstream and flash image via BSVTools vivado_tcl
make bitstream SYNTH=ooc TOP_MODULE=mkBlueJPEGTop_1920_12   # out-of-context synthesis of a core variant
```

Each test builds in `build/<RUN_TEST>`, the bitstream in `build/BlueJPEG_PA200T/BlueJPEG_PA200T`
(`*_out_<WNS>.bit` and `.mcs`, plus timing and utilization reports). A test fails `make sim`
when its output contains `ERROR`.

### PA200T test design

`mkPA200T_JPEG_Top` encodes a 192x192 test pattern from a BRAM ROM and sends the JPEG over
the USB-UART. Registers are reached through the JTAG bus master on the header pins, the
same custom TAP as the pa200t design.

```
200 MHz -> PLL -+- 50 MHz:  JTAG bus master -> TEST regs, JPEG regs
                |           pattern ROM -> streamer -> BlueJPEG -> 8 KiB BRAM FIFO -+
                +- 125 MHz: UART TX <- dual-clock FIFO <---------------------------+
```

- Encoder: the `mkBlueJPEGTop_1920_12` configuration (1920 pixels wide, DCT and quantization
  scale 12, 4:4:4, double-buffered tiler) with the DCT on the 50 MHz clock. At scale 12 the
  output is bit-exact to the C++ reference.
- The streamer starts by itself when the encoder starts a frame (`busy` rises) and streams
  `NPIX` pixels, so all counters are aligned to the frame start.
- The output buffer holds a whole frame, so the encoder is never throttled by the UART.
- LED0 lights with the encoder interrupt (frame done), LED1 is the JTAG LED control register.

Bus map: `0x0000` TEST (`src/system/JpegTestRegs.bsv`), `0x2000` JPEG (encoder registers above).

| Offset | TEST register | Description |
| ------ | ------------- | ----------- |
| 0x00   | MIV    | Module ID 0x002 |
| 0x04   | CTRL   | `[0]` stream the pattern into every encoder frame (reset 1) |
| 0x08   | STS    | `[0]` streaming, `[1]` last pixel accepted, `[2]` last byte out |
| 0x0C   | NPIX   | Pixels per frame (reset 36864, the ROM address wraps) |
| 0x10   | UDIV   | UART clocks per bit (reset 1085 = 115200 baud at 125 MHz) |
| 0x20   | INCYC  | Input window, first to last accepted pixel |
| 0x24   | INSTL  | Input window cycles with a pixel offered but not accepted |
| 0x28   | OUTB   | JPEG bytes out of the encoder |
| 0x2C   | OUTCYC | Output window, first to last JPEG byte |
| 0x30   | OUTSTL | Output window cycles with the output buffer full |
| 0x34   | TOTAL  | Frame start to last JPEG byte |

Board test:

```sh
make sim RUN_TEST=TestJpegSystem          # expected JPEG: build/TestJpegSystem/uart_capture.jpg
make bitstream                            # then load the .bit with the Vivado Hardware Manager
python3 test/host/capture_uart.py /dev/ttyUSB0 --expect build/TestJpegSystem/uart_capture.jpg &
openocd -f test/host/bluejpeg_jlink.tcl   # checks module IDs, encodes one frame, prints the counters
```

`bluejpeg_report` prints all counters in 50 MHz cycles plus pixels per cycle, configure
cycles, frame time and throughput. In simulation the frame takes 146,868 cycles
(0.25 pixels per running cycle).
