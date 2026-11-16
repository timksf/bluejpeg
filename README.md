# BlueJPEG

A configurable baseline JPEG encoder written in Bluespec SystemVerilog. BlueJPEG is a generator: a
handful of compile-time parameters select image width, arithmetic precision, colour mode and buffering,
and the build emits a synthesizable Verilog core sized for exactly that configuration. The core takes
YCbCr pixels over AXI4-Stream, is configured over AXI4-Lite and produces a complete JFIF file as a byte
stream.

- Baseline sequential DCT, Huffman entropy coding, JFIF output (SOI, APP0, DQT, SOF0, DHT, SOS, EOI)
- YCbCr 4:4:4 colour or grayscale, 8-bit samples, width up to the configured maximum, height at runtime
- Quantization and Huffman tables programmable at runtime, Huffman codes generated on chip
- One component sample per main clock cycle: 1/3 pixel per cycle in colour, measured at 99.74 % of
  that limit for a 1920 × 1080 frame
- DCT in its own clock domain behind gearboxes, so the arithmetic can run at a fraction of the main clock
- Output byte-identical to the C++ reference encoder in `sw/` at 12-bit DCT and quantization scales
- Routed at 200 MHz out of context on an Artix-7 `xc7a200t-2`, in 6,021 LUTs, 4,488 FFs, 25 BRAM tiles
  and 11 DSPs, and demonstrated at 1080p30 on hardware

## Architecture

![BlueJPEG top-level pipeline](assets/toplevel.svg)

Pixels arrive in raster order and are reordered into 8 × 8 blocks by the image tiler (*Derasterizer*),
a BRAM line buffer of eight lines of the maximum width, optionally double-buffered so the next strip
fills while the current one drains. A channel splitter and dispatcher turn each 8 × 8 MCU into one Y,
one Cb and one Cr data unit. Each data unit then passes through mean shift, a separable AAN 2D DCT
(row DCT, transpose buffer, column DCT), quantization with the AAN scale factors folded into the
tables, and zigzag reordering. RLE and the Huffman encoder produce codewords, which the bitstream
writer packs into bytes with `0xFF` stuffing. The frame writer emits the JFIF headers from the current
tables and then passes the scan data through. All stages are connected by elastic interfaces and
handle back-pressure from the output stream.

The figure is rendered from [`assets/toplevel.excalidraw`](assets/toplevel.excalidraw), the source
that stays editable:

```sh
python3 assets/excalidraw_svg.py assets/toplevel.excalidraw     # writes assets/toplevel.svg
```

A more detailed block diagram with stage widths and control signals is in
[`assets/system.drawio.png`](assets/system.drawio.png), and the hardware architecture write-up in
[`assets/architecture/bluejpeg-architecture.pdf`](assets/architecture/bluejpeg-architecture.pdf).

## Configuration

Compile-time parameters are fields and numeric types of `BlueJPEGCfg_t` (`hdl/src/encoder/BlueJPEG.bsv`):

| Parameter | Effect | Typical values |
| --- | --- | --- |
| `max_img_width` | Maximum image width, sizes the tiler line buffers (the dominant BRAM cost) | 720, 1920, 2560 |
| `dct_scale` | Fixed-point width inside the DCT | 12, 14, 16 |
| `quant_scale` | Fixed-point width of the quantizer arithmetic and scaled tables | 12, 14, 16 |
| `pixel_width` | Input sample width | 8 |
| `en_chroma` | `True`: 4:4:4 colour, `False`: grayscale, the chroma path is not built | |
| `en_tiler` | `False` removes the tiler, input is then expected in 8 × 8 block order (e.g. from a 2D DMA) | |
| `double_buffer_tiler` | Double-buffers the line buffer, so a new strip is accepted while the last one drains | |
| `slow_clock`, `slow_reset` | Clock domain of the DCT, may equal the main clock | |

```bsv
BlueJPEGCfg_t#(1920, 12, 12, 8) cfg = BlueJPEGCfg_t {
    slow_clock:          clk_dct,
    slow_reset:          rst_dct,
    _prx_miw:            ?,
    _prx_dsc:            ?,
    _prx_qsc:            ?,
    _prx_pixw:           ?,
    en_tiler:            True,
    double_buffer_tiler: True,
    en_chroma:           True
};
BlueJPEG_ifc i_enc <- mkBlueJPEG(cfg);
```

Image width and height, quantization tables and Huffman tables are runtime settings in the register
map. Defaults after reset are the ITU-T T.81 Annex K tables. `hdl/src/synth/SynthTest.bsv` holds
ready-made synthesis tops, for example `mkBlueJPEGTop_1920_12` (colour, 1920 wide, double-buffered),
`mkBlueJPEGTop_2560_12_12`, `mkBlueJPEGGrayTop_1920_12_12` and `mkBlueJPEGGrayTop_720_12_12`.

## Interface and usage

| Port | Direction | Description |
| --- | --- | --- |
| `s_axis` | in | AXI4-Stream, 24-bit pixels `{Y, Cb, Cr}` in raster order |
| `m_axis` | out | AXI4-Stream, 8-bit JPEG bytes, `tlast` on the final `0xD9` of the file |
| `s_axi_cfg_rd`, `s_axi_cfg_wr` | in | AXI4-Lite register map, 32-bit |
| `irq` | out | Enabled pending interrupts (`IRQP & IRQE`) |
| `busy` | out | A frame is being encoded |

To encode a frame:

1. After reset, wait for `STS.RDY`: the default tables are loaded and their Huffman codes generated.
2. Write the image size to `IMSZ`. Optionally write tables, and after changing a Huffman table trigger
   code generation for it through `CGEN`.
3. Enable the interrupts of interest in `IRQE` and set `CTRL.START`. An invalid size rejects the start
   and raises `IRQP.INV`.
4. Stream width × height pixels into `s_axis` and collect the JFIF file from `m_axis`.
5. `IRQP.DONE` (write 1 to clear) signals the end of the frame. `PERF0` to `PERF6` hold cycle, pixel,
   byte, idle, flush, frame and boot counts of the last frame.

## Register map

Generated from the BlueCSR definition `blue_jpeg_csrs` (`hdl/src/encoder/BlueJPEGRegs.bsv`) with
`python3 hdl/docgen/regmap.py` in the Nix shell. Offsets are bytes from the base of the encoder's
AXI4-Lite window. Table regions take one entry per 32-bit word.

<!-- regmap:begin -->
BlueJPEG Register File for BlueJPEG encoder.

| Address | Register | Register Description | Field | Bits | Access | Reset | Field Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0x0000 | MIV | Module ID & Version Register. | MID | [11:00] | RC | 0x1 | Unique ID for this module. |
|  |  |  | VRS | [18:16] | RC | 0x0 | Module verion. |
| 0x0004 | CTRL | Control Register. | START | [00:00] | RW | 0x0 | Writing 1 requests processing. Hardware clears the request when it is accepted or rejected. |
| 0x0008 | STS | Status Register. | RDY | [00:00] | RO | 0x0 | Set once the default tables are loaded and their Huffman codes generated after reset. Low while a codegen runs. |
|  |  |  | CGB | [01:01] | RO | 0x0 | Indicates whether huffman table codegen is running. |
|  |  |  | DONE | [04:04] | RO | 0x0 | Set on frame completion and cleared when a new frame is accepted. |
| 0x000c | IMSZ | Image Size. | IMW | [15:00] | RW | 0x0 |  |
|  |  |  | IMH | [31:16] | RW | 0x0 |  |
| 0x0014 | CGEN | Huffman Codegen Config. | TBL | [01:00] | RW | 0x0 | Controls which table type to generate. 00=DC LUMA, 01=DC CHROMA, 10=AC LUMA, 11=AC CHROMA. |
|  |  |  | TRG | [31:31] | RW | 0x0 | Writing 1 triggers Huffman code generation from the stored tables. Hardware clears it when the codegen starts. |
| 0x0018 | IRQP | Interrupt Pending (W1C). | DONE | [00:00] | W1C | 0x0 | A frame was encoded completely. |
|  |  |  | INV | [01:01] | W1C | 0x0 | A start request was rejected because of an invalid image size. |
| 0x001c | IRQE | Interrupt Enable. | DONE | [00:00] | RW | 0x0 | Enables Frame Done. |
|  |  |  | INV | [01:01] | RW | 0x0 | Enables Invalid Config. |
| 0x0030 | PERF0 | Performance Counter Cycles. | CYC | [31:00] | RO | 0x0 | Number of cycles in running state since last processing start. |
| 0x0034 | PERF1 | Performance Counter Pixels. | PIX | [31:00] | RO | 0x0 | Number of pixels processed since last processing start. |
| 0x0038 | PERF2 | Performance Counter Bytes. | BYTEO | [31:00] | RO | 0x0 | Number of encoded bytes produced since last processing start. |
| 0x003c | PERF3 | Performance Counter Idle Cycles. | IDLE | [31:00] | RO | 0x0 | Cycles in running state in which no input pixel was accepted. |
| 0x0040 | PERF4 | Performance Counter Flush Cycles. | FLSH | [31:00] | RO | 0x0 | Cycles from the last data unit entering the pipeline until the frame is done. |
| 0x0044 | PERF5 | Performance Counter Frame Cycles. | FRAME | [31:00] | RO | 0x0 | Cycles from the accepted start request until the frame is done, including configuration. |
| 0x0048 | PERF6 | Performance Counter Boot Cycles. | BOOT | [31:00] | RO | 0x0 | Cycles from reset until the default tables and Huffman codes were first ready. |
| 0x0100:0x01ff | QLUMAR | Raw luma quantization table, used for bitstream generation. |  |  |  |  |  |
| 0x0200:0x02ff | QCHROMAR | Raw chroma quantization table, used for bitstream generation. |  |  |  |  |  |
| 0x0300:0x03ff | QLUMASC | Scaled luma quantization table, used during encoding. |  |  |  |  |  |
| 0x0400:0x04ff | QCHROMASC | Scaled chroma quantization table, used during encoding. |  |  |  |  |  |
| 0x0500:0x053f | HBITSDCL | HUFFBITS table for DC luma components. |  |  |  |  |  |
| 0x0540:0x057f | HBITSDCC | HUFFBITS table for DC chroma components. |  |  |  |  |  |
| 0x0580:0x05bf | HBITSACL | HUFFBITS table for AC luma components. |  |  |  |  |  |
| 0x05c0:0x05ff | HBITSACC | HUFFBITS table for AC chroma components. |  |  |  |  |  |
| 0x1000:0x13ff | HVALDCL | HUFFVAL table for DC luma components. |  |  |  |  |  |
| 0x1400:0x17ff | HVALDCC | HUFFVAL table for DC chroma components. |  |  |  |  |  |
| 0x1800:0x1bff | HVALACL | HUFFVAL table for AC luma components. |  |  |  |  |  |
| 0x1c00:0x1fff | HVALACC | HUFFVAL table for AC chroma components. |  |  |  |  |  |
<!-- regmap:end -->

## Out-of-context synthesis

The OOC flow synthesizes, places and routes one of the `SynthTest` tops on its own, with the main
clock at 5 ns (200 MHz) and the DCT clock at 40 ns (25 MHz, ratio 8:1) from
`hdl/src/synth/constr/ooc.xdc`:

```sh
make -C hdl bitstream SYNTH=ooc TOP_MODULE=mkBlueJPEGTop_1920_12
```

Results for `mkBlueJPEGTop_1920_12` on `xc7a200tfbg484-2` with Vivado 2025.2, after routing:

| Metric | Value |
| --- | ---: |
| Setup WNS / TNS | +0.014 ns / 0 ns |
| Hold WHS | +0.060 ns |
| Slice LUTs | 6,021 |
| Slice registers | 4,488 |
| BRAM tiles | 25 (the tiler line buffers and table storage) |
| DSP48E1 | 11 |

No false paths, multicycle paths or clock-group exclusions are used, and the clock crossings to and
from the DCT clock stay timed. The worst remaining path is CSR request decoding. The figures predate a
later increase of three per-DU metadata FIFOs from four to eight entries, which has not been
re-synthesized. Details and per-module slack are in [`docs/timing-200mhz.md`](docs/timing-200mhz.md).

Throughput in simulation, 1920 × 1080 colour frame, unrestricted output sink, in main clock cycles:

| Clocking | Frame cycles (`PERF5`) | Pixels per cycle | Of the 1/3 limit |
| --- | ---: | ---: | ---: |
| DCT on the main clock | 6,236,632 | 0.33249 | 99.75 % |
| DCT at main / 8 | 6,236,760 | 0.33248 | 99.74 % |
| Ideal | 6,220,800 | 0.33333 | 100 % |

The remaining loss is the first tiler strip, one-cycle bubbles at data-unit boundaries and the final
flush. The analysis is in [`docs/throughput-cycles.md`](docs/throughput-cycles.md). Throughput depends
on image content, since long zero runs and large codewords cost entropy coder cycles.

## Example system: 1080p30 over UDP

`hdl/src/system_udp` and `hdl/src/fpga/pa200t_udp` build a demonstration system for the PA200T board
(Artix-7 `xc7a200t`, DDR3, Gigabit Ethernet). Frames are loaded into DDR3 over UDP, read back by a
frame store, encoded, and the JPEG is sent back as UDP datagrams of up to 1024 payload bytes with an
eight-byte header carrying frame number, sequence number and a last-packet flag. A JTAG-to-AXI bridge
gives the host access to the system, Ethernet and encoder registers.

| Domain | Frequency | Contents |
| --- | ---: | --- |
| Encoder | 200 MHz | Tiler, JPEG pipeline, encoder registers |
| DCT | 25 MHz | DCT, behind timed gearboxes |
| System | 125 MHz | UDP/RGMII, frame control, packetizer, DDR requests |
| Memory | 81.25 MHz | MIG AXI interface |

On hardware the system encodes a 1920 × 1080 4:4:4 frame every 3,912,750 system cycles, **31.95 fps**,
producing 290,450 bytes in 284 packets per frame with no output stalls. Captured frames are compared
byte for byte with the C++ reference, including an animated 30-frame sequence replayed from DDR3 for
more than 2,900 frames. The input is preloaded: raw 1080p30 YCbCr needs about 1.5 Gb/s, more than the
link carries. The routed design meets timing with 0.000 ns setup WNS.

```sh
make -C hdl sim RUN_TEST=TbJpegUdpDemo UDP_TEST_1080P=1    # split-clock simulation, three reference frames
make -C hdl bitstream SYSTEM=udp UDP_DEMO_200=1            # board image
```

Board procedure, host tools and the full measurement record are in
[`docs/1080p30-demo.md`](docs/1080p30-demo.md) and [`docs/udp-system.md`](docs/udp-system.md).

## Building and testing

All commands run in `hdl/` inside the Nix shell (`nix develop ./nix` from the repository root). The
FPGA flows additionally need Vivado on the path.

```sh
make sim                                   # Bluesim, RUN_TEST picks test/<name>.bsv (default TestBlueJPEG)
make sim RUN_TEST=TestJPEGBitAccuracy      # JPEG bytes against the C++ reference
make sim RUN_TEST=TbEncoderThroughput UDP_TEST_1080P=1   # 1080p throughput budget and byte check
make sim RUN_TEST=TestJpegSystem           # small test system: pattern ROM -> encoder -> UART
make bitstream                             # PA200T UART test design (192 × 192 pattern over USB-UART)
```

Each test builds in `build/<RUN_TEST>` and fails when its output contains `ERROR`. Simulation tests
compare against the C++ reference encoder through BDPI. The reference also builds on its own:

```sh
cd sw && mkdir build && cd build && cmake .. && make
./encode <input.bmp> <output.jpg>
```

## Repository layout

```text
hdl/src/encoder/     encoder core, mkBlueJPEG and its pipeline stages
hdl/src/synth/       out-of-context synthesis tops and Vivado scripts
hdl/src/system/      UART test system: pattern ROM -> encoder -> UART
hdl/src/system_udp/  DDR3/UDP system: loader, frame store, packetizer, clock crossings
hdl/src/fpga/        PA200T board tops for both systems: PLLs, JTAG, pins, constraints
hdl/test/            Bluesim testbenches, test/bdpi holds the C++ reference models
hdl/docgen/          register map documentation generator
sw/                  C++ reference encoder
docs/                design notes and measurements
assets/              diagrams and test images
dep/                 submodules: BSVTools, bluecsr, bluefabric, bluej, blueuart, bluexlnx, ...
```

## Limitations

- Baseline only: Huffman coding, no progressive or arithmetic coding, no restart markers
- No chroma subsampling: 4:4:4 colour or grayscale
- One data unit lane, no parallel MCU encoding
- The scaled quantization tables have to be written alongside the raw tables
- Verilog simulation of the testbenches is not working yet, Bluesim is
