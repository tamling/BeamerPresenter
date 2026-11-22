#!/usr/bin/env python3
"""Test fixtures for the AlbumArtwork screensaver, from the standard library only.

  make-fixtures.py images <n> <dir>   n single-colour 64x48 PNGs, each its own colour
"""
import argparse
import os
import struct
import zlib

# Not square, so the screensaver's middle-square crop is exercised.
IMAGE_WIDTH, IMAGE_HEIGHT = 64, 48
# colour() gives this many distinct colours.
MAX_IMAGES = 1 << 21


def png(width, height, rgb):
    """A width x height PNG (8-bit RGB) filled with one colour."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit, RGB, no interlace
    row = b"\x00" + bytes(rgb) * width  # filter type 0: none
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b""))


def colour(i):
    """Colour number i: distinct for every i below MAX_IMAGES, no channel below 64."""
    k = ((i + 1) * 0x9E3779B1) % MAX_IMAGES  # an odd factor permutes 0..MAX_IMAGES-1
    return tuple(64 + ((k >> shift) & 0x7F) * 3 // 2 for shift in (14, 7, 0))


def images(args):
    os.makedirs(args.dir, exist_ok=True)
    for i in range(args.n):
        with open(os.path.join(args.dir, f"cover-{i + 1:04d}.png"), "wb") as f:
            f.write(png(IMAGE_WIDTH, IMAGE_HEIGHT, colour(i)))
    print(f"wrote {args.n} images to {args.dir}")


def main():
    parser = argparse.ArgumentParser(description="Test fixtures for the AlbumArtwork screensaver.")
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("images", help="single-colour PNGs, each its own colour")
    command.add_argument("n", type=int, help="how many images")
    command.add_argument("dir", help="folder to write them to (created if missing)")
    command.set_defaults(run=images)
    args = parser.parse_args()
    if args.command == "images" and not 0 <= args.n <= MAX_IMAGES:
        parser.error(f"n must be between 0 and {MAX_IMAGES}")
    args.run(args)


if __name__ == "__main__":
    main()
