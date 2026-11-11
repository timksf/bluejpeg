import ctypes
from pathlib import Path
import random
import struct
import subprocess
import tempfile
import unittest

import load_frame
import recv_jpeg


class HostProtocolTests(unittest.TestCase):
    def test_reference_conversion(self):
        reference = Path(__file__).resolve().parents[2] / 'bdpi' / 'RGB2YCbCr.cpp'
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / 'reference.so'
            subprocess.run(['c++', '-std=c++17', '-shared', '-fPIC', str(reference), '-o', str(library)], check=True)
            convert = ctypes.CDLL(str(library)).rgb2ycbcr_ref
            convert.argtypes = [ctypes.c_uint8] * 3
            convert.restype = ctypes.c_uint32
            rng = random.Random(1080)
            samples = [(i, i, i) for i in range(256)]
            samples += [(r, g, b) for r in (0, 1, 127, 128, 254, 255) for g in (0, 1, 127, 128, 254, 255) for b in (0, 1, 127, 128, 254, 255)]
            samples += [tuple(rng.randrange(256) for _ in range(3)) for _ in range(10000)]
            for rgb in samples:
                self.assertEqual(load_frame.rgb_to_ycbcr(*rgb), convert(*rgb).to_bytes(3, 'big'), rgb)

    def test_bmp_roundtrip_and_crop(self):
        rgb = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255, 1, 2, 3, 4, 5, 6])
        with tempfile.TemporaryDirectory() as directory:
            bmp = Path(directory) / 'image.bmp'
            load_frame.write_bmp(bmp, rgb, 3, 2)
            self.assertEqual(load_frame.read_bmp(bmp, 3, 2), rgb)
            self.assertEqual(load_frame.read_bmp(bmp, 2, 1), rgb[:6])
            data = bytearray(bmp.read_bytes())
            struct.pack_into('<i', data, 22, -2)
            data[54:66], data[66:78] = data[66:78], data[54:66]
            bmp.write_bytes(data)
            self.assertEqual(load_frame.read_bmp(bmp, 3, 2), rgb)
            bmp.write_bytes(data[:-1])
            with self.assertRaises(ValueError):
                load_frame.read_bmp(bmp, 3, 2)

    def test_wrapping_checksums(self):
        words = [0xffffff, 0x123456, 0, 0xffffff] * 1000
        pixels = b''.join(word.to_bytes(3, 'big') for word in words)
        first = sum(words) & 0xffffffff
        second = sum((len(words) - i) * word for i, word in enumerate(words)) & 0xffffffff
        self.assertEqual(load_frame.frame_checksums(pixels), (first, second))

    def test_reordered_duplicate_packets(self):
        frame = recv_jpeg.Frame()
        frame.add(2, True, b'ghi')
        frame.add(0, False, b'abc')
        self.assertFalse(frame.complete())
        self.assertIn('1 known missing', frame.loss())
        frame.add(0, False, b'abc')
        frame.add(1, False, b'def')
        self.assertTrue(frame.complete())
        self.assertEqual(frame.jpeg(), b'abcdefghi')
        with self.assertRaises(ValueError):
            frame.add(0, False, b'xyz')
        with self.assertRaises(ValueError):
            frame.add(3, True, b'jkl')

    def test_packet_validation(self):
        packet = struct.pack('!BBHHH', 0x4a, 1, 0xffff, 12, 3) + b'abc'
        self.assertEqual(recv_jpeg.parse_packet(packet), (0xffff, 12, True, b'abc'))
        for invalid in (packet[:-1], b'', bytes([0]) + packet[1:], packet[:1] + bytes([2]) + packet[2:]):
            with self.assertRaises(ValueError):
                recv_jpeg.parse_packet(invalid)


if __name__ == '__main__':
    unittest.main()
