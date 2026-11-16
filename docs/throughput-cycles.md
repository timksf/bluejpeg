# Encoder throughput

The encoder processes one component sample per main clock cycle. Y, Cb and Cr data units share a
single processing lane, so a 4:4:4 pixel needs at least three cycles and the upper bound is 1/3 pixel
per main clock cycle. This document shows how close the encoder gets to that bound, where the
remaining cycles go and how the queues between the stages are sized.

All figures come from simulation of a 1920 × 1080 YCbCr 4:4:4 frame with a maximum width of 1920,
a double-buffered tiler, 12-bit DCT and quantization precision and the default tables. They are
counted in main clock cycles, independent of the clock frequency. The image is the crop of
`assets/sample_1920x1280.bmp` used by the system tests. Every frame produces 290,450 bytes and is
compared byte for byte with the C++ reference. Table initialization and configuration happen before
the measurement.

## Measured frame time

With an output sink that never stalls, the encoder reaches 99.74 % of the bound, whether the DCT
runs on the main clock or at one eighth of it, as in the 200 MHz configuration.

| Configuration | Frame cycles (`PERF5`) | Pixels per cycle | Share of the 1/3 bound |
| --- | ---: | ---: | ---: |
| DCT on the main clock | 6,236,632 | 0.33249 | 99.75 % |
| DCT at one eighth of the main clock | 6,236,760 | 0.33248 | 99.74 % |
| Ideal | 6,220,800 | 0.33333 | 100 % |

`PERF5` counts from the accepted start request to the end of the frame. The last byte reaches the
consumer two cycles later.

With the DCT on the main clock, the lane advances 6,220,800 component samples within an interval of
6,221,057 cycles, so the only loss in steady state is 257 single-cycle bubbles at data unit
boundaries. The whole frame splits up as follows.

| Contribution | Cycles |
| --- | ---: |
| Before the first data unit, including the first 1920 × 8 strip of the tiler | 15,369 |
| Useful component samples | 6,220,800 |
| Bubbles at data unit boundaries | 257 |
| Flush and completion | 206 |
| Total | 6,236,632 |

The remaining 0.25 % is therefore filling and draining, not a reduced steady-state rate. The tiler
serves one pixel per cycle, since each logical client is bound to its own BRAM port, and in the trace
2,041,066 of the 2,073,599 intervals between tiler outputs are one cycle long. The longer gaps fall
where the chroma data units are processed.

Throughput depends on the image. Long runs of zeros and long codewords cost cycles in the run-length
and Huffman stages, and a different image or table set can produce more output bytes per pixel.

## Per-data-unit metadata queues

When the dispatcher sends the first sample of a data unit, it reserves one entry in three small
queues that carry the data unit's metadata to later stages.

| Queue | Token | Width | Depth | Released |
| --- | --- | ---: | ---: | --- |
| `Quantize.mkQuantize_RT.f_mode` | Luma or chroma table | 1 bit | 8 | After the last table request of the data unit |
| `RLE.mkRLE.f_comp` | Y, Cb or Cr DC predictor | 2 bits | 8 | After the last coefficient of the data unit |
| `HuffEncoder.mkHuffEncoder.f_meta` | Table selection and last data unit flag | 2 bits | 8 | After the final symbol of the data unit |

A data unit can only start when all three queues have room, so their depth limits how many data
units can be in flight between dispatch and the last stage. At one data unit per 64 cycles, eight
entries cover 512 cycles of pipeline latency. With four entries the encoder already reached 99.75 %
of the bound when the DCT ran on the main clock, but only 72.6 % with the DCT at one eighth, because
the slower DCT and its gearboxes add latency. The dispatcher then sent four data units and waited
96 cycles for a free entry, which gives 0.242 pixels per cycle, as measured. Eight entries restore
the full rate in both configurations at a cost of 20 bits of storage. They are sized for the tested
configuration and are not a bound for arbitrary clock ratios, and long downstream stalls still stop
the dispatcher safely through back-pressure.

## Effect of the output path

A slow consumer stalls the encoder through its output stream. Stalls propagate back through frame
writer, bitstream writer, Huffman encoder and run-length coder until the metadata queues fill and
dispatch stops. In the DDR3/UDP system this happened when the packetizer stopped collecting bytes
while it sent a packet, which limited the system to 91.4 % of the bound in simulation despite ample
average Ethernet bandwidth. The packetizer now collects the next packet while sending the previous
one, and the [1080p30 demonstration](1080p30-demo.md) runs without encoder output stalls.

## Reproducing

```sh
make -C hdl sim RUN_TEST=TbEncoderThroughput UDP_TEST_1080P=1 BUILDDIR=build/throughput_shared
make -C hdl sim RUN_TEST=TbEncoderThroughputDiv8 UDP_TEST_1080P=1 BUILDDIR=build/throughput_div8
```

Both testbenches encode two consecutive frames, compare every byte and `tlast` with the C++
reference and fail if `PERF5` exceeds three cycles per pixel plus 5 %, which also covers the strip
filling and draining of the 192 × 192 fixture.

Two tools in `hdl/test/host/throughput` support deeper analysis. `metadata_capacity_probe.py` copies
the affected encoder packages with a different queue depth into a separate directory, which can then
be simulated by passing it as `TEST_DIR`. `profile_generated.py` instruments a generated Bluesim model
in its own output directory to record which rules fire in every main clock cycle and the state of the
FIFOs, without changing the original model or its byte checks.

```sh
python3 hdl/test/host/throughput/metadata_capacity_probe.py build/metadata_probe --depth 4
python3 hdl/test/host/throughput/profile_generated.py hdl/build/throughput_div8 hdl/build/throughput_div8_profile --run
```
