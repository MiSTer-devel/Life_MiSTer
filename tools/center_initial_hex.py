#!/usr/bin/env python3

import argparse
from pathlib import Path


BOARD_WIDTH = 2200
ACTIVE_WIDTH = 1920
ACTIVE_HEIGHT = 1080
RECORD_SIZE = 16


def parse_ihex(path):
    mem = []
    upper = 0

    for raw in Path(path).read_text().splitlines():
        line = raw.strip()
        if not line:
            continue
        if line[0] != ":":
            raise ValueError(f"Invalid Intel HEX record: {line!r}")

        count = int(line[1:3], 16)
        addr = int(line[3:7], 16)
        record_type = int(line[7:9], 16)
        data = line[9 : 9 + count * 2]

        if record_type == 0:
            full_addr = (upper << 16) + addr
            if len(mem) < full_addr + count:
                mem.extend([0] * (full_addr + count - len(mem)))
            for i in range(count):
                mem[full_addr + i] = 0xFF if int(data[i * 2 : i * 2 + 2], 16) else 0x00
        elif record_type == 4:
            upper = int(data, 16)
        elif record_type == 1:
            break
        else:
            raise ValueError(f"Unsupported Intel HEX record type {record_type}")

    return mem


def checksum(byte_values):
    return (-sum(byte_values)) & 0xFF


def data_record(addr, data):
    body = [len(data), (addr >> 8) & 0xFF, addr & 0xFF, 0x00] + data
    return ":" + "".join(f"{b:02X}" for b in body) + f"{checksum(body):02X}"


def upper_record(upper):
    body = [0x02, 0x00, 0x00, 0x04, (upper >> 8) & 0xFF, upper & 0xFF]
    return ":" + "".join(f"{b:02X}" for b in body) + f"{checksum(body):02X}"


def write_ihex(path, mem):
    lines = []
    current_upper = None

    for addr in range(0, len(mem), RECORD_SIZE):
        upper = addr >> 16
        if upper != current_upper:
            lines.append(upper_record(upper))
            current_upper = upper
        lines.append(data_record(addr & 0xFFFF, mem[addr : addr + RECORD_SIZE]))

    lines.append(":00000001FF")
    Path(path).write_text("\n".join(lines) + "\n")


def bbox(mem, width):
    coords = [(idx % width, idx // width) for idx, value in enumerate(mem) if value]
    if not coords:
        raise ValueError("No live cells found")

    xs = [x for x, _ in coords]
    ys = [y for _, y in coords]
    return min(xs), min(ys), max(xs), max(ys)


def raw_to_ring_display(mem):
    return [mem[0]] + list(reversed(mem[1:]))


def ring_display_to_raw(display):
    return [display[0]] + list(reversed(display[1:]))


def shift_image_to_target_center(image, width, target_cx, target_cy):
    min_x, min_y, max_x, max_y = bbox(image, width)
    old_cx = (min_x + max_x) / 2
    old_cy = (min_y + max_y) / 2
    dx = round(target_cx - old_cx)
    dy = round(target_cy - old_cy)

    height = len(image) // width
    shifted = [0] * len(image)
    dropped = 0

    for idx, value in enumerate(image):
        if not value:
            continue
        x = idx % width
        y = idx // width
        nx = x + dx
        ny = y + dy
        if 0 <= nx < width and 0 <= ny < height:
            shifted[ny * width + nx] = value
        else:
            dropped += 1

    return shifted, (min_x, min_y, max_x, max_y), bbox(shifted, width), dx, dy, dropped


def shift_to_target_center(mem, width, target_cx, target_cy, space):
    if space == "raw":
        return shift_image_to_target_center(mem, width, target_cx, target_cy)

    display = raw_to_ring_display(mem)
    shifted_display, before, after, dx, dy, dropped = shift_image_to_target_center(display, width, target_cx, target_cy)
    return ring_display_to_raw(shifted_display), before, after, dx, dy, dropped


def main():
    parser = argparse.ArgumentParser(description="Shift Life initial Intel HEX image to a target center.")
    parser.add_argument("source", help="Input Intel HEX file")
    parser.add_argument("target", nargs="?", help="Output Intel HEX file. Defaults to in-place update.")
    parser.add_argument(
        "--space",
        choices=("raw", "ring-display"),
        default="raw",
        help="Coordinate space to center. Raw is Intel HEX address order; ring-display is the reversed order read by the ring counter.",
    )
    parser.add_argument("--target-x", type=float, default=(ACTIVE_WIDTH - 1) / 2, help="Target center X coordinate")
    parser.add_argument("--target-y", type=float, default=(ACTIVE_HEIGHT - 1) / 2, help="Target center Y coordinate")
    args = parser.parse_args()

    source = Path(args.source)
    target = Path(args.target) if args.target else source
    mem = parse_ihex(source)
    shifted, before, after, dx, dy, dropped = shift_to_target_center(
        mem, BOARD_WIDTH, args.target_x, args.target_y, args.space
    )

    if dropped:
        raise SystemExit(f"Refusing to write: shift would drop {dropped} live cells")

    write_ihex(target, shifted)

    print(f"live cells: {sum(1 for v in mem if v)}")
    print(f"shift: dx={dx}, dy={dy}")
    print(f"space: {args.space}")
    print(f"target center: ({args.target_x}, {args.target_y})")
    print(f"before bbox: {before}")
    print(f"after bbox:  {after}")


if __name__ == "__main__":
    main()
