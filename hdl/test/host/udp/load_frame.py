#!/usr/bin/env python3
"""Load a BMP raster over UDP and verify the DDR frame over OpenOCD Tcl RPC."""

import argparse
from pathlib import Path
import socket
import struct
import time


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


COEFFICIENTS = ((0.299, 0.587, 0.114), (-0.168736, -0.331264, 0.5), (0.5, -0.418688, -0.081312))
PRODUCTS = tuple(tuple(tuple(f32(f32(c) * i) for i in range(256)) for c in row) for row in COEFFICIENTS)


def rgb_to_ycbcr(r, g, b):
    """Round every operation to float32, matching rgb2ycbcr_ref with no FMA."""
    result = []
    for channel, products in enumerate(PRODUCTS):
        value = f32(f32(products[0][r] + products[1][g]) + products[2][b])
        if channel:
            value = f32(value + 128.0)
        result.append(int(min(255.0, max(0.0, value))))
    return bytes(result)


def read_bmp(path, width=1920, height=1080):
    """Read an uncompressed 24-bit or 32-bit BMP and crop its top-left raster."""
    data = Path(path).read_bytes()
    if len(data) < 54 or data[:2] != b'BM':
        raise ValueError('expected a Windows BMP')
    offset = struct.unpack_from('<I', data, 10)[0]
    dib, source_width, source_height, planes, bits, compression = struct.unpack_from('<IiiHHI', data, 14)
    if dib < 40 or planes != 1 or compression != 0 or bits not in (24, 32):
        raise ValueError('expected an uncompressed 24-bit or 32-bit BMP')
    if width <= 0 or height <= 0 or source_width < width or abs(source_height) < height:
        raise ValueError('BMP is smaller than the requested crop')
    stride = ((source_width * bits + 31) // 32) * 4
    if offset < 14 + dib or offset + stride * abs(source_height) > len(data):
        raise ValueError('truncated BMP pixel data')
    rgb = bytearray()
    for y in range(height):
        source_y = abs(source_height) - y - 1 if source_height > 0 else y
        row = offset + source_y * stride
        for x in range(width):
            b, g, r = data[row + x * (bits // 8):row + x * (bits // 8) + 3]
            rgb.extend((r, g, b))
    return bytes(rgb)


def write_bmp(path, rgb, width, height):
    stride = (width * 3 + 3) & ~3
    header = struct.pack('<2sIHHI', b'BM', 54 + stride * height, 0, 0, 54)
    header += struct.pack('<IiiHHIIiiII', 40, width, height, 1, 24, 0, stride * height, 2835, 2835, 0, 0)
    with Path(path).open('wb') as output:
        output.write(header)
        for y in reversed(range(height)):
            row = rgb[y * width * 3:(y + 1) * width * 3]
            bgr = bytearray(row)
            bgr[0::3], bgr[2::3] = row[2::3], row[0::3]
            output.write(bgr)
            output.write(bytes(stride - width * 3))


def frame_checksums(pixels):
    sum1 = sum2 = 0
    for index in range(0, len(pixels), 3):
        word = int.from_bytes(pixels[index:index + 3], 'big')
        sum1 = (sum1 + word) & 0xffffffff
        sum2 = (sum2 + sum1) & 0xffffffff
    return sum1, sum2


class OpenOcd:
    def __init__(self, host='127.0.0.1', port=6666, tap='pa200t.tap'):
        if tap != 'pa200t.tap':
            raise ValueError('expected pa200t.tap')
        self.tap = tap
        self.socket = socket.create_connection((host, port), timeout=10)

    def command(self, command):
        self.socket.sendall(command.encode('ascii') + b'\x1a')
        response = bytearray()
        while not response.endswith(b'\x1a'):
            block = self.socket.recv(4096)
            if not block:
                raise ConnectionError('OpenOCD closed the Tcl connection')
            response.extend(block)
        return response[:-1].decode('utf-8').strip()

    def read(self, address):
        result = self.command(f'bluej_bus_access {self.tap} 0x3 0 {address} 0')
        try:
            return int(result, 0)
        except ValueError as exc:
            raise RuntimeError(f'OpenOCD read failed: {result}') from exc

    def write(self, address, value):
        result = self.command(f'bluej_bus_access {self.tap} 0x3 1 {address} {value & 0xffffffff}')
        if result != '0':
            raise RuntimeError(f'OpenOCD write failed: {result}')

    def wait(self, address, mask, expected, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = self.read(address)
            if value & 0x20 and address == 8:
                raise RuntimeError('frame store AXI error')
            if value & mask == expected:
                return value
            time.sleep(0.01)
        raise TimeoutError(f'register 0x{address:x} did not reach 0x{expected:x}')

    def close(self):
        self.socket.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bmp', type=Path)
    parser.add_argument('--fpga', default='192.168.178.250')
    parser.add_argument('--port', type=int, default=5000)
    parser.add_argument('--width', type=int, default=1920)
    parser.add_argument('--height', type=int, default=1080)
    parser.add_argument('--base', type=lambda value: int(value, 0), default=0)
    parser.add_argument('--gap-ms', type=float, default=1)
    parser.add_argument('--attempts', type=int, default=3)
    parser.add_argument('--openocd-host', default='127.0.0.1')
    parser.add_argument('--tcl-port', type=int, default=6666)
    parser.add_argument('--write-crop', type=Path)
    parser.add_argument('--prepare-only', action='store_true', help='convert and print checksums without network or JTAG access')
    args = parser.parse_args()
    if args.width <= 0 or args.width > 1920 or args.height <= 0 or args.height > 65535 or args.width % 8 or args.height % 8:
        parser.error('dimensions must be positive multiples of eight within encoder limits')
    if args.base < 0 or args.base + args.width * args.height > 1 << 28 or args.gap_ms < 0 or args.attempts < 1:
        parser.error('invalid base, gap or attempt count')
    rgb = read_bmp(args.bmp, args.width, args.height)
    if args.write_crop:
        write_bmp(args.write_crop, rgb, args.width, args.height)
    pixels = bytearray()
    for index in range(0, len(rgb), 3):
        pixels.extend(rgb_to_ycbcr(*rgb[index:index + 3]))
    expected = frame_checksums(pixels)
    print(f'{args.width}x{args.height}, CHK1={expected[0]:08x}, CHK2={expected[1]:08x}', flush=True)
    if args.prepare_only:
        return
    control = OpenOcd(args.openocd_host, args.tcl_port)
    try:
        if control.read(0) & 0xfff != 3 or control.read(0x4000) & 0xfff != 1:
            raise RuntimeError('unexpected FPGA module IDs')
        control.wait(8, 2, 2)
        control.write(4, 0)
        control.wait(8, 0x19, 0)
        control.write(0x10, args.base)
        control.write(0x0c, args.width * args.height)
        control.wait(0x4008, 1, 1)
        control.write(0x400c, args.height << 16 | args.width)
        control.write(0x401c, 1)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
            for attempt in range(args.attempts):
                control.write(4, 4)
                for offset in range(0, len(pixels), 480 * 3):
                    udp.sendto(struct.pack('!I', offset // 3) + pixels[offset:offset + 480 * 3], (args.fpga, args.port))
                    time.sleep(args.gap_ms / 1000)
                time.sleep(0.05)
                control.wait(8, 0x19, 0)
                control.write(4, 8)
                time.sleep(0.01)
                control.wait(8, 4, 4)
                actual = control.read(0x20), control.read(0x24)
                if actual == expected:
                    print(f'Verified frame in DDR after attempt {attempt + 1}')
                    return
                print(f'Checksum mismatch {actual}, resending frame', flush=True)
        raise RuntimeError('frame verification failed after all attempts')
    finally:
        control.close()


if __name__ == '__main__':
    main()
