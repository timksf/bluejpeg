#!/usr/bin/env python3

import argparse
import struct
import threading
import time
from pathlib import Path

import serial
from PIL import Image


DEFAULT_PORT = "/dev/ttyUSB1"
DEFAULT_BAUDRATE = 1_000_000
DEFAULT_UART_TIMEOUT_S = 0.1
DEFAULT_RESULT_TIMEOUT_S = 30.0
DEFAULT_MAX_JPEG_BYTES = 512 * 1024
DEFAULT_CHUNK_SIZE = 4096
DEFAULT_CHUNK_DELAY_S = 0.0
EOI_MARKER = b"\xff\xd9"


def rgb_to_ycbcr(red: int, green: int, blue: int) -> tuple[int, int, int]:
    y = 0.299 * red + 0.587 * green + 0.114 * blue
    cb = -0.168736 * red - 0.331264 * green + 0.5 * blue + 128.0
    cr = 0.5 * red - 0.418688 * green - 0.081312 * blue + 128.0

    def clamp(channel: float) -> int:
        return int(max(0.0, min(255.0, channel)))

    return clamp(y), clamp(cb), clamp(cr)


def pack_ycbcr_pixels(image_path: Path) -> bytes:
    image = Image.open(image_path).convert("RGB")
    payload = bytearray()

    for red, green, blue in image.getdata():
        y, cb, cr = rgb_to_ycbcr(red, green, blue)
        payload.extend((cr, cb, y))

    return bytes(payload)


def parse_jpeg_dimensions(payload: bytes) -> tuple[int, int]:
    if len(payload) < 4 or payload[:2] != b"\xff\xd8":
        raise ValueError("JPEG output is missing the SOI marker")
    if payload[-2:] != EOI_MARKER:
        raise ValueError("JPEG output is missing the EOI marker")

    sof_markers = {
        0xC0,
        0xC1,
        0xC2,
        0xC3,
        0xC5,
        0xC6,
        0xC7,
        0xC9,
        0xCA,
        0xCB,
        0xCD,
        0xCE,
        0xCF,
    }

    index = 2
    while index < len(payload):
        if payload[index] != 0xFF:
            index += 1
            continue

        while index < len(payload) and payload[index] == 0xFF:
            index += 1
        if index >= len(payload):
            break

        marker = payload[index]
        index += 1

        if marker == 0xD9:
            break
        if marker == 0xD8 or marker == 0x01 or 0xD0 <= marker <= 0xD7:
            continue

        if index + 2 > len(payload):
            break

        segment_length = struct.unpack_from(">H", payload, index)[0]
        if segment_length < 2 or index + segment_length > len(payload):
            raise ValueError("JPEG output contains an invalid segment length")

        if marker in sof_markers:
            height = struct.unpack_from(">H", payload, index + 3)[0]
            width = struct.unpack_from(">H", payload, index + 5)[0]
            return width, height

        index += segment_length

    raise ValueError("JPEG output is missing a start-of-frame marker")


def build_command(image_path: Path) -> tuple[bytes, int]:
    payload = pack_ycbcr_pixels(image_path)
    command = bytes([ord("S")]) + len(payload).to_bytes(4, "little") + payload
    return command, len(payload)


def send_command(uart: serial.Serial, command: bytes, chunk_size: int, chunk_delay: float) -> None:
    total_written = 0

    while total_written < len(command):
        next_offset = min(total_written + chunk_size, len(command))
        written = uart.write(command[total_written:next_offset])
        if written <= 0:
            raise TimeoutError("UART write stalled before the image command completed")
        total_written += written
        if total_written % DEFAULT_CHUNK_SIZE == 0 or total_written == len(command):
            print(f"Sent {total_written}/{len(command)} UART bytes")
        if chunk_delay > 0.0 and total_written < len(command):
            time.sleep(chunk_delay)

    uart.flush()


def receive_jpeg(
    uart: serial.Serial,
    output_path: Path,
    max_bytes: int,
    done_event: threading.Event,
    result_holder: list[bytes],
    error_holder: list[BaseException],
) -> None:
    payload = bytearray()
    tail = b""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        with output_path.open("wb") as output_file:
            while not done_event.is_set():
                chunk = uart.read(uart.in_waiting or 1)
                if not chunk:
                    continue

                combined = tail + chunk
                marker_index = combined.find(EOI_MARKER)

                if marker_index == -1:
                    output_file.write(chunk)
                    output_file.flush()
                    payload.extend(chunk)
                    if len(payload) > max_bytes:
                        raise TimeoutError("Received more JPEG data than the configured limit")
                    if len(payload) % DEFAULT_CHUNK_SIZE == 0:
                        print(f"Received {len(payload)} JPEG bytes")
                    tail = combined[-(len(EOI_MARKER) - 1):] if len(EOI_MARKER) > 1 else b""
                    continue

                keep_from_chunk = marker_index + len(EOI_MARKER) - len(tail)
                final_chunk = chunk[:keep_from_chunk]
                output_file.write(final_chunk)
                output_file.flush()
                payload.extend(final_chunk)

                if len(payload) > max_bytes:
                    raise TimeoutError("Received more JPEG data than the configured limit")

                result_holder.append(bytes(payload))
                done_event.set()
                return
    except BaseException as exc:
        error_holder.append(exc)
        done_event.set()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send an RGB image over UART to the CMOD JPEG encoder and capture the JPEG output."
    )
    parser.add_argument("image", type=Path, help="Input image path")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Output JPEG path (defaults to the input stem with .jpg)",
    )
    parser.add_argument("--port", default=DEFAULT_PORT, help="UART device path")
    parser.add_argument("--baudrate", type=int, default=DEFAULT_BAUDRATE, help="UART baud rate")
    parser.add_argument(
        "--uart-timeout",
        type=float,
        default=DEFAULT_UART_TIMEOUT_S,
        help="Per-read UART timeout in seconds",
    )
    parser.add_argument(
        "--result-timeout",
        type=float,
        default=DEFAULT_RESULT_TIMEOUT_S,
        help="Maximum time to wait for the JPEG EOI marker",
    )
    parser.add_argument(
        "--max-jpeg-bytes",
        type=int,
        default=DEFAULT_MAX_JPEG_BYTES,
        help="Abort if more than this many JPEG bytes are received",
    )
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=DEFAULT_CHUNK_SIZE,
        help="UART write chunk size in bytes",
    )
    parser.add_argument(
        "--chunk-delay",
        type=float,
        default=DEFAULT_CHUNK_DELAY_S,
        help="Delay in seconds after each UART write chunk",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    image_path = args.image.resolve()
    if not image_path.is_file():
        raise FileNotFoundError(f"Input image does not exist: {image_path}")

    output_path = args.output.resolve() if args.output else image_path.with_suffix(".jpg")
    command, payload_length = build_command(image_path)

    print(f"Opening {args.port} at {args.baudrate} baud")
    print(f"Input image: {image_path}")
    print(f"Output JPEG: {output_path}")
    print(f"Packed payload size: {payload_length} bytes")

    done_event = threading.Event()
    result_holder: list[bytes] = []
    error_holder: list[BaseException] = []

    with serial.Serial(
        port=args.port,
        baudrate=args.baudrate,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=args.uart_timeout,
        write_timeout=args.result_timeout,
    ) as uart:
        uart.reset_input_buffer()
        uart.reset_output_buffer()

        receiver = threading.Thread(
            target=receive_jpeg,
            args=(uart, output_path, args.max_jpeg_bytes, done_event, result_holder, error_holder),
            daemon=True,
        )
        receiver.start()

        try:
            send_command(uart, command, args.chunk_size, args.chunk_delay)

            if not done_event.wait(args.result_timeout):
                done_event.set()
                raise TimeoutError("Timed out waiting for the JPEG EOI marker over UART")
        finally:
            receiver.join(timeout=args.uart_timeout * 2 + 1.0)

    if error_holder:
        raise error_holder[0]
    if not result_holder:
        raise RuntimeError("UART receiver finished without capturing a JPEG")

    jpeg_bytes = result_holder[0]
    jpeg_width, jpeg_height = parse_jpeg_dimensions(jpeg_bytes)
    print(f"Received {len(jpeg_bytes)} JPEG bytes ({jpeg_width}x{jpeg_height})")
    print(f"Wrote JPEG to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
