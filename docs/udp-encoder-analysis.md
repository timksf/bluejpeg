# Encoder resources in the DDR3/UDP system

Encoder in the routed DDR3 variant of the [DDR3/UDP system](udp-system.md), `xc7a200tfbg484-2`,
Vivado 2025.2. Configuration is 1920 maximum width, 4:4:4, 12-bit precision, double-buffered tiler,
register map and tables, with encoder and DCT on the 81.25 MHz MIG clock.

## Resources

| Resource | Encoder in the routed system | Share of the device | Complete system |
| --- | ---: | ---: | ---: |
| Slice LUTs | 6,559 | 4.9 % | 19,917 |
| LUT as logic | 5,581 | | |
| LUT as memory | 978 | | |
| Flip-flops | 4,313 | 1.6 % | 18,759 |
| BRAM tiles | 25 | 6.8 % | 33 |
| DSP48E1 | 11 | 1.5 % | 11 |

Counts are the leaf primitives below `i_sys_i_enc` after optimization and routing. The BRAM tiles are
24 RAMB36E1 in the tiler line buffer and two RAMB18E1 for the tables. The DSPs implement the DCT and
quantization multipliers.

Standalone (`mkJpegEncoderResource` in `hdl/src/synth/JpegEncoderResource.bsv`, synthesized out of
context) the same configuration uses 7,044 LUTs (1,038 as memory), 4,361 flip-flops, 25 BRAM tiles
and 11 DSPs. The integrated count is lower due to optimization across the encoder boundary.

## Critical paths

The system meets timing at 81.25 MHz with +0.343 ns setup and +0.008 ns hold slack.

| Path | Data path | Levels | Slack |
| --- | ---: | ---: | ---: |
| MIG reset synchronizer to a DU gearbox register, 3,496 loads | 11.45 ns, mostly routing | | +0.343 ns |
| Tiler buffer threshold through write address logic to line buffer BRAM | 10.09 ns, 3.79 ns logic | 14 | +1.542 ns |

The encoder is limited by the line buffer address logic, not the DCT. The tiler changes in
[timing-200mhz.md](timing-200mhz.md) address this path. Reset fan-out is the other limit when raising
the clock.

## Reproducing

```sh
make -C hdl bitstream SYSTEM=udp
make -C hdl bitstream SYNTH=ooc MAIN_MODULE=synth/JpegEncoderResource TOP_MODULE=mkJpegEncoderResource SCRIPT="$PWD/hdl/src/synth/script/encoder_resource.tcl"
vivado -mode batch -nojournal -nolog -source hdl/src/synth/script/udp_encoder_analysis.tcl
```

DDR3 system, standalone encoder, then encoder utilization and timing from the routed checkpoint.
BlueLens (`dep/bluelens`) maps routed primitives back to the BSV hierarchy, for example the DCT under
`i_du_proc/i_dct` and the line buffers under `i_img_tiler/i_pixels`.

```sh
make -C hdl SIM_TYPE=VERILOG compile_top SYSTEM=udp UDP_MEMORY=mig
bluetcl dep/bluelens/report_bsv_utilization.tcl --top mkPA200T_UDP_JPEG_Top --build hdl/build/BlueJPEG_PA200T_UDP_mig --vivado-cells hdl/build/udp_encoder_analysis/primitives.tsv --include '*i_enc*' --max-depth 12 --min-total 100 --out hdl/build/udp_encoder_analysis/bluelens_utilization.md
```
