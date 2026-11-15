The [1080p30 demonstration experiment](1080p30-demo.md) adds overlapping UDP packet collection and transmission and separates the 200 MHz encoder from 125 MHz UDP/control using explicit CDC. Its exact-ratio split-clock simulation passes three reference-identical full-HD frames at 3,914,026 system cycles per repeat, equivalent to 31.936 fps at 125 MHz. The integrated route meets 200 MHz encoder timing with 0.000 ns setup WNS and +0.040 ns hold WHS. The user-approved SRAM demonstration now runs at 31.94684 fps on hardware, with reference-identical 1920 × 1080 JPEGs. The UDP packetizer measurements below describe the earlier, non-overlapping implementation.

The original four-entry DU metadata queues caused different throughput results depending on the DCT clock ratio. With a shared main/DCT clock and an unrestricted byte sink, the four-entry design reached **99.746% of the 1/3 pixel-per-cycle ceiling**. With the **8:1 main/DCT clock ratio used by the 200 MHz OOC wrapper**, it reached only **72.595%**. The latter shortfall came from insufficient DU metadata capacity, confirmed by an isolated simulation experiment that changes only FIFO depths.

The full-HD measurements use the encoder, 1920 × 1080 pixels, YCbCr 4:4:4, double-buffered tiling, 12-bit DCT and quantization scales, the same cropped image as `TestJpegUdpSystem`, and default tables. Results are in **main-clock cycles**, without conversion to frequency or frames per second. Each tested frame produces 290,450 bytes and is compared byte for byte with the C++ reference. Upload, reference generation, table initialization, and software configuration occur before the measurement.

| Standalone encoder, unrestricted byte sink | Frame cycles (`PERF5`) | Pixels/main cycle | Fraction of 1/3 limit |
| --- | ---: | ---: | ---: |
| Shared clock, original four-entry metadata queues | 6,236,632 | 0.33248715 | 99.7461% |
| DCT at main/8, original four-entry metadata queues | 8,569,171–8,569,175 | 0.24198362–0.24198373 | 72.5951% |
| DCT at main/8, eight entries (initial experiment and production fix) | 6,236,759–6,236,760 | 0.33248033–0.33248038 | 99.7441% |
| Ideal useful work | 6,220,800 | 0.33333333 | 100% |

Two consecutive frames pass the reference comparison in each standalone configuration. `PERF5` measures the encoder's frame-processing interval. The last output byte reaches the testbench consumer two cycles later, and the testbench finishes its busy observation four cycles later. These small endpoint differences do not affect the diagnosis.

The original 8:1 bottleneck was a credit window imposed by these queues:

- `Quantize.mkQuantize_RT`: `f_mode <- mkSizedFIFO(4)`
- `RLE.mkRLE`: `f_comp <- mkSizedFIFO(4)`
- `HuffEncoder.mkHuffEncoder`: `f_meta <- mkSizedFIFO(4)`

`BlueJPEG.r_disp_to_duproc` enqueues one item in all three queues on the first sample of every 64-sample DU. Its compiled predicate requires all three queues to have space before that first sample can advance. The mode is retired by quantization, the component ID by RLE, and Huffman metadata when symbol preparation reaches the end of the DU. Slowing the rigid DCT to main/8 increases the number of main-clock cycles before those retirements. Four metadata entries no longer cover the pipeline latency.

The main/8 trace records **2,332,700 idle dispatch cycles** between the first and last component sample. Input data is available during these stalls, and the centered-pixel FIFO has no blocked cycles. Every classified dispatch stall has a full metadata queue at a DU boundary. There are no schedule-priority blockers on `r_disp_to_duproc`.

The DU-start intervals show the resulting pattern: most are 64 cycles, but 23,940 intervals in the first frame are 160 cycles. The dominant behavior is approximately four DUs followed by a 96-cycle credit wait:

```text
4 × 64 component samples / (4 × 64 + 96) main cycles
    = 8/11 component sample per main cycle
    = 8/33 image pixel per main cycle
    ≈ 0.242424 image pixel per main cycle
```

Initial line filling, pipeline draining, and smaller irregularities reduce that schedule estimate to the measured 0.241984. There is no need to infer a DCT arithmetic initiation-interval problem: increasing only those metadata queues to eight entries restores almost the entire ideal rate while retaining the 8:1 clocks and identical arithmetic. This experiment uses isolated package copies under `hdl/build/throughput_metadata8_sources/`. That initial experiment did not change production HDL and was not synthesized. Production now uses eight entries in these three queues. Eight entries are sufficient for this tested configuration, not a derived universal minimum for every clock ratio or pipeline depth.

The production fix retains ordinary guarded `mkSizedFIFO` queues, in the main clock domain, with these capacities:

| Owner / queue | Token | Width | Capacity | Retirement |
| --- | --- | ---: | ---: | --- |
| `Quantize.mkQuantize_RT.f_mode` | Luma/chroma table selection per DU | 1 bit | 8 DUs | Last quantizer table request in the DU |
| `RLE.mkRLE.f_comp` | Y/Cb/Cr DC predictor selection per DU | 2 bits | 8 DUs | Last coefficient processed in the DU |
| `HuffEncoder.mkHuffEncoder.f_meta` | Table selection and final-DU flag | 2 bits | 8 DUs | Final symbol prepared in the DU |

Dispatch still reserves all three tokens atomically with the first sample of a 64-sample DU. Each queue keeps its existing ordering, retirement and rewind behavior. At one DU per 64 main cycles, eight entries provide a 512-cycle credit window, covering the observed DCT/gearbox and downstream latency in the tested main/8 configuration. This is a measured capacity choice, not a guarantee for arbitrary clock ratios or entropy. Prolonged downstream stalls still backpressure dispatch safely. Increasing these three queues from four to eight adds 20 bits of payload capacity plus queue-control overhead. Keeping the constructor preserves registered full/empty flags and avoids adding a combinational dequeue-to-enqueue ready path. The static-table `mkQuantize` queue remains at four entries; it is outside this encoder path.

`TbEncoderThroughput` now checks `PERF5` against a budget of `3 * pixels * 105 / 100` main cycles for each of two consecutive frames, as well as comparing every JPEG byte and TLAST with the C++ reference. The 5% allowance includes strip filling/draining for both the 192 × 192 and 1920 × 1080 fixtures; it rejects the original main/8 metadata bottleneck.

Production validation (BSC 2024.07, 1920 × 1080, the configuration above) reproduced 6,236,760 and 6,236,759 cycles at main/8 and 6,236,632 cycles for both shared-clock frames. All four frames matched the 290,450-byte C++ reference, including TLAST. A four-entry negative control matched its first frame but failed the new performance check at 8,569,171 cycles, with a nonzero simulator exit. The main/8 fix reduces frame cycles by 27.22% and reaches 99.7441% of the scalar limit. Generated RTL for `mkBlueJPEGTop_1920_12` confirms guarded FIFO depths of eight and payload widths of 1/2/2 bits; its dispatch schedule has no blocking rules. The existing `TestBlueJPEGGrayBackpressure` test also passed with periodic output stalls (1,362 bytes, TLAST/EOI checked). Validation summaries are saved in `hdl/build/metadata_fix_validation/`. Physical timing and synthesized utilization have not been rerun for this fix.


The historical roughly 25% loss in the shared-clock board build had a different cause. The general banked-memory router allowed only one outstanding tiler read per client, which prevented consecutive-cycle reads. The timing work replaced that use with the direct dual-port backend. In the new shared-clock trace, 2,041,066 of the 2,073,599 tiler-output intervals are one cycle. The remaining long gaps primarily reflect component dispatch while the chroma DUs are processed. The previous two-cycle tiler service limit is gone.

With a shared clock and an unrestricted output sink, the scalar DU lane advances 6,220,800 component samples over a 6,221,057-cycle interval. Its only loss inside that interval is **257 one-cycle DU-boundary bubbles**. The full frame has this cycle accounting:

| Contribution | Cycles |
| --- | ---: |
| Before first DU sample, including the first 1920 × 8 tiler strip | 15,369 |
| Useful component-sample advances | 6,220,800 |
| DU-boundary bubbles | 257 |
| Flush and completion | 206 |
| Total encoder frame cycles | 6,236,632 |

Thus almost all of the remaining 0.254% frame-level loss in that configuration is initial filling and final draining, not a reduced steady-state service rate.

The current **shared-clock UDP system simulation** has a separate output bottleneck. Its repeat period is **6,804,675 cycles**, or **0.30473167 pixel/cycle**, which is **91.4195% of ideal**. This is the counter value already present in the final timing-task simulation. The older board result was 8,341,457 cycles and 74.5769% of ideal. The older simulation fixture recorded 8,705,650 cycles. Those historical measurements should not be confused with the new 8:1 metadata-capacity issue.

The UDP trace has **283 long DU-start gaps** for **284 packets**. In the middle repeated frame, long gaps account for 566,498 lost dispatch cycles, with another 204 cycles in one- and two-cycle bubbles. During 558,768 of those 566,702 dispatch-idle cycles, the packetizer is in `UdpPayload`. Another 7,934 occur while it has returned to collection and the backed-up pipeline is recovering. The encoder's framewriter output is blocked for 647,063 cycles. These overlapping counters are evidence of propagation and must not be added together.

`UdpPacketizer` has one 1024-byte BRAM FIFO. Its `jpeg.put` method is enabled only in `UdpCollect`. After filling a packet, it stops collecting JPEG data while requesting the header and sending the packet, then resumes collection after the final payload handshake. The testbench also throttles transmit ready to 11 of every 16 cycles and consumes through its receive FSM. Consequently, packet draining repeatedly blocks the encoder despite substantial average output-bandwidth headroom. The backpressure propagates through framewriter, bitstream, Huffman and RLE, eventually filling DU metadata queues and stopping dispatch. The standalone sink experiment removes those packet stalls and demonstrates their effect independently of the main/8 capacity experiment.

The metadata fix provides eight DU credits for the 8:1 pipeline latency. Overlapping UDP packet collection with transmission remains a separate change if system throughput should approach the encoder's service rate. The simulation results do not establish physical timing for these changes, nor a universal throughput bound for images with different entropy or tables.

The added harnesses are `hdl/test/TbEncoderThroughput.bsv` and `TbEncoderThroughputDiv8.bsv`. Reproduce the standalone measurements from the repository root in the usual development environment:

```sh
make -C hdl sim RUN_TEST=TbEncoderThroughput UDP_TEST_1080P=1 BUILDDIR=build/throughput_1080p_direct CXX_NO_OPT=
make -C hdl sim RUN_TEST=TbEncoderThroughputDiv8 UDP_TEST_1080P=1 BUILDDIR=build/throughput_1080p_div8 CXX_NO_OPT=
python3 hdl/test/host/throughput/metadata_capacity_probe.py hdl/build/throughput_metadata8_sources --depth 8
make -C hdl sim RUN_TEST=TbEncoderThroughputDiv8 UDP_TEST_1080P=1 TEST_DIR="$PWD/hdl/build/throughput_metadata8_sources" BUILDDIR=build/throughput_1080p_div8_metadata8 CXX_NO_OPT=
```

The metadata probe copies only the affected encoder packages and changes the FIFO-depth declarations, accepting either the old or new production depths. To reproduce the old bottleneck, use `--depth 4` and a separate build directory; the throughput budget is expected to fail for that negative control. It records source hashes in its manifest and uses symlinks for the existing test fixtures. Compiler warnings about duplicate package sources are expected: the experiment directory precedes the production encoder package directory in the import path.

To observe an already-built model:

```sh
python3 hdl/test/host/throughput/profile_generated.py hdl/build/throughput_1080p_div8 hdl/build/throughput_1080p_div8_profile --run
python3 hdl/test/host/throughput/profile_generated.py hdl/build/throughput_1080p_direct hdl/build/throughput_1080p_direct_profile --run
python3 hdl/test/host/throughput/profile_generated.py hdl/build/timing_sim_1080p_final hdl/build/throughput_1080p_profile --run
```

The observer modifies only a generated model in its output directory. It snapshots main-clock FIFO state before rule execution and records actual main-clock rule calls, including firing decisions evaluated later in the schedule. It excludes slow-clock rule calls from main-clock counts, preserves the original model implementation and byte checks, and links against the original simulation library. It requires the matching `bluetcl` and a compatible C++ compiler. The observed runs retained the uninstrumented cycle counters and passed every reference comparison.

Local logs and results are saved in `hdl/build/throughput_analysis/`, with rule traces in the three profile directories above. `results.json` contains per-frame counts and DU-gap histograms. Those saved results describe the original analysis before the production metadata fix.

The production-fix validation uses separate build directories:

```sh
make -C hdl sim RUN_TEST=TbEncoderThroughputDiv8 UDP_TEST_1080P=1 BUILDDIR=build/metadata_fix_div8 CXX_NO_OPT=
make -C hdl sim RUN_TEST=TbEncoderThroughput UDP_TEST_1080P=1 BUILDDIR=build/metadata_fix_shared CXX_NO_OPT=
make -C hdl sim RUN_TEST=TestBlueJPEGGrayBackpressure BUILDDIR=build/metadata_fix_stalls CXX_NO_OPT=
make -C hdl compile_top SIM_TYPE=VERILOG SYNTH=ooc BUILDDIR=build/metadata_fix_rtl
```
