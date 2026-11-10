#!/usr/bin/env python3
"""Capture one JPEG from the BlueJPEG PA200T test design's UART.

Reads from SOI (FF D8) to EOI (FF D9), writes the file and optionally compares it
with a reference, e.g. the simulation result build/TestJpegSystem/uart_capture.jpg:

    python3 capture_uart.py /dev/ttyUSB0 --out pa200t.jpg \
        --expect ../../build/TestJpegSystem/uart_capture.jpg

Start it before bluejpeg_jlink.tcl. Only the Python standard library is needed (Linux).
"""
import argparse
import os
import select
import sys
import termios
import time


def open_serial(port, baud):
    rate = getattr(termios, f"B{baud}", None)
    if rate is None:
        sys.exit(f"unsupported baud rate {baud}")
    fd = os.open(port, os.O_RDONLY | os.O_NOCTTY)
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0                                                   # iflag: raw input
    attrs[1] = 0                                                   # oflag
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL        # cflag: 8N1
    attrs[3] = 0                                                   # lflag: no echo, no canonical mode
    attrs[4] = rate
    attrs[5] = rate
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIFLUSH)
    return fd


def capture(fd, timeout):
    data = bytearray()
    started = False
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if not ready:
            continue
        chunk = os.read(fd, 4096)
        if not started:
            data += chunk
            soi = data.find(b"\xff\xd8")
            if soi < 0:
                data = data[-1:]
                continue
            data = data[soi:]
            started = True
            deadline = time.monotonic() + timeout
        else:
            data += chunk
        if started and data.endswith(b"\xff\xd9"):
            return bytes(data)
    sys.exit(f"timeout: {len(data)} bytes, {'no SOI' if not started else 'no EOI'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("port")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--out", default="pa200t.jpg")
    parser.add_argument("--expect", help="reference JPEG for a byte-for-byte comparison")
    parser.add_argument("--timeout", type=float, default=60.0, help="seconds to wait for SOI and between bytes")
    args = parser.parse_args()

    fd = open_serial(args.port, args.baud)
    print(f"waiting for a JPEG on {args.port} at {args.baud} baud")
    t0 = time.monotonic()
    jpeg = capture(fd, args.timeout)
    os.close(fd)
    with open(args.out, "wb") as f:
        f.write(jpeg)
    print(f"{len(jpeg)} bytes in {time.monotonic() - t0:.2f} s written to {args.out}")

    if args.expect:
        with open(args.expect, "rb") as f:
            ref = f.read()
        if jpeg == ref:
            print(f"matches {args.expect} ({len(ref)} bytes)")
            return
        first = next((i for i, (a, b) in enumerate(zip(jpeg, ref)) if a != b), min(len(jpeg), len(ref)))
        sys.exit(f"MISMATCH against {args.expect}: {len(jpeg)} vs {len(ref)} bytes, first difference at byte {first}")


if __name__ == "__main__":
    main()
