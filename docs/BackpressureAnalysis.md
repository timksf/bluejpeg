# BlueJPEG backpressure measurement

Measured 2026-09-20 using the current working-tree TestBlueJPEG and sample_192x192.bmp, 4:4:4, chroma enabled, same clock for both DU clock domains, default tables. Two isolated builds changed only double_buffer_tiler. No production source changes. Both simulations passed, produced byte-identical 3,527-byte JPEGs, and decoded to 192x192.

## Timing and input backpressure

| Metric (cycles unless noted) | Single tiler buffer | Double tiler buffer |
|---|---:|---:|
| PERF0 / S_RUNNING | 246,287 | 222,435 |
| S_RUNNING through frame completion (includes flush) | 246,747 | 222,895 |
| First to last input AXI handshake, inclusive | 237,356 | 205,326 |
| Input valid but not ready in that interval | 200,492 | 168,462 |
| Longest continuous input stall | 8,718 | 7,681 |
| Longest consecutive input transfer burst | 1,539 | 3,075 |
| Source-not-valid cycles between first/last input | 0 | 0 |
| Pixels per cycle over full frame processing | 0.1494 | 0.1654 |

Double buffering saves 23,852 processing cycles (9.7% of PERF0), and accepts the last input 32,030 cycles earlier. It does not make input continuous. Internal tiler/AXI queue capacity explains why bursts are slightly longer than one/two 1,536-pixel strips.

PERF0 counts only S_RUNNING: it excludes initialization, code generation, and the final 460 cycles of flush/completion in these runs. It is not the complete JPEG latency. Timing above uses the DUT's output/finish rather than later software polling or test teardown.

## Where data waits (double-buffered run)

A blocked cycle means the source output FIFO is nonempty but is not dequeued in that cycle. Counts overlap across stages, so do not add them to estimate total latency.

| Boundary | Items transferred | Blocked cycles |
|---|---:|---:|
| Tiler output -> channel splitter | 36,864 pixels | 149,255 |
| Dispatcher FIFO -> DUProc | 110,592 samples | 79,753 |
| Quantizer -> ZigZag | 110,592 coefficients | 110,528 |
| ZigZag / DUProc -> RLE | 110,592 coefficients | 0 |
| RLE -> Huffman | 5,479 symbols | 0 |
| Huffman -> bitstream | 5,479 codewords | 0 |
| Bitstream -> framewriter | 2,902 scan bytes | 0 |

Single buffering also gives zero blocked cycles on the four boundaries starting with DUProc -> RLE. The final JPEG includes 625 bytes in addition to scan output. RLE's extra ZRL processing rule fires 12 times, but causes no observed waiting at the DU output under this producer schedule.

## Main finding: ZigZag scheduling serializes its two buffers

In src/ZigZag.bsv, mkZigZag_Opt (lines 109 onward), the compiled schedule gives r_read_out priority and lists it as a blocking rule for r_write_in. In the double-buffered trace:

- r_write_in CAN_FIRE: 221,120 cycles.
- r_write_in WILL_FIRE: 110,592 cycles.
- Writes suppressed by scheduling: 110,528 cycles.
- r_read_out WILL_FIRE: 110,592 cycles.
- Simultaneous read/write cycles: zero.

Thus the nominal ping-pong buffers do not overlap loading and draining. The observed DU output is 64-cycle bursts separated by filling the next block, averaging 0.5001 coefficients/cycle from first to last coefficient. The quantizer is continuously held up for up to 64 cycles at a time. This matches approximately 3 components * 2 cycles = 6 cycles per image pixel, close to the measured full-frame rate of 0.1654 pixels/cycle.

This is a scheduling/implementation issue, not an inherent requirement of zigzag ordering. First investigate the rule conflicts (bank accesses and occupancy bookkeeping) and arrange for independent-bank reads/writes to cofire safely. Merely removing the urgency annotation does not demonstrate that the conflict is resolved. A fix needs a new schedule check, simultaneous-fire measurement, and bit-accuracy regression. No fix was made as part of this analysis.

## Implications for one image pixel per cycle

Even after restoring one coefficient/sample per cycle, the shared DUProc is a structural throughput limit:

| Mode | Component samples per image pixel | Ideal shared-DU input ceiling |
|---|---:|---:|
| 4:4:4 | 3 | 1/3 pixel/cycle |
| 4:2:2 | 2 | 1/2 pixel/cycle |
| 4:2:0 | 1.5 | 2/3 pixel/cycle |
| Grayscale | 1 | 1 pixel/cycle |

These are architectural ceilings, not measured results for the other modes. Sustained 4:4:4 at one image pixel/cycle requires at least three component samples/cycle of processing capacity (parallel lanes or appropriate faster-clock processing throughout the relevant path). A deeper input buffer alone absorbs finite bursts, but it cannot compensate indefinitely for a lower average processing rate.

For the UART context, replaying the measured double-buffered input service against one pixel arriving each cycle for this one frame gives a peak backlog of 29,181 pixels (87,543 bytes at 24 bits/pixel) ahead of the DUT. Single buffering gives 30,717 pixels. These are trace-specific finite-frame estimates with the same downstream behavior and timing origin, not universal FIFO sizing guarantees. At actual UART rates, the backlog must be recomputed with the actual arrival spacing.

## Method and limits

Used normal Bluesim make sim RUN_TEST=TestBlueJPEG, with -keep-fires and VCD output. analyze.py samples rule-firing, AXI handshake and FIFO EMPTY_N/DEQ signals once per rising edge, and summarize.py produces JSON. Checked 36,864 input transfers, 110,592 DU samples/coefficients, 5,479 symbols/codewords, and 3,527 output bytes. FIFO transfers with EMPTY_N low were zero at all sampled boundaries, and waveform S_RUNNING counts exactly match PERF0.

The test source stays valid continuously during the measured input interval, and the test output is continuously consumed without deliberate sink throttling. Results describe this compressible sample and present default tables. More detailed/noisy images and different tables can put much greater pressure on RLE/Huffman/byte output, especially after the ZigZag limit is fixed. Zero waiting here does not prove those stages can sustain every possible input at a higher producer rate.

Artifacts in this directory: double.log, single.log, double.sched, double.json, single.json, analyze.py, summarize.py, full VCDs and compact *.vcd.npz traces. Source snapshot is hdl/encoder, and its final test configuration is single buffering. The original workspace remains unchanged by this analysis.
