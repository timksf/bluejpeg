#!/usr/bin/env python3
"""Reassemble BlueJPEG UDP packets and save only complete JPEG frames."""

import argparse
from dataclasses import dataclass, field
from pathlib import Path
import socket
import struct
import time


@dataclass
class Frame:
    chunks: dict = field(default_factory=dict)
    last_sequence: int | None = None
    updated: float = field(default_factory=time.monotonic)

    def add(self, sequence, last, payload):
        if sequence in self.chunks and self.chunks[sequence] != payload:
            raise ValueError('conflicting duplicate packet')
        if self.last_sequence is not None and (sequence > self.last_sequence or (last and sequence != self.last_sequence)):
            raise ValueError('inconsistent final packet')
        if last and any(index > sequence for index in self.chunks):
            raise ValueError('final packet precedes existing data')
        self.chunks[sequence] = payload
        if last:
            self.last_sequence = sequence
        self.updated = time.monotonic()

    def complete(self):
        return self.last_sequence is not None and len(self.chunks) == self.last_sequence + 1

    def jpeg(self):
        return b''.join(self.chunks[index] for index in range(self.last_sequence + 1))

    def loss(self):
        if not self.chunks:
            return 'all packets missing'
        end = self.last_sequence if self.last_sequence is not None else max(self.chunks, default=-1)
        missing = [index for index in range(end + 1) if index not in self.chunks]
        suffix = '' if self.last_sequence is not None else ', final packet missing'
        return f'{len(missing)} known missing packets{suffix}'


def parse_packet(packet):
    if len(packet) < 9:
        raise ValueError('short packet')
    magic, flags, frame, sequence, length = struct.unpack_from('!BBHHH', packet)
    if magic != 0x4a or flags & ~1 or not 1 <= length <= 1024 or len(packet) != length + 8:
        raise ValueError('invalid header or payload length')
    return frame, sequence, bool(flags & 1), packet[8:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=5001)
    parser.add_argument('--output', type=Path, default=Path('.'))
    parser.add_argument('--expect', type=Path)
    parser.add_argument('--count', type=int, default=0, help='complete frames to receive, zero means unlimited')
    parser.add_argument('--timeout', type=float, default=2, help='seconds before an incomplete frame is reported')
    parser.add_argument('--buffer', type=int, default=16 * 1024 * 1024)
    args = parser.parse_args()
    if args.count < 0 or args.timeout <= 0 or args.buffer < 1:
        parser.error('invalid count, timeout or buffer')
    expected = args.expect.read_bytes() if args.expect else None
    args.output.mkdir(parents=True, exist_ok=True)
    frames = {}
    completed = {}
    received = 0
    first = None
    latest_frame = None
    failed = False
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, args.buffer)
        udp.bind((args.bind, args.port))
        udp.settimeout(min(args.timeout, 0.25))
        print(f'Listening on {args.bind}:{args.port}, socket buffer {udp.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)}', flush=True)
        try:
            while not args.count or received < args.count:
                try:
                    packet, _peer = udp.recvfrom(65535)
                    frame_id, sequence, last, payload = parse_packet(packet)
                    now = time.monotonic()
                    if frame_id in completed and now - completed[frame_id] < args.timeout:
                        continue
                    if latest_frame is not None:
                        advance = (frame_id - latest_frame) & 0xffff
                        if 1 < advance < 0x8000:
                            if advance > 8:
                                print(f'Lost {advance - 1} whole frames after frame {latest_frame}', flush=True)
                                failed = True
                            else:
                                for gap in range(1, advance):
                                    missing_id = (latest_frame + gap) & 0xffff
                                    if missing_id not in completed:
                                        frames.setdefault(missing_id, Frame())
                        if 0 < advance < 0x8000:
                            latest_frame = frame_id
                    else:
                        latest_frame = frame_id
                    if frame_id not in frames and len(frames) >= 8:
                        oldest = min(frames, key=lambda key: frames[key].updated)
                        print(f'Lost frame {oldest}: {frames.pop(oldest).loss()}', flush=True)
                        failed = True
                    frame = frames.setdefault(frame_id, Frame())
                    frame.add(sequence, last, payload)
                    if frame.complete():
                        jpeg = frame.jpeg()
                        if jpeg[:2] != b'\xff\xd8' or jpeg[-2:] != b'\xff\xd9':
                            raise ValueError(f'frame {frame_id} lacks JPEG SOI or EOI')
                        if expected is not None and jpeg != expected:
                            raise ValueError(f'frame {frame_id} differs from --expect')
                        path = args.output / f'frame_{frame_id}.jpg'
                        path.write_bytes(jpeg)
                        received += 1
                        if first is None:
                            first = now
                        fps = (received - 1) / (now - first) if now > first else 0
                        print(f'{path}: {len(jpeg)} bytes, {len(frame.chunks)} packets, {fps:.2f} fps', flush=True)
                        del frames[frame_id]
                        completed[frame_id] = now
                except socket.timeout:
                    pass
                now = time.monotonic()
                for key in list(frames):
                    if now - frames[key].updated >= args.timeout:
                        print(f'Lost frame {key}: {frames.pop(key).loss()}', flush=True)
                        failed = True
                completed = {key: value for key, value in completed.items() if now - value < args.timeout}
        except KeyboardInterrupt:
            pass
        finally:
            for key, frame in frames.items():
                print(f'Lost frame {key}: {frame.loss()}', flush=True)
                failed = True
    if failed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
