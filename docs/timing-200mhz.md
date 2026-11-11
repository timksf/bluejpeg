The Full HD color encoder meets its internal OOC timing constraints on the PA200T's `xc7a200tfbg484-2` after the changes described here. Vivado 2025.2 reports **+0.014 ns setup WNS**, **0 ns TNS**, no failing setup endpoints, and **+0.060 ns hold WHS** after routing. The remaining margin is only 14 ps. The worst path is now CSR request decoding to its response register. Board integration still needs its own timing validation.

The synthesized top is `mkBlueJPEGTop_1920_12`, with a maximum image width of 1920, color enabled, a double-buffered tiler, and 12-bit DCT and quantization scales. Height is a runtime setting and the functional system test uses 1920 × 1080. The main clock is constrained to 5 ns and the separate DCT clock to 40 ns, matching the existing 8:1 configuration. The DCT itself is therefore running at 25 MHz in this experiment.

The baseline and final builds use the same part and clock constraints. No false paths, multicycle paths, clock-group exclusions, placement constraints, arithmetic approximations, or image-size special cases were added. The existing elastic interfaces between JPEG modules remain in place.

| Routed setup slack | Baseline (ns) | Final (ns) |
| --- | ---: | ---: |
| Complete core | -2.633 | +0.014 |
| Image tiler | -2.633 | +0.319 |
| JPEGBitstream | -2.448 | +0.230 |
| DU processing, including quantization | -1.863 | +0.302 |
| Huffman encoder | -1.705 | +0.312 |
| Table storage and code generation | -1.702 | +0.125 |
| RLE | -1.074 | +0.481 |

The module rows are the worst paths whose sequential endpoints are both in the named module. The DU processing row includes its gearboxes and clock crossings. In the final full-core report, the framewriter has +0.050 ns slack and CSR decoding has +0.014 ns. Clock crossings are still timed, with +0.660 ns setup slack from the main clock to the DCT clock and +0.302 ns in the reverse direction. All internal endpoints have clocks and maximum-delay constraints. External I/O delays, OOC partition pin locations, and the final board clock roots are not specified by this core-level experiment and must be checked during system integration.

The baseline identified several distinct problems:

- The tiler used the general bank router for a single dual-port BRAM. Its non-power-of-two bank depth introduced division and remainder logic into address generation. It also multiplexed both logical clients across both physical ports and routed responses through an owner mux. The direct dual-port backend now binds each client to its own port. The general shared-bank accessor is unchanged. Read addresses are registered before BRAM requests, and the last write address and row increment are calculated when the width is configured.
- JPEGBitstream cleared emitted bits through a 64-bit CReg, then shifted and appended the next codeword in the same cycle. Clearing is unnecessary because only the low `rg_bits` bits are valid and appending cannot move stale high bits into the valid region. The accumulator is now an ordinary register. Only the small count retains its CReg. Mask generation uses shifts and complements at the codeword or byte width, and final padding operates on one byte. A registered byte boundary separates extraction from stuffing. Completion waits until those bytes and their stuffing have been handled.
- Quantization placed operand negation, multiplication, and product negation in one cycle through `signedMul`. The runtime quantizer now has rigid stages for table requests, operand magnitudes, unsigned multiplication, sign restoration, and rounding. All internal stages share one advance condition, and their `fire_when_enabled` and `no_implicit_conditions` assertions pass compilation. Signed extrema retain the original arithmetic behavior.
- Huffman preparation combined absolute-value calculation and magnitude encoding, and emission combined LUTRAM lookup with codeword packing. Its rigid pipeline now separates preparation, symbol generation, table lookup, and packing under one advance condition with the same scheduling assertions. RLE registers zero classification before its variable-rate symbol logic.
- Code generation now registers each code-length count before comparing it with the symbol counter. Per-table HUFFVAL reads are registered before selecting the destination table, splitting lookup from selection and writes.
- CSR requests are registered before decoding. Startup rewind distribution is a separate control step from the guarded tiler and framewriter start handshakes, adding one startup cycle per frame. A framewriter comparison uses a precomputed last HUFFVAL index instead of subtracting from the total while emitting each symbol.

There was a cross-module control path: the framewriter's guarded start influenced the rewind pulse and reset logic in other modules. It was a startup path, not a long streaming data path. The combinational table interfaces also cross module boundaries by design. The critical streaming operations were otherwise concentrated within modules, as expected.

| Routed resources | Baseline | Final |
| --- | ---: | ---: |
| Slice LUTs | 6,941 | 6,021 |
| Slice registers | 4,374 | 4,488 |
| BRAM tiles | 25 | 25 |
| DSPs | 11 | 11 |

The complete OOC flow can be reproduced from the repository root with:

```sh
make -C hdl bitstream SYNTH=ooc TOP_MODULE=mkBlueJPEGTop_1920_12 BUILDDIR=build/timing_200_reproduce
```

`synth_ooc.tcl` now synthesizes, optimizes, places, physically optimizes, and routes the core. `timing_reports.tcl` writes full-core, per-clock, and per-module paths at each major stage. Original `_tim1` and `_tim2` reports are retained. The local baseline artifacts are in `hdl/build/timing_200_baseline/mkBlueJPEGTop_1920_12_ooc/`, and the final artifacts are in `hdl/build/timing_200_final/mkBlueJPEGTop_1920_12_ooc/`. The most useful final files are:

- `mkBlueJPEGTop_1920_12_ooc_route_summary.rpt`
- `mkBlueJPEGTop_1920_12_ooc_route_paths.rpt`
- `mkBlueJPEGTop_1920_12_ooc_route_i_img_tiler.rpt`
- `mkBlueJPEGTop_1920_12_ooc_route_i_stuffer.rpt`
- `mkBlueJPEGTop_1920_12_ooc_route_util.rpt`
- `mkBlueJPEGTop_1920_12_ooc_route.dcp`

Functional validation includes all 36 existing JPEGBitstream cases across buffered and bypass inputs, with and without output stalls. The tiler test now covers widths 8, 128, and 1920 and both buffer modes. `TbQuantizePipeline` checks signed extrema, negative table multipliers, input bubbles, output stalls, and repeated rewind. The JPEG byte-accuracy test matches all 3,560 reference bytes, and the consecutive-frame test passes with color and double buffering enabled.

The final Full HD system test passes three consecutive 1920 × 1080 frames, including repeat operation. Each frame contains 290,450 bytes in 284 UDP packets and matches the C++ reference byte for byte. Validation logs are saved under `hdl/build/timing_200_final/validation/`.
