# Encoder throughput

Y, Cb and Cr data units share one lane at one component sample per cycle, so the bound is 1/3 pixel
per main clock cycle.

Figures are from simulation of the 1920 × 1080 crop of `assets/sample_1920x1280.bmp` (290,450 bytes,
byte-checked against the C++ reference), 1920 maximum width, double-buffered tiler, 12-bit
precision, default tables, counted in main clock cycles after configuration.

## Measured frame time

With a non-stalling sink the encoder reaches 99.74 % of the bound, with the DCT on the main clock or
at one eighth of it (the 200 MHz configuration).

| Configuration | Frame cycles (`PERF5`) | Pixels per cycle | Share of the 1/3 bound |
| --- | ---: | ---: | ---: |
| DCT on the main clock | 6,236,632 | 0.33249 | 99.75 % |
| DCT at one eighth of the main clock | 6,236,760 | 0.33248 | 99.74 % |
| Ideal | 6,220,800 | 0.33333 | 100 % |

`PERF5` counts from the accepted start to the end of the frame. The last byte leaves two cycles later.
With the DCT on the main clock the frame splits up as follows.

| Contribution | Cycles |
| --- | ---: |
| Before the first data unit, including the first 1920 × 8 strip of the tiler | 15,369 |
| Useful component samples | 6,220,800 |
| Bubbles at data unit boundaries | 257 |
| Flush and completion | 206 |
| Total | 6,236,632 |

The 0.25 % loss is fill and drain, not a reduced steady-state rate. The tiler serves one pixel per
cycle (one BRAM port per client). 2,041,066 of 2,073,599 tiler output intervals are one cycle, the
longer ones fall on chroma data units.

Throughput depends on the image, since long zero runs and long codewords cost cycles in the entropy
coder.

## Per-data-unit metadata queues

The dispatcher reserves one entry in each of three metadata queues per data unit.

| Queue | Token | Width | Depth | Released |
| --- | --- | ---: | ---: | --- |
| `Quantize.mkQuantize_RT.f_mode` | Luma or chroma table | 1 bit | 8 | After the last table request of the data unit |
| `RLE.mkRLE.f_comp` | Y, Cb or Cr DC predictor | 2 bits | 8 | After the last coefficient of the data unit |
| `HuffEncoder.mkHuffEncoder.f_meta` | Table selection and last data unit flag | 2 bits | 8 | After the final symbol of the data unit |

Queue depth limits the data units in flight. At 64 cycles per data unit, eight entries cover 512
cycles of latency. Four entries give 99.75 % with the DCT on the main clock but 72.6 % with the DCT at
one eighth, where the dispatcher waits 96 cycles after every four data units (0.242 pixels per
cycle). Eight entries restore full rate in both cases for 20 bits of storage. The depth is sized for
the tested clock ratios, other ratios may need more.

## Effect of the output path

Output stalls propagate back until the metadata queues fill and dispatch stops. A packetizer that
stopped collecting while sending limited the DDR3/UDP system to 91.4 % in simulation. It now collects
the next packet during transmission, and the [1080p30 demonstration](1080p30-demo.md) runs without
encoder output stalls.

## Reproducing

```sh
make -C hdl sim RUN_TEST=TbEncoderThroughput UDP_TEST_1080P=1 BUILDDIR=build/throughput_shared
make -C hdl sim RUN_TEST=TbEncoderThroughputDiv8 UDP_TEST_1080P=1 BUILDDIR=build/throughput_div8
make -C hdl sim RUN_TEST=TbEncoderThroughputShallow UDP_TEST_1080P=1 BUILDDIR=build/throughput_shallow
make -C hdl sim RUN_TEST=TestDCTShallow             # deep and shallow DCT bit-identical under stalls
```

`TbEncoderThroughputShallow` runs the DCT at one eighth with `shallow_dct`, which finishes a frame
80 cycles earlier (6,236,680 instead of 6,236,760).

The throughput tests encode two frames, check every byte and `tlast` and fail if `PERF5` exceeds three cycles per pixel
plus 5 %.

In `hdl/test/host/throughput`, `metadata_capacity_probe.py` copies the encoder packages with another
queue depth for simulation through `TEST_DIR`, and `profile_generated.py` records rule firings and
FIFO state per cycle in a copy of a Bluesim model.

```sh
python3 hdl/test/host/throughput/metadata_capacity_probe.py build/metadata_probe --depth 4
python3 hdl/test/host/throughput/profile_generated.py hdl/build/throughput_div8 hdl/build/throughput_div8_profile --run
```
