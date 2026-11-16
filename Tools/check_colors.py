#!/usr/bin/env python3
"""Guards the brand colour: one value everywhere, readable, and not confusable
with a colour that means something.

    python3 Tools/check_colors.py

Run it by hand or from CI. It reads the real files — it has no copy of the
palette of its own, because a checker with its own copy of the thing it checks
is the drift it is meant to catch.

Three things are asserted:

  parity    The brand red is one value. It is written down in four places that
            no compiler compares: the Swift theme, the Linux stylesheet (twice,
            Night and Paper), and the icon renderer. Two near-identical reds are
            invisible to a reader and obvious to nobody, which is exactly how
            they drift.

  contrast  Whatever is drawn on the brand fill clears WCAG AA (4.5:1), by the
            real formula — sRGB gamma expansion, then 0.2126/0.7152/0.0722.
            The naive version that skips the gamma step reports black as the
            better label on this red (5.23 against white's 4.02) and is wrong:
            with the gamma step white reaches 4.88 and black only 4.30, so the
            shortcut does not merely lose precision, it inverts the answer.

  distance  The brand stays clear of the colours that carry meaning — the
            overrun red, the warning amber, the ready green, the running
            orange. A brand that collides with a status colour cannot be read
            as either.
"""

import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ------------------------------------------------------------------ WCAG


def _linear(channel_byte):
    """sRGB 0-255 -> linear 0-1. The step the shortcut formulas leave out."""
    c = channel_byte / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = rgb
    return 0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b)


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def _lab(c):
    """sRGB -> CIE L*a*b* (D65). Distance in Lab accounts for lightness and
    chroma as well as hue, which hue alone does not: a pale rose and a signal
    red share a hue and are in no danger of being confused."""
    r, g, b = (_linear(x) for x in c)
    X = r * 0.4124 + g * 0.3576 + b * 0.1805
    Y = r * 0.2126 + g * 0.7152 + b * 0.0722
    Z = r * 0.0193 + g * 0.1192 + b * 0.9505

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = f(X / 0.95047), f(Y / 1.0), f(Z / 1.08883)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def delta_e(a, b):
    """CIE76. Rough rule of thumb: under ~2.3 is invisible, over ~25 is two
    plainly different colours."""
    return sum((x - y) ** 2 for x, y in zip(_lab(a), _lab(b))) ** 0.5


def rgb(text):
    """'#E30613', 'E30613' or '0xE30613' -> (227, 6, 19)."""
    s = text.strip().lstrip("#")
    if s.lower().startswith("0x"):
        s = s[2:]
    v = int(s, 16)
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def as_hex(c):
    return "#%02X%02X%02X" % c


# ------------------------------------------------------- reading the files
# Each reader pulls the value out of the file that actually ships it. If a file
# is restructured so a pattern stops matching, that is a failure too: a check
# that silently finds nothing is indistinguishable from one that passes.


def _one(path, pattern, what):
    text = (ROOT / path).read_text()
    found = re.findall(pattern, text, re.M)
    if len(found) != 1:
        sys.exit(f"✗ {path}: expected exactly one {what}, found {len(found)}.\n"
                 f"  Pattern: {pattern}\n"
                 f"  If the file was restructured, update this check — do not "
                 f"loosen the pattern until it matches something.")
    return found[0]


def brand_sources():
    """Every place the brand red is written down, as {label: rgb}."""
    return {
        "Theme.swift accent":
            rgb(_one("Sources/Shared/Theme.swift",
                     r"static let accent\s*=\s*Color\(hex:\s*(0x[0-9A-Fa-f]{6})\)",
                     "accent")),
        "night.css --accent (Night)":
            rgb(_one("Linux/ui/css/night.css",
                     r"--accent:\s*(#[0-9A-Fa-f]{6})",
                     "--accent")),
        "night.css --accent-ring (Night)":
            rgb(_one("Linux/ui/css/night.css",
                     r"--accent-ring:\s*(#[0-9A-Fa-f]{6});\s*/\* brand",
                     "--accent-ring marked as the brand")),
        "make_icon.py BRAND":
            rgb(_one("Tools/make_icon.py",
                     r"^BRAND\s*=\s*\"(#[0-9A-Fa-f]{6})\"",
                     "BRAND")),
    }


def on_brand():
    """The colour drawn on top of a brand fill."""
    return rgb(_one("Sources/Shared/Theme.swift",
                    r"static let onAccent\s*=\s*Color\(hex:\s*(0x[0-9A-Fa-f]{6})\)",
                    "onAccent"))


def accent_ink():
    """The brand as text — read as the Night value of the pick(night, paper)."""
    return rgb(_one("Sources/Shared/Theme.swift",
                    r"static var accentInk: Color\s*\{ pick\(Color\(hex: "
                    r"(0x[0-9A-Fa-f]{6})\)",
                    "accentInk (Night)"))


def meaningful_colours():
    """Colours that carry a meaning and must not be mistaken for the brand."""
    t = (ROOT / "Sources/Shared/Theme.swift").read_text()

    def night(name):
        m = re.search(name + r".*?pick\(Color\(hex:\s*(0x[0-9A-Fa-f]{6})\)", t)
        if not m:
            sys.exit(f"✗ Theme.swift: could not read {name}")
        return rgb(m.group(1))

    def flat(name):
        m = re.search(name + r"\s*=\s*Color\(hex:\s*(0x[0-9A-Fa-f]{6})\)", t)
        if not m:
            sys.exit(f"✗ Theme.swift: could not read {name}")
        return rgb(m.group(1))

    # Split by role. A colour is only confusable with another one used the same
    # way: the brand is a fill, so it is checked against the other fills; the
    # brand's ink is text, so it is checked against the other text colours.
    #
    # The brand red and the overrun red are 22.4 apart, which would not clear
    # the threshold — and they are deliberately not compared, because they
    # never share a role. The brand is never drawn as status text and the
    # overrun red is never a fill. That separation is the thing to protect; if
    # it is ever broken, this split is what has to be revisited, not the number.
    fills = {
        "running (statusRunning)": flat("static let statusRunning"),
        "ready (statusOk)": night("statusOk"),
        "warning (statusWarn)": night("statusWarn"),
    }
    inks = {
        "over time (PenInk.red)": flat("static let red"),
        "warning (statusWarn)": night("statusWarn"),
    }
    return fills, inks


# --------------------------------------------------------------- icon PNGs
# The icons ship as committed PNGs. A source constant agreeing with another
# source constant proves nothing about them: brand-icon.png sat on the previous
# accent for two releases because no script wrote it and no check looked. So
# the check looks — into the pixels, for the brand colour.


def png_colours(path):
    """{(r,g,b): count} for an 8-bit RGB/RGBA PNG. Enough of a decoder for the
    files this repo ships, with no third-party dependency."""
    data = (ROOT / path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"✗ {path}: not a PNG")
    pos, idat, w = 8, bytearray(), None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            if depth != 8 or ctype not in (2, 6):
                sys.exit(f"✗ {path}: only 8-bit RGB/RGBA is handled "
                         f"(depth {depth}, colour type {ctype})")
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
        pos += 12 + length

    chan = 4 if ctype == 6 else 3
    raw = zlib.decompress(bytes(idat))
    stride = w * chan
    out, prev = {}, bytearray(stride)
    at = 0
    for _ in range(h):
        ft = raw[at]; at += 1
        line = bytearray(raw[at:at + stride]); at += stride
        for i in range(stride):
            a = line[i - chan] if i >= chan else 0
            b = prev[i]
            c = prev[i - chan] if i >= chan else 0
            if ft == 1:
                line[i] = (line[i] + a) & 255
            elif ft == 2:
                line[i] = (line[i] + b) & 255
            elif ft == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif ft == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        for x in range(0, stride, chan):
            if chan == 4 and line[x + 3] < 250:
                continue                      # ignore soft edges and corners
            px = (line[x], line[x + 1], line[x + 2])
            out[px] = out.get(px, 0) + 1
        prev = line
    return out


# The icons a change to the palette must be re-rendered into. Each is a file
# that ships to a user: the macOS iconset master, the Linux window/taskbar
# icon, the mark on the Linux home screen, and the iOS app icon.
BRANDED_ICONS = [
    "Resources/AppIcon.png",
    "Linux/src-tauri/icons/icon.png",
    "Linux/ui/brand-icon.png",
    "iOS/BeamerPresenter/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
]


# ------------------------------------------------------------------ checks

AA = 4.5
MIN_DELTA_E = 25.0       # below this, two colours in the same role read alike

failures = []


def check(ok, message):
    print(("  ✓ " if ok else "  ✗ ") + message)
    if not ok:
        failures.append(message)


def main():
    print("Brand parity — the same red in every file that writes it down")
    sources = brand_sources()
    values = set(sources.values())
    for label, value in sources.items():
        print(f"      {as_hex(value)}  {label}")
    check(len(values) == 1,
          f"one value across {len(sources)} files"
          + ("" if len(values) == 1 else f" — found {len(values)}: "
             + ", ".join(sorted(as_hex(v) for v in values))))
    if len(values) != 1:
        report()

    brand = next(iter(values))

    print()
    print("Contrast — the label on the brand fill, real WCAG (sRGB gamma)")
    label = on_brand()
    white, black = (255, 255, 255), (0, 0, 0)
    c_label = contrast(label, brand)
    c_white = contrast(white, brand)
    c_black = contrast(black, brand)
    print(f"      white  on {as_hex(brand)}: {c_white:.2f}:1")
    print(f"      black  on {as_hex(brand)}: {c_black:.2f}:1")
    print(f"      onAccent {as_hex(label)} on {as_hex(brand)}: {c_label:.2f}:1")
    check(c_label >= AA, f"onAccent clears AA ({c_label:.2f}:1 >= {AA})")
    better = white if c_white >= c_black else black
    check(c_label >= contrast(better, brand) - 1e-9,
          f"onAccent is the better of white/black "
          f"(the better one is {as_hex(better)} at "
          f"{max(c_white, c_black):.2f}:1)")

    print()
    print("Distance — the brand must not be mistaken for a meaning (CIE76 dE,")
    print("           compared within a role: fills to fills, text to text)")
    fills, inks = meaningful_colours()
    ink = accent_ink()
    for name, value in fills.items():
        d = delta_e(brand, value)
        check(d >= MIN_DELTA_E,
              f"fill  {as_hex(brand)} is {d:5.1f} from {name} {as_hex(value)}"
              f" (need >= {MIN_DELTA_E})")
    for name, value in inks.items():
        d = delta_e(ink, value)
        check(d >= MIN_DELTA_E,
              f"text  {as_hex(ink)} is {d:5.1f} from {name} {as_hex(value)}"
              f" (need >= {MIN_DELTA_E})")

    print()
    print("Icons — the shipped PNGs carry the brand, not a memory of it")
    for path in BRANDED_ICONS:
        counts = png_colours(path)
        n = counts.get(brand, 0)
        total = sum(counts.values())
        if n:
            check(True, f"{path}: {n} px of {as_hex(brand)}")
        else:
            near = sorted(counts.items(), key=lambda kv: -kv[1])[:3]
            check(False,
                  f"{path}: no {as_hex(brand)} pixel at all. Most common: "
                  + ", ".join(f"{as_hex(c)}x{k}" for c, k in near)
                  + f" (of {total}). Re-run ./make-icon.sh and "
                  f"python3 Linux/make-icon.py.")

    report()


def report():
    print()
    if failures:
        print(f"✗ {len(failures)} check(s) failed")
        sys.exit(1)
    print("✓ all colour checks passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
