#!/usr/bin/env python3
"""Display the FPGA's repeating JPEG stream and stop repeat when the window closes."""

import argparse
import hashlib
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time

from load_frame import OpenOcd
from recv_jpeg import Frame, parse_packet


def schedule_sequence(bases, baseline, host, port, stop, errors):
    control = None
    previous = baseline
    try:
        control = OpenOcd(host, port)
        while not stop.is_set():
            completed = control.read(0x40)
            advance = (completed - previous) & 0xffffffff
            if advance > 1:
                raise RuntimeError('DDR sequence control missed a frame deadline')
            if advance:
                offset = (completed - baseline) & 0xffffffff
                control.write(0x10, bases[(offset + 1) % len(bases)])
                previous = completed
            stop.wait(0.001)
    except Exception as error:
        errors.append(error)
    finally:
        if control is not None:
            control.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=5001)
    parser.add_argument('--expect', type=Path)
    parser.add_argument('--sequence', type=Path, help='DDR sequence manifest from load_pattern.py')
    parser.add_argument('--no-overlay', action='store_true', help='show only the FPGA-encoded image')
    parser.add_argument('--snapshot', type=Path)
    parser.add_argument('--openocd-host', default='127.0.0.1')
    parser.add_argument('--tcl-port', type=int, default=6666)
    args = parser.parse_args()
    if args.expect and args.sequence:
        parser.error('--expect and --sequence are mutually exclusive')
    expected = args.expect.read_bytes() if args.expect else None
    sequence = json.loads(args.sequence.read_text()) if args.sequence else None
    bases = [entry['base'] for entry in sequence['frames']] if sequence else []
    if sequence:
        pixels = sequence['width'] * sequence['height']
        if len(bases) < 2 or any(base < 0 or base + pixels > 0x10000000 for base in bases):
            parser.error('invalid DDR sequence')
    sequence_hashes = {}
    frames = {}
    previous = None
    received = 0
    first = last_report = None
    player = None
    control = None
    repeat_started = False
    schedule_stop = threading.Event()
    schedule_errors = []
    scheduler = None
    with tempfile.TemporaryDirectory(prefix='bluejpeg-preview-') as overlay_dir, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        overlay = Path(overlay_dir) / 'status.txt'
        overlay.write_text('Waiting for FPGA frames\n')
        overlay_filter = (
            f'drawtext=textfile={overlay}:reload=1:expansion=none:'
            'font=DejaVu Sans Mono:fontsize=40:fontcolor=white:'
            'box=1:boxcolor=black@0.75:boxborderw=12:x=28:y=28'
        )
        udp.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
        udp.bind((args.bind, args.port))
        udp.settimeout(0.25)
        try:
            player_command = [
                'ffplay', '-loglevel', 'error', '-nostats', '-fflags', 'nobuffer',
                '-flags', 'low_delay', '-probesize', '32', '-analyzeduration', '0',
                '-f', 'mjpeg', '-framerate', '60', '-i', 'pipe:0',
                '-x', '1280', '-y', '720', '-autoexit',
                '-window_title', 'BlueJPEG 1920x1080 | encoder 200 MHz | UDP 125 MHz',
            ]
            if not args.no_overlay:
                player_command.extend(['-vf', overlay_filter])
            player = subprocess.Popen(player_command, stdin=subprocess.PIPE)
            control = OpenOcd(args.openocd_host, args.tcl_port)
            if control.read(0) & 0xfff != 3 or control.read(0x4000) & 0xfff != 1:
                raise RuntimeError('unexpected FPGA module IDs')
            control.write(0x2030, 0x3ff)
            control.write(0x2034, 0x1ff)
            if sequence:
                control.write(4, 0)
                control.wait(8, 0x19, 0)
                control.write(0x0c, pixels)
                control.write(0x400c, sequence['height'] << 16 | sequence['width'])
                control.write(0x10, bases[0])
                baseline = control.read(0x40)
                control.write(4, 1)
                repeat_started = True
                control.write(0x10, bases[1])
                control.write(4, 2)
                scheduler = threading.Thread(target=schedule_sequence,
                    args=(bases, baseline, args.openocd_host, args.tcl_port, schedule_stop, schedule_errors), daemon=True)
                scheduler.start()
            else:
                control.write(4, (control.read(4) & 4) | 2)
                repeat_started = True
            print('Live FPGA preview running, close the window to stop repeat', flush=True)
            while player.poll() is None:
                if schedule_errors:
                    raise schedule_errors[0]
                try:
                    packet, _peer = udp.recvfrom(65535)
                except socket.timeout:
                    if any(time.monotonic() - frame.updated > 2 for frame in frames.values()):
                        raise RuntimeError('incomplete FPGA frame timed out')
                    continue
                frame_id, sequence, final, payload = parse_packet(packet)
                frame = frames.setdefault(frame_id, Frame())
                frame.add(sequence, final, payload)
                if len(frames) > 8:
                    raise RuntimeError('too many incomplete FPGA frames')
                if not frame.complete():
                    continue
                jpeg = frame.jpeg()
                if jpeg[:2] != b'\xff\xd8' or jpeg[-2:] != b'\xff\xd9':
                    raise RuntimeError('invalid JPEG markers')
                if expected is not None and jpeg != expected:
                    raise RuntimeError(f'frame {frame_id} differs from reference')
                if previous is not None and frame_id != ((previous + 1) & 0xffff):
                    raise RuntimeError(f'frame gap after {previous}: got {frame_id}')
                if sequence:
                    source_index = received % len(bases)
                    digest = hashlib.sha256(jpeg).digest()
                    if source_index in sequence_hashes and digest != sequence_hashes[source_index]:
                        raise RuntimeError(f'FFmpeg source frame {source_index} changed across replay loops')
                    sequence_hashes[source_index] = digest
                    if len(sequence_hashes) == len(bases) and len(set(sequence_hashes.values())) != len(bases):
                        raise RuntimeError('DDR sequence contains repeated images instead of distinct source frames')
                previous = frame_id
                del frames[frame_id]
                now = time.monotonic()
                received += 1
                if first is None:
                    first = last_report = now
                    if args.snapshot:
                        args.snapshot.parent.mkdir(parents=True, exist_ok=True)
                        args.snapshot.write_bytes(jpeg)
                fps = (received - 1) / (now - first) if now > first else 0
                pending_overlay = overlay.with_suffix('.tmp')
                pending_overlay.write_text(f'FPGA frame {frame_id:05d}   received {received:,}\nReceive rate {fps:.2f} fps\n')
                pending_overlay.replace(overlay)
                if now - last_report >= 1:
                    verification = f'replay verified={len(sequence_hashes)}/{len(bases)}' if sequence else f'reference match={expected is not None}'
                    print(f'{received} frames, {fps:.3f} fps, {len(jpeg)} bytes, {verification}', flush=True)
                    last_report = now
                player.stdin.write(jpeg)
                player.stdin.flush()
        except (KeyboardInterrupt, BrokenPipeError):
            pass
        finally:
            schedule_stop.set()
            if scheduler is not None:
                scheduler.join(timeout=2)
            if control is not None:
                try:
                    if repeat_started:
                        control.write(4, control.read(4) & 4)
                        control.wait(8, 1, 0)
                        print(f'Preview stopped after {received} frames', flush=True)
                finally:
                    control.close()
            if player is not None:
                try:
                    player.stdin.close()
                except BrokenPipeError:
                    pass
                try:
                    player.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    player.terminate()
                    player.wait(timeout=2)


if __name__ == '__main__':
    main()
