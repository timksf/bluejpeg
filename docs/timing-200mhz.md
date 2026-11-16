# Timing closure at 200 MHz

The colour encoder `mkBlueJPEGTop_1920_12` (maximum width 1920, colour, double-buffered tiler,
12-bit DCT and quantization precision) meets timing out of context at 200 MHz on the Artix-7
`xc7a200tfbg484-2`. The main clock is constrained to 5 ns and the separate DCT clock to 40 ns, the
8 to 1 ratio used throughout, so the DCT runs at 25 MHz. No false paths, multicycle paths, clock
group exclusions, placement constraints or arithmetic approximations are used, the clock crossings
between main and DCT clock stay timed, and all internal endpoints have clocks and delay constraints.
External I/O delays and board clock roots are outside the scope of an out-of-context run and are
checked when the core is integrated, as in the [1080p30 demonstration](1080p30-demo.md).

## Result

Vivado 2025.2 reports +0.014 ns setup slack, 0 ns total negative slack and +0.060 ns hold slack after
routing. The worst path is the decoding of a CSR request into its response register. The table lists
the worst routed setup slack per module before and after the changes described below, counting only
paths whose start and end points both lie in the module.

| Module | Before (ns) | After (ns) |
| --- | ---: | ---: |
| Complete core | -2.633 | +0.014 |
| Image tiler | -2.633 | +0.319 |
| Bitstream writer | -2.448 | +0.230 |
| DU processing including quantization, gearboxes and clock crossings | -1.863 | +0.302 |
| Huffman encoder | -1.705 | +0.312 |
| Table storage and code generation | -1.702 | +0.125 |
| RLE | -1.074 | +0.481 |

In the final report the frame writer has +0.050 ns slack, the crossing from the main to the DCT clock
+0.660 ns and the reverse direction +0.302 ns.

| Routed resources | Before | After |
| --- | ---: | ---: |
| Slice LUTs | 6,941 | 6,021 |
| Slice registers | 4,374 | 4,488 |
| BRAM tiles | 25 | 25 |
| DSPs | 11 | 11 |

## Design changes

- The tiler used the general banked-memory router for a single dual-port BRAM. Its bank depth is not
  a power of two, which put division and remainder logic into the address generation, and both
  logical clients were multiplexed across both physical ports with a response multiplexer behind
  them. A direct dual-port backend now binds each client to its own port, while the general router
  remains available for other uses. Read addresses are registered before the BRAM request, and the
  last write address and the row increment are computed when the width is configured.
- The bitstream writer cleared emitted bits through a 64-bit CReg and then shifted and appended the
  next codeword in the same cycle. Clearing is unnecessary, since only the low `rg_bits` bits are
  valid and appending never moves stale upper bits into that range, so the accumulator is now an
  ordinary register and only the bit count remains a CReg. Masks are built with shifts and
  complements at codeword or byte width, final padding works on a single byte, and a registered
  byte boundary separates extraction from stuffing. Completion waits until those bytes and their
  stuffing have been handled.
- Quantization performed operand negation, multiplication and product negation in one cycle through
  `signedMul`. The runtime quantizer now has rigid stages for the table request, operand magnitudes,
  unsigned multiplication, sign restoration and rounding, all advancing on one enable condition and
  checked with `fire_when_enabled` and `no_implicit_conditions`. Signed extreme values keep their
  previous arithmetic behaviour.
- The Huffman encoder combined absolute value and magnitude encoding in its preparation step and
  table lookup with codeword packing in its emission step. Its rigid pipeline now separates
  preparation, symbol generation, table lookup and packing under one enable condition. RLE registers
  the zero classification before its variable-rate symbol logic.
- Code generation registers each code-length count before comparing it with the symbol counter, and
  per-table HUFFVAL reads are registered before the destination table is selected.
- CSR requests are registered before decoding. The rewind distribution at frame start is a separate
  control step ahead of the guarded tiler and frame writer start handshakes, which adds one cycle per
  frame, and the frame writer compares against a precomputed last HUFFVAL index instead of
  subtracting from the total for every symbol.

Apart from the start handshake of the frame writer, which reached into the rewind and reset logic of
other modules, and the combinational table interfaces, the critical paths were contained within
single modules.

## Reproducing

```sh
make -C hdl bitstream SYNTH=ooc TOP_MODULE=mkBlueJPEGTop_1920_12
```

`hdl/src/synth/script/synth_ooc.tcl` synthesizes, optimizes, places, physically optimizes and routes
the core, and `timing_reports.tcl` writes full-core, per-clock and per-module path reports after each
stage. The relevant outputs in the build directory are the route summary, path and utilization
reports, the per-module reports such as those for `i_img_tiler` and `i_stuffer`, and the routed
checkpoint.

The changes are covered by the existing regressions. All 36 bitstream writer cases with buffered and
bypassed input, with and without output stalls, pass. The tiler test covers widths of 8, 128 and 1920
in both buffer modes, and `TbQuantizePipeline` checks signed extreme values, negative table
multipliers, input bubbles, output stalls and repeated rewind. The byte-accuracy test matches all
3,560 reference bytes, the consecutive-frame test passes with colour and double buffering enabled,
and the 1920 × 1080 system test passes three consecutive frames including repeat operation.
