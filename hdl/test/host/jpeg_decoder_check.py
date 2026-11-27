#!/usr/bin/env python3
"""Inputs and checks for the TbJpegDecoder* Bluesim tests.

    jpeg_decoder_check.py gen   <simdir> [--profile color|look|blocks|gray]  write the test inputs
    jpeg_decoder_check.py check <simdir> [--order raster|blocks]             compare dec_out_<i>.raw against libjpeg

Input i is one of three files, see TbJpegDecoder.bsv:

    dec_in_<i>.jpg    a valid frame, its output is compared against libjpeg
    dec_bad_<i>.jpg   damaged entropy-coded data, the output must have the full frame size
    dec_skip_<i>.jpg  a frame the decoder rejects, no output may exist

The decoder emits YCbCr pixels (three bytes each) in raster order, or in 8x8
block order without the untiler. The reference is libjpeg (through Pillow)
with colour conversion disabled, grayscale streams get neutral chroma.

The decoder upsamples 4:2:2 and 4:2:0 chroma by replication, libjpeg by its
fancy (triangle) filter. For those frames the luma is compared directly, the
chroma output must be an exact replication of one sample per 2x1 or 2x2
group, and those native samples run through libjpeg's filter must match
libjpeg's chroma.
"""

import argparse
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HDL_DIR = Path(__file__).resolve().parents[2]
ASSETS = HDL_DIR.parent / "assets"
HW_JPEG = HDL_DIR / "build" / "board_udp_bram" / "frame_0.jpg"

#largest per-sample difference to libjpeg islow that still passes
MAX_ABS_DIFF = 2

SUB = {"444": 0, "422": 1, "420": 2}


def encode(img: Image.Image, **kw) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "JPEG", **kw)
    return buf.getvalue()


def segments(data: bytes):
    """(marker, start, end) of each header segment up to and including SOS, end is past the payload."""
    pos = data.index(b"\xff\xd8") + 2
    while pos < len(data):
        while data[pos] == 0xFF and data[pos + 1] == 0xFF:
            pos += 1
        marker = data[pos + 1]
        length = int.from_bytes(data[pos + 2:pos + 4], "big")
        yield marker, pos, pos + 2 + length
        if marker == 0xDA:
            return
        pos += 2 + length


def ecs_range(data: bytes) -> tuple:
    sos_end = [end for marker, _, end in segments(data) if marker == 0xDA][0]
    return sos_end, data.rindex(b"\xff\xd9")


def camera_like(data: bytes) -> bytes:
    """OmniVision-like framing: junk before SOI, no APP0, zero padding after EOI."""
    app0 = [(start, end) for marker, start, end in segments(data) if marker == 0xE0]
    for start, end in reversed(app0):
        data = data[:start] + data[end:]
    return b"\x00\x12\x34\x00\xfe" + data + b"\x00" * 7


def corrupt(data: bytes) -> bytes:
    """Sixteen one bits match no Huffman code, so decoding fails there."""
    start, end = ecs_range(data)
    cut = start + int((end - start) * 0.4)
    while data[cut - 1] == 0xFF:
        cut += 1
    return data[:cut] + b"\xff\x00" * 4 + data[cut:]


def truncate(data: bytes) -> bytes:
    """Entropy-coded data cut short without EOI, the next frame's SOI ends it."""
    start, end = ecs_range(data)
    cut = start + int((end - start) * 0.6)
    while data[cut - 1] == 0xFF:
        cut -= 1
    return data[:cut]


def with_dri(data: bytes) -> bytes:
    """A restart interval, which the decoder rejects."""
    sos = [start for marker, start, _ in segments(data) if marker == 0xDA][0]
    return data[:sos] + b"\xff\xdd\x00\x04\x00\x10" + data[sos:]


def gen(simdir: Path, profile: str) -> None:
    src = Image.open(ASSETS / "sample_192x192.bmp").convert("RGB")
    wide = src.resize((250, 37))
    crop = src.crop((13, 7, 113, 82))
    small = src.resize((64, 48))
    gray = src.convert("L")

    def jpg(img, sub=None, **kw):
        if sub is not None:
            kw["subsampling"] = SUB[sub]
        return encode(img, **kw)

    #the first inputs match the earlier profiles, so their cycle counts stay comparable
    base = [
        ("in", jpg(src, "444", quality=90)),
        ("in", jpg(gray, quality=75)),
        ("in", jpg(crop, "444", quality=50, optimize=True)),
        ("in", jpg(small, "444", quality=100)),
        ("in", jpg(wide, "444", quality=85)),
        ("in", HW_JPEG.read_bytes() if HW_JPEG.exists() else None),
    ]
    if profile == "color":
        cases = base + [
            ("in", jpg(src, "422", quality=90)),
            ("in", jpg(src, "420", quality=90)),
            ("in", jpg(crop, "422", quality=50, optimize=True)),
            ("in", jpg(wide, "420", quality=85)),
            ("in", jpg(small, "420", quality=100)),
            ("in", camera_like(jpg(src, "422", quality=80))),
            ("bad", corrupt(jpg(src, "422", quality=90))),
            ("in", jpg(src, "422", quality=75)),
            ("bad", truncate(jpg(src, "444", quality=90))),
            ("in", jpg(crop, "420", quality=70)),
            ("skip", jpg(src, "444", quality=90, progressive=True)),
            ("in", jpg(gray, quality=60)),
            ("skip", with_dri(jpg(src, "444", quality=90))),
            ("in", jpg(wide, "422", quality=85)),
        ]
    elif profile == "look":
        cases = base + [
            ("in", jpg(src, "422", quality=90)),
            ("in", jpg(crop, "422", quality=50, optimize=True)),
            ("in", camera_like(jpg(src, "422", quality=80))),
            ("skip", jpg(src, "420", quality=90)),
            ("in", jpg(src, "422", quality=75)),
            ("bad", corrupt(jpg(src, "422", quality=90))),
            ("in", jpg(crop, "444", quality=70)),
        ]
    elif profile == "blocks":
        cases = base + [
            ("skip", jpg(src, "422", quality=90)),
            ("in", jpg(crop, "444", quality=70)),
        ]
    else:
        cases = [
            ("in", jpg(gray, quality=75)),
            ("in", jpg(crop.convert("L"), quality=50, optimize=True)),
            ("in", jpg(small.convert("L"), quality=100)),
            ("in", jpg(wide.convert("L"), quality=85)),
            ("skip", jpg(src, "444", quality=90)),
            ("in", jpg(gray, quality=60)),
            ("bad", truncate(jpg(gray, quality=90))),
            ("in", jpg(wide.convert("L"), quality=70)),
        ]
    simdir.mkdir(parents=True, exist_ok=True)
    for old in simdir.glob("dec_*_*.*"):
        old.unlink()
    for i, (kind, data) in enumerate(cases):
        if data is not None:
            (simdir / f"dec_{kind}_{i}.jpg").write_bytes(data)
    print(f"wrote {profile} test inputs to {simdir}")


def from_raster(raw: bytes, w: int, h: int) -> np.ndarray:
    px = np.frombuffer(raw, dtype=np.uint8)
    if px.size != w * h * 3:
        raise ValueError(f"got {px.size // 3} pixels, expected {w * h}")
    return px.reshape(h, w, 3)


def from_blocks(raw: bytes, w: int, h: int) -> np.ndarray:
    bw, bh = (w + 7) // 8, (h + 7) // 8
    px = np.frombuffer(raw, dtype=np.uint8)
    if px.size != bw * bh * 64 * 3:
        raise ValueError(f"got {px.size // 3} pixels, expected {bw * bh * 64}")
    img = px.reshape(bh, bw, 8, 8, 3).transpose(0, 2, 1, 3, 4).reshape(bh * 8, bw * 8, 3)
    return img[:h, :w, :]


def fancy_h2v1(c: np.ndarray) -> np.ndarray:
    """libjpeg h2v1_fancy_upsample on native chroma rows."""
    if c.shape[1] == 1:
        return np.repeat(c, 2, axis=1)
    left = np.concatenate([c[:, :1], c[:, :-1]], axis=1)
    right = np.concatenate([c[:, 1:], c[:, -1:]], axis=1)
    even = (3 * c + left + 1) >> 2
    odd = (3 * c + right + 2) >> 2
    even[:, 0] = c[:, 0]
    odd[:, -1] = c[:, -1]
    return np.stack([even, odd], axis=2).reshape(c.shape[0], -1)


def fancy_h2v2(c: np.ndarray) -> np.ndarray:
    """libjpeg h2v2_fancy_upsample on native chroma, edge rows replicated."""
    above = np.concatenate([c[:1], c[:-1]], axis=0)
    below = np.concatenate([c[1:], c[-1:]], axis=0)
    rows = []
    for cs in (3 * c + above, 3 * c + below):
        if cs.shape[1] == 1:
            rows.append(np.repeat((4 * cs + 8) >> 4, 2, axis=1))
            continue
        left = np.concatenate([cs[:, :1], cs[:, :-1]], axis=1)
        right = np.concatenate([cs[:, 1:], cs[:, -1:]], axis=1)
        even = (3 * cs + left + 8) >> 4
        odd = (3 * cs + right + 7) >> 4
        even[:, 0] = (4 * cs[:, 0] + 8) >> 4
        odd[:, -1] = (4 * cs[:, -1] + 7) >> 4
        rows.append(np.stack([even, odd], axis=2).reshape(cs.shape[0], -1))
    return np.stack(rows, axis=1).reshape(2 * c.shape[0], -1)


def compare(jpg: Path, dut_raw: bytes, order: str) -> tuple:
    data = jpg.read_bytes()
    ref = Image.open(io.BytesIO(data[data.index(b"\xff\xd8"):]))
    ncomp = 1 if ref.mode == "L" else 3
    hs = max(l[1] for l in ref.layer) if ncomp == 3 else 1
    vs = max(l[2] for l in ref.layer) if ncomp == 3 else 1
    if ncomp == 3:
        ref.draft("YCbCr", ref.size)
    w, h = ref.size
    ref = np.asarray(ref).reshape(h, w, ncomp).astype(int)
    if ncomp == 1:
        ref = np.concatenate([ref, np.full((h, w, 2), 128)], axis=2)
    unpack = from_raster if order == "raster" else from_blocks
    dut = unpack(dut_raw, w, h).astype(int)
    desc = f"{w}x{h}x{ncomp} {'gray' if ncomp == 1 else {(1, 1): '4:4:4', (2, 1): '4:2:2', (2, 2): '4:2:0'}[(hs, vs)]}"
    if hs == 1 and vs == 1:
        diff = np.abs(dut - ref)
        return diff, desc, ""
    native = dut[0::vs, 0::hs, 1:]
    replicated = np.repeat(np.repeat(native, vs, axis=0), hs, axis=1)[:h, :w]
    if not np.array_equal(replicated, dut[:, :, 1:]):
        raise ValueError("chroma is not a replication of one sample per group")
    up = fancy_h2v1 if vs == 1 else fancy_h2v2
    fancy = np.stack([up(native[:, :, k]) for k in range(2)], axis=2)[:h, :w]
    d_fancy = np.abs(fancy - ref[:, :, 1:])
    d_repl = np.abs(dut[:, :, 1:] - ref[:, :, 1:])
    d_chroma, how = (d_fancy, "fancy") if d_fancy.max() <= d_repl.max() else (d_repl, "replicated")
    diff = np.concatenate([np.abs(dut[:, :, :1] - ref[:, :, :1]), d_chroma], axis=2)
    return diff, desc, f" chroma vs libjpeg {how}"


def check(simdir: Path, order: str) -> int:
    failures = 0
    found = 0
    inputs = sorted(simdir.glob("dec_*_*.jpg"), key=lambda p: int(p.stem.split("_")[-1]))
    for jpg in inputs:
        kind, idx = jpg.stem.split("_")[1], jpg.stem.split("_")[-1]
        out = simdir / f"dec_out_{idx}.raw"
        if kind == "skip":
            ok = not out.exists()
            failures += not ok
            print(f"{jpg.name}: rejected, {'no output ok' if ok else 'unexpected output FAIL'}")
            continue
        if not out.exists():
            print(f"{jpg.name}: no decoder output FAIL")
            failures += 1
            continue
        found += 1
        if kind == "bad":
            w, h = Image.open(jpg).size
            n = len(out.read_bytes()) // 3
            exp = w * h if order == "raster" else ((w + 7) // 8) * ((h + 7) // 8) * 64
            ok = n == exp
            failures += not ok
            print(f"{jpg.name}: concealed, {n} pixels of {exp} {'ok' if ok else 'FAIL'}")
            continue
        try:
            diff, desc, note = compare(jpg, out.read_bytes(), order)
        except ValueError as e:
            print(f"{jpg.name}: {e} FAIL")
            failures += 1
            continue
        ok = diff.max() <= MAX_ABS_DIFF
        failures += not ok
        print(f"{jpg.name}: {desc} max|diff| {diff.max()} "
              f"mean {diff.mean():.4f} exact {np.mean(diff == 0) * 100:.1f}%{note} {'ok' if ok else 'FAIL'}")
    if found == 0:
        print("no outputs to check")
        return 1
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["gen", "check"])
    ap.add_argument("simdir", type=Path, nargs="?", default=HDL_DIR / "build" / "TbJpegDecoder")
    ap.add_argument("--profile", choices=["color", "look", "blocks", "gray"], default="color")
    ap.add_argument("--order", choices=["raster", "blocks"], default="raster")
    args = ap.parse_args()
    if args.cmd == "gen":
        gen(args.simdir, args.profile)
        return 0
    return check(args.simdir, args.order)


if __name__ == "__main__":
    sys.exit(main())
