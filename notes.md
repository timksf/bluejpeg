
### Project goals

1. **Configurable encoder generation** — Expose compile-time parameters
   (`max_img_width`, `dct_scale`, `quant_scale`) so that a single BSV
   codebase can generate Verilog cores with different area/precision
   trade-offs.  Ideally the configuration interface should be improved beyond
   raw `numeric type` parameters (e.g. a small config file or package that
   bundles a named preset).
2. **Runtime tunability** — Quantization tables and subsampling mode are
   selectable at runtime via the AXI4-Lite register interface, allowing
   quality/bandwidth trade-offs without re-synthesis.
3. **Hardware verification** — Validate the generated Verilog on real FPGA
   hardware (beyond simulation).