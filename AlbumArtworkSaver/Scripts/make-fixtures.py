#!/usr/bin/env python3
"""Test fixtures for the AlbumArtwork screensaver, from the standard library only.

  make-fixtures.py images <n> <dir>   n single-colour 64x48 PNGs, each its own colour
  make-fixtures.py mp3 <dir>          a small music folder (see mp3() for its files)
  make-fixtures.py mp3-one <file> <album> <r,g,b>
                                      one MP3 with that album title and a cover in that colour

The MP3s are an ID3v2 tag followed by 1024 zero bytes: enough for the scanner,
which reads the tag only.
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


# ID3v2 tags. Text frames are Latin-1 in v2.3 and UTF-8 in v2.4.

AUDIO = bytes(1024)


def syncsafe(n):
    """n as four 7-bit bytes, as ID3v2 stores tag (and v2.4 frame) sizes."""
    assert 0 <= n < 1 << 28
    return bytes((n >> shift) & 0x7F for shift in (21, 14, 7, 0))


def frame(version, frame_id, content):
    size = syncsafe(len(content)) if version == 4 else struct.pack(">I", len(content))
    return frame_id.encode("ascii") + size + b"\x00\x00" + content


def text_frame(version, frame_id, text):
    if version == 4:
        return frame(version, frame_id, b"\x03" + text.encode("utf-8"))
    return frame(version, frame_id, b"\x00" + text.encode("latin-1"))


def picture_frame(version, image):
    """APIC: MIME type, picture type 3 (front cover), empty description, the PNG."""
    encoding = b"\x03" if version == 4 else b"\x00"
    return frame(version, "APIC", encoding + b"image/png\x00" + b"\x03" + b"\x00" + image)


def tag(version, frames, size=None):
    """An ID3v2.<version> tag of `frames`; `size` overrides the size its header claims."""
    body = b"".join(frames)
    claimed = len(body) if size is None else size
    return b"ID3" + bytes((version, 0, 0)) + syncsafe(claimed) + body


def write_mp3(path, data):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(data + AUDIO)


def track(version=3, album=None, artist=None, image=None):
    frames = []
    if album is not None:
        frames.append(text_frame(version, "TALB", album))
    if artist is not None:
        frames.append(text_frame(version, "TPE1", artist))
    if image is not None:
        frames.append(picture_frame(version, image))
    return tag(version, frames)


def mp3(args):
    """Seven MP3s in three albums, plus one hidden one the scanner must skip:

      A/01-03.mp3   v2.3, "Album A" by "Artist A", the same red 1000x800 cover
      B/01.mp3      v2.4 (UTF-8), "Album B", a blue cover
      loose.mp3     no album, a green cover (an album of its own)
      nopic.mp3     only an album title, no cover
      broken.mp3    its tag claims more bytes than the file has
      .hidden/x.mp3 a valid track in a hidden folder
    """
    red = png(1000, 800, (200, 30, 30))  # larger than a cached cover, and not square
    files = {
        "A/01.mp3": track(album="Album A", artist="Artist A", image=red),
        "A/02.mp3": track(album="Album A", artist="Artist A", image=red),
        "A/03.mp3": track(album="Album A", artist="Artist A", image=red),
        "B/01.mp3": track(version=4, album="Album B", image=png(IMAGE_WIDTH, IMAGE_HEIGHT, (30, 30, 200))),
        "loose.mp3": track(image=png(IMAGE_WIDTH, IMAGE_HEIGHT, (30, 200, 30))),
        "nopic.mp3": track(album="No Cover"),
        # A frame that runs past the end, in a tag that claims 1 MiB.
        "broken.mp3": tag(3, [b"TALB" + struct.pack(">I", 5000) + b"\x00\x00" + b"\x00Broken"], size=1 << 20),
        ".hidden/x.mp3": track(album="Hidden", image=png(IMAGE_WIDTH, IMAGE_HEIGHT, (200, 200, 30))),
    }
    for name, data in files.items():
        write_mp3(os.path.join(args.dir, name), data)
    print(f"wrote {len(files)} MP3s to {args.dir}")


def mp3_one(args):
    write_mp3(args.file, track(album=args.album, image=png(IMAGE_WIDTH, IMAGE_HEIGHT, args.rgb)))
    print(f"wrote {args.file}")


def rgb(value):
    parts = value.split(",")
    if len(parts) != 3 or not all(p.strip().isdigit() and int(p) <= 255 for p in parts):
        raise argparse.ArgumentTypeError(f"{value!r} is not r,g,b with 0-255 each")
    return tuple(int(p) for p in parts)


def main():
    parser = argparse.ArgumentParser(description="Test fixtures for the AlbumArtwork screensaver.")
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("images", help="single-colour PNGs, each its own colour")
    command.add_argument("n", type=int, help="how many images")
    command.add_argument("dir", help="folder to write them to (created if missing)")
    command.set_defaults(run=images)
    command = commands.add_parser("mp3", help="a small music folder with MP3s of three albums")
    command.add_argument("dir", help="folder to write them to (created if missing)")
    command.set_defaults(run=mp3)
    command = commands.add_parser("mp3-one", help="one MP3 with an album title and a one-colour cover")
    command.add_argument("file", help="the MP3 to write (its folder is created if missing)")
    command.add_argument("album", help="the album title")
    command.add_argument("rgb", type=rgb, help="the cover's colour as r,g,b, e.g. 255,160,0")
    command.set_defaults(run=mp3_one)
    args = parser.parse_args()
    if args.command == "images" and not 0 <= args.n <= MAX_IMAGES:
        parser.error(f"n must be between 0 and {MAX_IMAGES}")
    args.run(args)


if __name__ == "__main__":
    main()
