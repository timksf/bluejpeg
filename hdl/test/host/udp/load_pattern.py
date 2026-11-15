#!/usr/bin/env python3
"""Preload a full-range FFmpeg testsrc2 sequence into separate FPGA DDR frames."""

import argparse
import json
from pathlib import Path
import socket
import struct
import subprocess
import time

from load_frame import OpenOcd, frame_checksums


def interleave_yuv444(raw, pixels):
    if len(raw) != pixels * 3:
        raise ValueError('incomplete planar YUV444 frame')
    packed = bytearray(len(raw))
    packed[0::3] = raw[:pixels]
    packed[1::3] = raw[pixels:2 * pixels]
    packed[2::3] = raw[2 * pixels:]
    return packed


def upload_frame(control, udp, pixels, base, fpga, gap_ms):
    expected = frame_checksums(pixels)
    control.write(0x10, base)
    for attempt in range(3):
        control.write(4, 4)
        started = time.monotonic()
        for offset in range(0, len(pixels), 1440):
            udp.sendto(struct.pack('!I', offset // 3) + pixels[offset:offset + 1440], (fpga, 5000))
            time.sleep(gap_ms / 1000)
        time.sleep(0.05)
        control.wait(8, 0x19, 0)
        control.write(4, 8)
        time.sleep(0.01)
        control.wait(8, 4, 4)
        actual = control.read(0x20), control.read(0x24)
        if actual == expected:
            return expected, time.monotonic() - started
        print(f'Checksum mismatch at base {base}, retrying at a slower pace', flush=True)
        gap_ms *= 2
    raise RuntimeError(f'pattern upload failed verification at base {base}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--width', type=int, default=1920)
    parser.add_argument('--height', type=int, default=1080)
    parser.add_argument('--frames', type=int, default=30)
    parser.add_argument('--rate', type=int, default=30)
    parser.add_argument('--base', type=lambda value: int(value, 0))
    parser.add_argument('--gap-ms', type=float, default=0.4)
    parser.add_argument('--fpga', default='192.168.178.250')
    parser.add_argument('--openocd-host', default='127.0.0.1')
    parser.add_argument('--tcl-port', type=int, default=6666)
    parser.add_argument('--output', type=Path, default=Path('/tmp/bluejpeg-pattern'))
    parser.add_argument('--input-yuv', type=Path, help='existing full-range planar YUV444 clip')
    args = parser.parse_args()
    pixels = args.width * args.height
    base = pixels if args.base is None else args.base
    if not 0 < args.width <= 1920 or args.height <= 0 or args.height > 65535 or args.width % 8 or args.height % 8:
        parser.error('dimensions must be supported positive multiples of eight')
    if args.frames < 2 or args.rate < 1 or args.gap_ms <= 0 or base < 0 or base + args.frames * pixels > 0x10000000:
        parser.error('invalid sequence dimensions, DDR range, rate or packet gap')
    args.output.mkdir(parents=True, exist_ok=True)
    raw_path = args.input_yuv or args.output / 'testsrc2.yuv'
    if args.input_yuv is None:
        subprocess.run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
            '-i', f'testsrc2=size={args.width}x{args.height}:rate={args.rate}',
            '-vf', "scale=in_range=tv:out_range=pc,format=yuv444p,drawtext=font=DejaVu Sans Mono:"
                   "text='FFmpeg source frame %{n}':fontcolor=white:fontsize=48:box=1:boxcolor=black@0.65:x=w-tw-32:y=32",
            '-frames:v', str(args.frames), '-pix_fmt', 'yuv444p', '-f', 'rawvideo', '-y', str(raw_path),
        ], check=True)
    if raw_path.stat().st_size != pixels * 3 * args.frames:
        raise ValueError('YUV clip size does not match the sequence dimensions')
    control = OpenOcd(args.openocd_host, args.tcl_port)
    entries = []
    try:
        if control.read(0) & 0xfff != 3 or control.read(0x4000) & 0xfff != 1:
            raise RuntimeError('unexpected FPGA module IDs')
        control.write(4, 0)
        control.wait(8, 0x19, 0)
        control.wait(8, 2, 2)
        control.write(0x0c, pixels)
        control.write(0x400c, args.height << 16 | args.width)
        with raw_path.open('rb') as source, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
            for index in range(args.frames):
                packed = interleave_yuv444(source.read(pixels * 3), pixels)
                address = base + index * pixels
                sums, elapsed = upload_frame(control, udp, packed, address, args.fpga, args.gap_ms)
                entries.append({'base': address, 'checksums': list(sums)})
                print(f'Verified FFmpeg frame {index + 1}/{args.frames} at word {address}, upload {elapsed:.3f}s', flush=True)
        manifest = {'width': args.width, 'height': args.height, 'source_rate': args.rate,
                    'source': 'FFmpeg testsrc2, full-range YUV444', 'frames': entries}
        manifest_path = args.output / 'sequence.json'
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        print(f'Ready for preview: {manifest_path}', flush=True)
    finally:
        control.write(4, 0)
        control.close()


if __name__ == '__main__':
    main()
