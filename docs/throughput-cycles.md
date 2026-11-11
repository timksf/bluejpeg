The current encoder has two different throughput results depending on the DCT clock ratio. With a shared main/DCT clock and an unrestricted byte sink, it reaches **99.746% of the 1/3 pixel-per-cycle ceiling**. With the **8:1 main/DCT clock ratio used by the 200 MHz OOC wrapper**, it reaches only **72.595%**. The latter shortfall comes from insufficient DU metadata capacity, confirmed by an isolated simulation experiment that changes only FIFO depths.

All measurements use the current encoder, 1920 × 1080 pixels, YCbCr 4:4:4, double-buffered tiling, 12-bit DCT and quantization scales, the same cropped image as `TestJpegUdpSystem`, and default tables. Results are in **main-clock cycles**, without conversion to frequency or frames per second. Each tested frame produces 290,450 bytes and is compared byte for byte with the C++ reference. Upload, reference generation, table initialization, and software configuration occur before the measurement.

| Standalone encoder, unrestricted byte sink | Frame cycles (`PERF5`) | Pixels/main cycle | Fraction of 1/3 limit |
| --- | ---: | ---: | ---: |
| Shared clock, production metadata depths | 6,236,632 | 0.33248715 | 99.7461% |
| DCT at main/8, production metadata depths | 8,569,171–8,569,175 | 0.24198362–0.24198373 | 72.5951% |
| DCT at main/8, metadata depths increased to eight in isolated copies | 6,236,759–6,236,760 | 0.33248033–0.33248038 | 99.7441% |
| Ideal useful work | 6,220,800 | 0.33333333 | 100% |

Two consecutive frames pass the reference comparison in each standalone configuration. `PERF5` measures the encoder's frame-processing interval. The last output byte reaches the testbench consumer two cycles later, and the testbench finishes its busy observation four cycles later. These small endpoint differences do not affect the diagnosis.

The 8:1 bottleneck is a credit window imposed by these queues:

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

Initial line filling, pipeline draining, and smaller irregularities reduce that schedule estimate to the measured 0.241984. There is no need to infer a DCT arithmetic initiation-interval problem: increasing only those metadata queues to eight entries restores almost the entire ideal rate while retaining the 8:1 clocks and identical arithmetic. This experiment uses isolated package copies under `hdl/build/throughput_metadata8_sources/`. **Production HDL was not changed**, and the capacity experiment was not synthesized. Eight entries are sufficient for this tested configuration, not a derived universal minimum for every clock ratio or pipeline depth.

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

The appropriate next changes are therefore distinct: provide enough DU metadata credits for the 8:1 pipeline latency, and overlap UDP packet collection with transmission if system throughput should approach the encoder's service rate. The simulation results do not establish physical timing for those prospective changes, nor a universal throughput bound for images with different entropy or tables.

The added harnesses are `hdl/test/TbEncoderThroughput.bsv` and `TbEncoderThroughputDiv8.bsv`. Reproduce the standalone measurements from the repository root in the usual development environment:

```sh
make -C hdl sim RUN_TEST=TbEncoderThroughput UDP_TEST_1080P=1 BUILDDIR=build/throughput_1080p_direct CXX_NO_OPT=
make -C hdl sim RUN_TEST=TbEncoderThroughputDiv8 UDP_TEST_1080P=1 BUILDDIR=build/throughput_1080p_div8 CXX_NO_OPT=
python3 hdl/test/host/throughput/metadata_capacity_probe.py hdl/build/throughput_metadata8_sources --depth 8
make -C hdl sim RUN_TEST=TbEncoderThroughputDiv8 UDP_TEST_1080P=1 TEST_DIR="$PWD/hdl/build/throughput_metadata8_sources" BUILDDIR=build/throughput_1080p_div8_metadata8 CXX_NO_OPT=
```

The metadata probe copies only the affected encoder packages and changes the FIFO-depth declarations. It records source hashes in its manifest and uses symlinks for the existing test fixtures. Compiler warnings about duplicate package sources are expected: the experiment directory precedes the production encoder package directory in the import path.

To observe an already-built model:

```sh
python3 hdl/test/host/throughput/profile_generated.py hdl/build/throughput_1080p_div8 hdl/build/throughput_1080p_div8_profile --run
python3 hdl/test/host/throughput/profile_generated.py hdl/build/throughput_1080p_direct hdl/build/throughput_1080p_direct_profile --run
python3 hdl/test/host/throughput/profile_generated.py hdl/build/timing_sim_1080p_final hdl/build/throughput_1080p_profile --run
```

The observer modifies only a generated model in its output directory. It snapshots main-clock FIFO state before rule execution and records actual main-clock rule calls, including firing decisions evaluated later in the schedule. It excludes slow-clock rule calls from main-clock counts, preserves the original model implementation and byte checks, and links against the original simulation library. It requires the matching `bluetcl` and a compatible C++ compiler. The observed runs retained the uninstrumented cycle counters and passed every reference comparison.

Local logs and results are saved in `hdl/build/throughput_analysis/`, with rule traces in the three profile directories above. `results.json` contains per-frame counts and DU-gap histograms. No production HDL changes or throughput optimizations were applied during this analysis.
