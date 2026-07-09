# BlueJPEG Interactive Demo Execution Plan

This plan captures the intended design for an interactive Python demo for the
BlueJPEG FPGA JPEG encoder. It is written so a future Codex session can upload
or read this file and continue implementation without needing the original
discussion.

## Goal

Build a reusable Python-based demo and instrumentation layer for BlueJPEG.

The final experience should let a user select an image, encode it through one
of several backends, display the original image beside the compressed JPEG
output, and show meaningful image, transport, and hardware statistics.

The same demo API should support:

- Real CMod A7 hardware over the existing UART route switch.
- RTL simulation through cocotb, preferably direct AXI-lite plus AXI-stream.
- Full top-level UART simulation through cocotb as a slower end-to-end mode.
- Bluesim/BDPI simulation through a dedicated dynamic test harness.
- A software or mock backend for development without hardware or simulator.

## Repo Context

Important existing files:

- `examples/cmoda7/uart_axis.py`
  - Current hardware UART demo.
  - Uses route byte `C` for control/CSR access and `D` for pixel data.
  - Packs RGB input as YCbCr bytes in `(Cr, Cb, Y)` order.
  - Configures the JPEG core over UART-to-AXI-lite.
  - Captures JPEG bytes until the EOI marker `0xffd9`.

- `dep/blueuart/hdl/script/uart_axi_lite.py`
  - Existing Python UART-to-AXI-lite protocol helper.
  - Provides `UartAxiLite.read()` and `UartAxiLite.write()`.
  - Good base for reusable CSR tooling.

- `hdl/encoder/src/BlueJPEGRegs.bsv`
  - Source of truth for BlueJPEG CSR layout.
  - Important registers:
    - `0x00 MIV`
    - `0x04 CTRL.START`
    - `0x08 STS.RDY/CGB/DONE/ERR/INV`
    - `0x0c IMSZ`
    - `0x10 SUBS`
    - `0x14 CGEN`
    - `0x30 PERF0` cycles
    - `0x34 PERF1` pixels
    - `0x38 PERF2` output bytes
    - table regions starting at `0x100`

- `examples/cmoda7/tb/test_cmod_jpeg_core.py`
  - Existing cocotb direct-core test.
  - Drives AXI-lite and AXI-stream directly.
  - Fastest likely RTL simulation backend.

- `examples/cmoda7/tb/test_cmod_jpeg_top.py`
  - Existing cocotb top-level UART test.
  - Bit-bangs UART and verifies the full CMod top-level path.
  - Useful for end-to-end verification, likely too slow for default demo use.

- `hdl/encoder/test/TestBlueJPEG.bsv`
  - Existing Bluesim/BDPI test.
  - Loads images through BDPI, configures BlueJPEG, feeds stream input, writes
    JPEG output to a file, and prints performance counters.
  - Should become the basis for a dynamic Bluesim demo harness.

- `hdl/encoder/src/BDPI.bsv`
  - Existing BDPI imports, including image loading, SimRAM, image writing, and
    software JPEG reference helpers.

- `assets/`
  - Contains sample BMP/JPEG inputs that can be used for default demos and
    smoke tests.

## Design Principles

- Keep hardware transport and CSR editing reusable. The JPEG demo should be a
  client of this layer, not the owner of it.
- Give every encoder path the same Python backend interface.
- Make the UI useful without hardware by supporting software/mock/simulation
  backends.
- Prefer direct cocotb core simulation for interactive RTL use. Keep full UART
  cocotb simulation as an explicit slower verification mode.
- Use Bluesim/BDPI for fast BSV-level simulation once a dynamic harness exists.
- Keep first implementation practical: a local Python web app is enough.

## Proposed Directory Layout

Create new Python tooling under `tools/`:

```text
tools/
  bluejpeg_demo/
    __init__.py
    app.py
    backends.py
    image_utils.py
    jpeg_utils.py
    metrics.py
    register_maps.py
    sim_runner.py
  uart_axilite/
    __init__.py
    transport.py
    csr.py
    cli.py
```

Optional later layout:

```text
hdl/encoder/test/TestBlueJPEGDemo.bsv
examples/cmoda7/tb/demo_cmod_jpeg_core.py
examples/cmoda7/tb/demo_cmod_jpeg_top.py
```

## Common Backend API

Implement a small common model:

```python
from dataclasses import dataclass
from pathlib import Path

@dataclass
class EncodeRequest:
    image_path: Path
    output_dir: Path
    subsampling: str = "444"
    timeout_s: float = 30.0

@dataclass
class EncodeResult:
    backend_name: str
    jpeg_path: Path
    width: int
    height: int
    raw_input_bytes: int
    jpeg_bytes: int
    compression_ratio: float
    bits_per_pixel: float
    elapsed_s: float
    hw_cycles: int | None = None
    hw_pixels: int | None = None
    hw_output_bytes: int | None = None
    log: str = ""
```

Backends should expose:

```python
class EncoderBackend:
    name: str

    def available(self) -> bool:
        ...

    def encode(self, request: EncodeRequest) -> EncodeResult:
        ...
```

Initial backend list:

- `SoftwareBackend`
- `HardwareUartBackend`
- `CocotbCoreBackend`
- `CocotbUartTopBackend`
- `BluesimBackend`
- `MockReplayBackend`

## Phase 1: Shared Python Utilities

Extract reusable code from `examples/cmoda7/uart_axis.py` and cocotb tests.

Create `tools/bluejpeg_demo/image_utils.py`:

- Load an image with Pillow.
- Convert to RGB.
- Return dimensions.
- Pack RGB pixels into FPGA input bytes as `(Cr, Cb, Y)`.
- Optionally resize or reject unsupported dimensions.

Create `tools/bluejpeg_demo/jpeg_utils.py`:

- Parse JPEG dimensions from byte payload.
- Validate SOI/EOI.
- Save JPEG payload.
- Decode JPEG with Pillow for display/comparison.

Create `tools/bluejpeg_demo/metrics.py`:

- Raw input bytes.
- JPEG bytes.
- Compression ratio.
- Bits per pixel.
- Host elapsed time.
- Optional PSNR and SSIM if dependencies are available.
- Optional difference heatmap.

Acceptance criteria:

- `examples/cmoda7/uart_axis.py` can be refactored to use these helpers without
  behavior changes.
- Existing sample `assets/sample_192x192.bmp` can be packed and validated.

## Phase 2: Reusable UART AXI-lite CSR Tool

Create `tools/uart_axilite/transport.py` around the existing
`dep/blueuart/hdl/script/uart_axi_lite.py` helper.

Do not duplicate the wire protocol unless needed. Prefer importing the existing
`UartAxiLite` class and wrapping it with a cleaner API.

Create `tools/uart_axilite/csr.py`:

- `RegisterMap`
- `Register`
- `Field`
- Decode fields from integer register values.
- Encode field writes when possible.
- Track access type: read-only, read-write, write-one-clear, write-one-set.

Create `tools/bluejpeg_demo/register_maps.py`:

- Declarative BlueJPEG CSR map matching `BlueJPEGRegs.bsv`.
- Include perf counters at `0x30`, `0x34`, `0x38`.

Create `tools/uart_axilite/cli.py`:

Target commands:

```sh
python -m tools.uart_axilite.cli --port /dev/ttyUSB1 --baud 1000000 dump
python -m tools.uart_axilite.cli read STS
python -m tools.uart_axilite.cli write IMSZ 0x00c000c0
python -m tools.uart_axilite.cli poll STS.RDY=1 --timeout 5
python -m tools.uart_axilite.cli repl
```

Acceptance criteria:

- Can dump named BlueJPEG registers through the UART-to-AXI-lite master.
- Can read/write by either numeric address or register name.
- Can decode `STS`, `IMSZ`, `SUBS`, `CGEN`, and perf counters.
- CLI remains reusable for future register maps.

## Phase 3: Hardware UART Backend

Implement `HardwareUartBackend` by reusing/refactoring
`examples/cmoda7/uart_axis.py`.

Responsibilities:

- Open serial port.
- Reset serial buffers.
- Select control route with byte `C`.
- Wait for `STS.RDY`.
- Trigger Huffman codegen for four tables via `CGEN`.
- Write `IMSZ`.
- Write `SUBS`.
- Pulse `CTRL.START`.
- Select data route with byte `D`.
- Send packed image payload.
- Receive JPEG bytes until EOI.
- Read `PERF0`, `PERF1`, and `PERF2` after completion when available.
- Return an `EncodeResult`.

Important details:

- Preserve route idle delays from the current script.
- Preserve chunking and timeout options.
- Keep default baudrate `1_000_000`.
- Keep default port behavior compatible with current use.

Acceptance criteria:

- Existing command-line hardware flow still works.
- Demo backend can encode `assets/sample_192x192.bmp` on hardware.
- Result contains hardware perf counters when CSR reads succeed.

## Phase 4: Cocotb Direct-Core Simulation Backend

Implement `CocotbCoreBackend` first among simulation backends.

Recommended approach:

- Add a demo-oriented cocotb test or adapt `test_cmod_jpeg_core.py` to support
  a single selected test through environment variables.
- Continue using:
  - `BMP_PATH`
  - `EXPECTED_WIDTH`
  - `EXPECTED_HEIGHT`
  - `OUTPUT_JPEG`
- Add optional `OUTPUT_STATS_JSON` for machine-readable results.

Backend behavior:

- Convert or verify selected input image as BMP-compatible input.
- Launch the existing cocotb make target through `subprocess.run`.
- Pass paths and dimensions via environment variables.
- Capture stdout/stderr into `EncodeResult.log`.
- Read `OUTPUT_JPEG`.
- Read optional `OUTPUT_STATS_JSON`.
- Compute host-side metrics if sim stats are not available.

Why this backend first:

- It exercises real RTL.
- It bypasses UART bit-level framing, so it should be much faster than the
  top-level UART simulation.
- The existing cocotb test already contains most of the driver code.

Acceptance criteria:

- Running the backend produces a valid JPEG from `assets/sample_192x192.bmp`.
- It works without physical FPGA hardware.
- It returns the same `EncodeResult` shape as the hardware backend.

## Phase 5: Cocotb Full-UART Top Backend

Implement `CocotbUartTopBackend` as an optional slower mode.

Use `examples/cmoda7/tb/test_cmod_jpeg_top.py` as the base.

Backend behavior:

- Launch top-level cocotb simulation.
- Drive configuration over simulated UART using route byte `C`.
- Send image payload over simulated UART using route byte `D`.
- Capture JPEG bytes from simulated UART TX.
- Return normal `EncodeResult`.

Acceptance criteria:

- Validates the full UART mode switch and UART-to-AXI-lite path.
- UI clearly labels this mode as slow.
- It is not the default simulation backend.

## Phase 6: Bluesim/BDPI Backend

Implement this after the cocotb core backend unless Bluesim turns out to be
significantly easier to parameterize.

Create a dedicated `hdl/encoder/test/TestBlueJPEGDemo.bsv`.

Start from `hdl/encoder/test/TestBlueJPEG.bsv`, but make it dynamic:

- Accept input image path at runtime.
- Accept output JPEG path at runtime.
- Accept width and height at runtime if possible.
- Accept subsampling mode at runtime.
- Write a JSON stats file if practical.

Possible runtime configuration mechanisms:

- Bluesim plusargs.
- Environment-variable reads through a tiny new BDPI helper.
- A small text config file parsed by BDPI/C++ and exposed to BSV.

Preferred output artifacts:

```text
result.jpg
result.json
```

Suggested JSON fields:

```json
{
  "width": 192,
  "height": 192,
  "jpeg_bytes": 12345,
  "cycles": 123456,
  "pixels": 36864,
  "hw_output_bytes": 12345,
  "subsampling": "444"
}
```

Acceptance criteria:

- `BluesimBackend` can run from Python and return `EncodeResult`.
- It can encode at least the sample 192x192 image.
- It reports perf counters from `PERF0`, `PERF1`, and `PERF2`.

## Phase 7: Interactive App

Build a local Python web UI.

Recommended first implementation: Streamlit, because it is fast to build and
good enough for lab demos.

Potential later implementation: FastAPI plus a small frontend if more polish or
long-running job control is needed.

Main UI:

- Image picker/uploader.
- Backend selector:
  - Software/mock
  - cocotb core
  - cocotb top UART
  - Bluesim
  - hardware UART
- Port/baud controls for hardware backend.
- Subsampling selector: `4:4:4`, `4:2:2`, `4:2:0`.
- Encode button.
- Original image preview.
- FPGA/sim/software JPEG output preview.
- Statistics panel.
- Log panel.

Useful stats:

- Width and height.
- Raw input bytes.
- JPEG output bytes.
- Compression ratio.
- Bits per pixel.
- Host elapsed time.
- UART transfer time if available.
- Hardware cycles.
- Hardware pixels.
- Hardware output bytes.
- Cycles per pixel.
- Effective output throughput.
- JPEG marker validity.
- PSNR and optional SSIM.

Optional visual tabs:

- Difference heatmap.
- JPEG marker/segment summary.
- CSR/register panel.
- Pipeline overview:
  - Input pixels
  - YCbCr
  - MCU tiling
  - DCT
  - Quantize
  - RLE/Huffman
  - JPEG bytes

Acceptance criteria:

- App starts locally and can run a software/mock backend without hardware.
- App can display original and encoded image side by side.
- App can show metrics from any backend.
- App can call at least one simulation backend.

## Phase 8: CSR Editor UI

The CSR editor should be reusable and not tightly coupled to BlueJPEG.

It can start as either:

- a CLI/TUI under `tools/uart_axilite`, or
- a panel embedded in the Streamlit demo.

Expected features:

- List registers by name and address.
- Read one register.
- Dump all registers.
- Decode bitfields.
- Edit read-write fields.
- Poll selected fields.
- Show raw hex and decoded field values.
- Use the BlueJPEG register map as one selectable map.

Acceptance criteria:

- CSR editor can work independently of the JPEG demo.
- BlueJPEG demo can embed it or link to it.
- Future projects can add register maps without rewriting transport code.

## Testing Strategy

Unit tests:

- Image packing order.
- JPEG SOI/EOI and dimension parsing.
- Metric calculations.
- CSR field encode/decode.

Integration tests:

- Software/mock backend returns a valid `EncodeResult`.
- Cocotb core backend runs sample image and produces JPEG.
- Hardware backend can be smoke-tested manually with CMod A7.
- Bluesim backend runs sample image once dynamic harness exists.

Regression targets to preserve:

- Existing `examples/cmoda7/uart_axis.py` behavior.
- Existing cocotb tests.
- Existing Bluesim tests.

## Suggested Implementation Order

1. Add shared `image_utils.py`, `jpeg_utils.py`, and `metrics.py`.
2. Refactor `examples/cmoda7/uart_axis.py` to use the shared helpers.
3. Add reusable UART AXI-lite CSR library and BlueJPEG register map.
4. Implement `SoftwareBackend` and `MockReplayBackend`.
5. Implement `HardwareUartBackend`.
6. Implement `CocotbCoreBackend`.
7. Build initial Streamlit app.
8. Add CSR editor CLI.
9. Add `CocotbUartTopBackend`.
10. Add dynamic `BluesimBackend`.
11. Polish UI, stats, and docs.

## Non-Goals For The First Pass

- Do not build a complex frontend before the backend API is stable.
- Do not make UART the only simulation path.
- Do not force users to have hardware connected to use the demo.
- Do not hard-code the CSR editor to BlueJPEG.
- Do not rewrite the existing UART AXI-lite protocol helper unless necessary.

## Future Prompt For Codex

Use this prompt when resuming:

```text
Please implement the BlueJPEG interactive demo according to
docs/interactive_demo_plan.md. Start with Phase 1 and Phase 2 unless they are
already complete. Keep changes scoped, preserve existing hardware and cocotb
flows, and verify each phase with focused tests or smoke commands.
```

