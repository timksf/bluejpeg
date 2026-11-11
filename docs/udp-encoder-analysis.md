# UDP encoder resources, timing and throughput

Measured on the PA200T with the completed DDR3 UDP system on 2026-11-10.
The encoder configuration is 1920-pixel maximum width, 8-bit YCbCr 4:4:4,
12-bit DCT and quantization scales, double-buffered tiling, and one shared
81.25 MHz clock for the encoder and DCT. Tables and the input image are the
ones used in the byte-accuracy system test.

## Isolated encoder resources

`mkJpegEncoderResource` instantiates exactly the UDP system's `mkBlueJPEG`
configuration and exports its AXI streams, AXI-Lite configuration, frame start,
IRQ and busy interface. This includes the tiler and programmable JPEG tables.
It excludes DDR3/MIG, the external frame store, UDP/Ethernet, JTAG and board clocks.
Vivado 2025.2 synthesized and optimized it out of context for `xc7a200tfbg484-2`
with a 12.307692 ns clock constraint. These are optimized synthesis counts,
not a separately placed and routed encoder.

| Resource | Standalone encoder | Device use | Encoder cells in routed system | Complete routed system |
| --- | ---: | ---: | ---: | ---: |
| Slice LUTs | 7,044 | 5.23% | 6,559 | 19,917 |
| LUTs as logic | 6,006 | 4.46% | 5,581 | — |
| LUTs as memory | 1,038 | 2.25% of memory-capable LUTs | 978 | — |
| Flip-flops | 4,361 | 1.62% | 4,313 | 18,759 |
| BRAM tiles | 25 | 6.85% | 25 | 33 |
| DSP48E1 | 11 | 1.49% | 11 | 11 |

The isolated LUT memory count is 930 distributed RAM LUTs plus 108 shift-register
LUTs. The 25 BRAM tiles are 24 RAMB36E1 and two RAMB18E1. In the routed design,
all 24 RAMB36E1 belong to the tiler, and the two RAMB18E1 belong to table
initialization storage. Device percentages use the full device capacity.
Synthesis and physical optimization explain why the standalone count differs
from cells attributed to the encoder in the integrated design.

BlueLens was used to map the routed primitive list back to BSV hierarchy.
Its mapping locates the DCT under `i_du_proc/i_dct` and the line buffers under
`i_img_tiler/i_pixels`. Treat its module totals as a hierarchy reference.
Synthesized arithmetic names are sometimes truncated, and the mapping misses
the encoder's 11 DSPs. The resource table above therefore uses native Vivado
utilization, with leaf primitive selection for the integrated encoder count.
The integrated selection uses names containing `i_sys_i_enc`, so it is an
attribution within the optimized system rather than an independent area build.

Artifacts, relative to the repository root:

- Standalone utilization: `hdl/build/mkJpegEncoderResource_ooc/mkJpegEncoderResource_ooc/mkJpegEncoderResource_ooc_util.rpt`
- Standalone checkpoint: same directory, `mkJpegEncoderResource_ooc_synth.dcp`
- Routed attribution: `hdl/build/udp_encoder_analysis/encoder_utilization.rpt`
- BlueLens hierarchy: `hdl/build/udp_encoder_analysis/bluelens_utilization.md`
- Primitive export: `hdl/build/udp_encoder_analysis/primitives.tsv`

## Critical paths

These paths come from the final system's post-route physical optimization
checkpoint. The design meets setup and hold at 81.25 MHz, with system worst
setup slack +0.343 ns and hold slack +0.008 ns.

The worst path with both sequential endpoints inside the encoder is:

```text
i_img_tiler/rg_buf_threshold_reg[3]
    -> buffer threshold / write-address logic
    -> i_img_tiler/i_pixels/i_bank/i_bram_memory/RAM_reg_0_8/ADDRBWRADDR[13]
```

Its data path is **10.093 ns**, split into 3.794 ns logic and 6.299 ns routing.
There are **14 logic levels**, including eight CARRY4s. Setup slack is
**+1.542 ns**. The source-level logic is in `ImageTilingEngine.bsv`, around
`advance_write` and `buffer_address`. The critical path is address/control logic
for the line buffer, rather than DCT multiplication.

The complete system's worst path starts outside the encoder:

```text
MIG u_ddr3_infrastructure/rstdiv0_sync_r1_reg_rep
    -> encoder i_du_proc/i_gear_o/block1_reg[64]/R
```

This is synchronous reset distribution. Its data path is **11.453 ns**, with
11.074 ns routing, 0.379 ns cell delay and no intervening combinational levels.
It has **+0.343 ns** setup slack. The reset net has 3,496 loads. Reset fanout and placement dominate this path.
Both this path and the tiler path would need attention when increasing clock
frequency. Neither slack value proves operation at a higher clock without a
fresh implementation. The present application clock also comes from MIG, so
changing encoder frequency requires a clocking and CDC design decision.

Detailed paths are in `hdl/build/udp_encoder_analysis/encoder_timing.rpt` and
`system_timing.rpt`.

## Continuous 1080p throughput

The board produced one single frame and exactly **100 consecutive repeat
frames**, all byte-identical to the C++ reference. Each JPEG is 290,450 bytes
and 284 UDP packets. No egress packets were lost. This repeats a preloaded DDR
frame and excludes host upload time. The last repeat frame had:

| Measurement | Result |
| --- | ---: |
| Start-to-start period | 8,341,457 cycles |
| Frame period at 81.25 MHz | 102.664086 ms |
| Continuous throughput | **9.740505 fps** |
| Cycles per image pixel | **4.022693** |
| Input window, INCYC | 8,230,178 cycles |
| Input backpressure, INSTL | 6,156,578 cycles |
| Input transfers | 2,073,600 pixels |
| JPEG output valid but not ready, OUTSTL | 273,213 cycles |
| JPEG generation, TOTAL | 8,340,786 cycles |
| JPEG payload rate | 22.633 Mb/s |
| DDR pixel-read payload rate, four bytes per pixel | 80.792 MB/s |

`INCYC - INSTL - 2,073,600 = 0`. The frame source was valid throughout the
measured input window. DDR3 supplied every cycle in which the encoder could
accept a pixel. Larger DDR bursts or deeper input buffering cannot improve
this measured steady-state rate by eliminating input starvation, because
there was none.

The encoder serializes Y, Cb and Cr through one DU processing lane. Even with
one component sample per cycle and no bubbles, 4:4:4 requires at least three
cycles per image pixel. At 81.25 MHz that gives an **ideal architectural
ceiling of 13.061 fps** for 1920×1080. The measured rate is about 74.6% of that
ceiling.

The main avoidable bubble is in the tiler's `mkBankedMemoryAccessor`, not the
DCT arithmetic. For nonzero read latency, `r_route_requests` grants a read only
when `rg_read_busy[client]` is false. It sets busy on issue and clears it when
`pw_response_taken` fires. The grant condition uses the old busy value, so it
cannot grant another read in the response-consumption cycle. With this
one-cycle BRAM configuration, reads issue at best every **two cycles**. Two
physical BRAM ports do not remove this per-client outstanding-read restriction.

`mkDUDispatcher` consumes 64 Y samples, then 64 Cb, then 64 Cr. The splitter
must fetch each YCbCr pixel from the tiler during the Y phase. Its small queues
cannot prefetch a whole next block during the chroma phases. A simple schedule
therefore takes roughly 128 cycles for Y and 64 each for Cb and Cr, or about
**four cycles per image pixel**. That predicts roughly **9.80 fps** at 81.25 MHz,
consistent with the measured 9.74 fps after other overhead and backpressure.
This is an approximate schedule model, not a strict bound for every image.

A simulation observer confirmed the tiler response spacing on the 192×192
test. In each frame, 36,288 of the 36,863 intervals were exactly two cycles.
There were no one-cycle intervals. The remaining intervals include the chroma
phases and strip boundaries. All three observed JPEGs still matched the C++
reference byte for byte. A separate observed 1080p simulation also passed all
three byte comparisons and retained its original PERIOD of 8,705,650 cycles.
These observers only modify generated Bluesim C++ in build directories.
They snapshot FIFO state before rule execution and record actual rule calls,
including rules whose firing conditions are evaluated later in the schedule.

The first throughput improvement to investigate is allowing pipelined tiler
reads, with enough response tracking and storage to preserve ordering under
backpressure. That needs shared-encoder changes and regression testing.
After approaching three cycles per pixel, the shared component lane itself
becomes the next architectural limit. No throughput optimization was applied
as part of this analysis.

Output stalls are directly observed on 3.28% of TOTAL cycles, but those
overlapping stall counts are not an additive latency breakdown or a prediction
of the gain from buffering.

The measured limit is the encoder pipeline's service rate at the MIG clock.
Ethernet wire bandwidth and DDR input bandwidth have headroom for this image.
Output stalls can still come from the packetizer and stack handshakes, even
with low average wire utilization. Sustained operation for different images
and tables can change the entropy-coding and output load, so 9.7405 fps is a
measurement for this verified frame, not a universal worst-case guarantee.

The older `BackpressureAnalysis.md` describes a ZigZag read/write scheduling
conflict that has already been fixed. It must not be used to claim that the
current ZigZag is limited to half a coefficient per cycle.

## Reproduce resource and timing reports

Run from the repository root inside the flake. Vivado must be on PATH.

```sh
nix develop ./nix
make -C hdl bitstream SYNTH=ooc MAIN_MODULE=synth/JpegEncoderResource TOP_MODULE=mkJpegEncoderResource SCRIPT="$PWD/hdl/src/synth/script/encoder_resource.tcl"
vivado -mode batch -nojournal -nolog -source hdl/src/synth/script/udp_encoder_analysis.tcl
```

The timing script requires the completed MIG system checkpoint. To regenerate
BlueLens metadata and the hierarchy report after a clean bitstream build:

```sh
make -C hdl SIM_TYPE=VERILOG compile_top SYSTEM=udp UDP_MEMORY=mig
bluetcl dep/bluelens/report_bsv_utilization.tcl --top mkPA200T_UDP_JPEG_Top --build hdl/build/BlueJPEG_PA200T_UDP_mig --vivado-cells hdl/build/udp_encoder_analysis/primitives.tsv --include '*i_enc*' --max-depth 12 --min-total 100 --out hdl/build/udp_encoder_analysis/bluelens_utilization.md
```

The hardware evidence is saved under `hdl/build/board_udp_1080/`, including
`repeat/counters.json` and the 100 JPEG captures. Fractional fps reporting in
`bluejpeg_udp.tcl` uses floating-point division and was checked against these
board counters, reporting 9.741 fps.

Simulation observer sources, logs and generated models are under
`hdl/build/udp_encoder_analysis/` and `hdl/build/encoder_profile_tiler/` or
`hdl/build/encoder_profile_correct/`. These are local analysis artifacts.
