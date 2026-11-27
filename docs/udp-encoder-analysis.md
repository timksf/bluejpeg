# Encoder resources in the DDR3/UDP system

This document lists the resources of the encoder as part of the routed DDR3 variant of the
[DDR3/UDP system](udp-system.md) on the Artix-7 `xc7a200tfbg484-2`, built with Vivado 2025.2. The
encoder is configured for a maximum width of 1920, 8-bit YCbCr 4:4:4, 12-bit DCT and quantization
precision and a double-buffered tiler, and it includes its AXI4-Lite register map and programmable
tables. In this variant the encoder and its DCT share the 81.25 MHz MIG user clock.

## Resources

| Resource | Encoder in the routed system | Share of the device | Complete system |
| --- | ---: | ---: | ---: |
| Slice LUTs | 6,559 | 4.9 % | 19,917 |
| LUT as logic | 5,581 | | |
| LUT as memory | 978 | | |
| Flip-flops | 4,313 | 1.6 % | 18,759 |
| BRAM tiles | 25 | 6.8 % | 33 |
| DSP48E1 | 11 | 1.5 % | 11 |

The encoder counts are the leaf primitives below the encoder instance `i_sys_i_enc` in the optimized
and routed system, so they reflect the encoder after cross-boundary optimization rather than an
independent area build. The 25 BRAM tiles are 24 RAMB36E1 in the tiler line buffer and two RAMB18E1
in the table storage. The 11 DSPs implement the DCT and quantization multipliers.

For comparison, `mkJpegEncoderResource` in `hdl/src/synth/JpegEncoderResource.bsv` instantiates the
same encoder configuration on its own with its streams, register interface, frame start, interrupt
and busy signal as ports. Synthesized and optimized out of context with the same clock, without
placement and routing, it uses 7,044 LUTs (6,006 as logic and 1,038 as memory, 930 of them
distributed RAM and 108 shift registers), 4,361 flip-flops, 25 BRAM tiles and 11 DSPs. The integrated
count is lower because the surrounding system lets synthesis and physical optimization remove or
merge logic at the encoder boundary.

## Critical paths

The system meets timing at 81.25 MHz with +0.343 ns setup and +0.008 ns hold slack. Its worst path
is synchronous reset distribution from the MIG reset synchronizer into a gearbox register of the DU
processing, an 11.45 ns path that is almost entirely routing to a net with 3,496 loads.

The worst path with both ends inside the encoder runs from the buffer threshold register of the
tiler through its write address logic into the address input of a line buffer BRAM. It has a data
path of 10.09 ns, 3.79 ns of logic and 6.30 ns of routing, over 14 logic levels including eight
CARRY4, and +1.542 ns of slack. The line buffer address and control logic, not the DCT arithmetic,
limits the encoder in this build. The tiler changes for 200 MHz
address this path, and reset fan-out is the other point to consider when raising the clock.

## Reproducing

```sh
make -C hdl bitstream SYSTEM=udp
make -C hdl bitstream SYNTH=ooc MAIN_MODULE=synth/JpegEncoderResource TOP_MODULE=mkJpegEncoderResource SCRIPT="$PWD/hdl/src/synth/script/encoder_resource.tcl"
vivado -mode batch -nojournal -nolog -source hdl/src/synth/script/udp_encoder_analysis.tcl
```

The first command builds the DDR3 system, the second the standalone encoder, and the analysis script
reads the routed system checkpoint and writes the encoder utilization and timing reports. The BlueLens
tool in `dep/bluelens` maps the routed primitives back to the BSV hierarchy, which locates for example
the DCT under `i_du_proc/i_dct` and the line buffers under `i_img_tiler/i_pixels`.

```sh
make -C hdl SIM_TYPE=VERILOG compile_top SYSTEM=udp UDP_MEMORY=mig
bluetcl dep/bluelens/report_bsv_utilization.tcl --top mkPA200T_UDP_JPEG_Top --build hdl/build/BlueJPEG_PA200T_UDP_mig --vivado-cells hdl/build/udp_encoder_analysis/primitives.tsv --include '*i_enc*' --max-depth 12 --min-total 100 --out hdl/build/udp_encoder_analysis/bluelens_utilization.md
```
