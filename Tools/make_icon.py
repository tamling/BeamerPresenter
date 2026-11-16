#!/usr/bin/env python3
"""Dependency-free renderer for the BeamerPresenter app icon.

The icon is Mina, drawn analytically (signed-distance rounded rects, circles and
triangles with 1px anti-aliasing) at every size macOS needs. It writes a
`.iconset` folder plus a 1024px master PNG. No third-party libraries — just the
standard library — so it runs anywhere. On macOS, `iconutil` turns the
`.iconset` into `BeamerPresenter.icns` (see make-icon.sh / build-app.sh).

Everything is laid out relative to the head radius, so the proportions that make
a face read as friendly rather than blank — big eyes set low and close together,
a round head, short ears — hold at 16px as well as at 1024.
"""

import math
import os
import struct
import zlib

# ---------------------------------------------------------------- PNG output

def write_png(path, w, h, buf):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)                       # filter type 0 (None)
        raw += buf[y * stride:(y + 1) * stride]
    comp = zlib.compress(bytes(raw), 9)

    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data +
                struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", comp))
        f.write(chunk(b"IEND", b""))

# ---------------------------------------------------------------- drawing

def blend(buf, idx, r, g, b, a):
    """Source-over compositing of a straight-alpha pixel."""
    if a <= 0:
        return
    da = buf[idx + 3] / 255.0
    oa = a + da * (1 - a)
    if oa <= 0:
        return
    inv = da * (1 - a)
    buf[idx]     = min(255, int((r * a + buf[idx]     * inv) / oa + 0.5))
    buf[idx + 1] = min(255, int((g * a + buf[idx + 1] * inv) / oa + 0.5))
    buf[idx + 2] = min(255, int((b * a + buf[idx + 2] * inv) / oa + 0.5))
    buf[idx + 3] = int(oa * 255 + 0.5)


def rr_dist(px, py, cx, cy, w, h, r):
    """Signed distance (px) to a rounded rectangle; negative = inside."""
    qx = abs(px - cx) - (w / 2 - r)
    qy = abs(py - cy) - (h / 2 - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def fill_rr(buf, W, H, cx, cy, w, h, r, color=None, alpha=1.0, grad=None):
    x0 = max(0, int(cx - w / 2 - 1)); x1 = min(W, int(cx + w / 2 + 2))
    y0 = max(0, int(cy - h / 2 - 1)); y1 = min(H, int(cy + h / 2 + 2))
    top = cy - h / 2
    for y in range(y0, y1):
        col = grad((y + 0.5 - top) / h) if grad else color
        cr, cg, cb = col
        row = y * W
        for x in range(x0, x1):
            d = rr_dist(x + 0.5, y + 0.5, cx, cy, w, h, r)
            cov = min(max(0.5 - d, 0.0), 1.0)
            if cov > 0:
                blend(buf, (row + x) * 4, cr, cg, cb, cov * alpha)


def fill_circle(buf, W, H, cx, cy, rad, color, alpha=1.0):
    fill_rr(buf, W, H, cx, cy, rad * 2, rad * 2, rad, color=color, alpha=alpha)


# ---------------------------------------------------------------- the icon

# The brand red. This is one of four places the value is written down — the
# others are Theme.swift and night.css (twice) — and nothing in the build
# compares them, so Tools/check_colors.py does. It reads the line below by
# pattern, which is why the literal stays on its own line as a plain string.
BRAND = "#E30613"


def _hex(s):
    v = int(s.lstrip("#"), 16)
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


# Mina: black with a white bib, a white fleck under the nose set off to the
# viewer's right, amber eyes and big ears. NIGHT is the shipped icon; PAPER is
# swapped into the Dock at runtime for the light appearance.
NIGHT = dict(GROUND=_hex(BRAND), FUR=(30, 27, 31), WHITE=(249, 246, 240),
             EYE=(232, 190, 80), NOSE=(224, 150, 152), SNOUT=(54, 48, 52))
PAPER = dict(GROUND=(243, 237, 226), FUR=(32, 29, 32), WHITE=(252, 250, 246),
             EYE=(206, 160, 52), NOSE=(214, 138, 140), SNOUT=(58, 52, 56))


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    t = max(0.0, min(1.0, (wx * vx + wy * vy) / (vx * vx + vy * vy)))
    return math.hypot(wx - t * vx, wy - t * vy)


def tri_dist(px, py, a, b, c):
    """Signed distance to the triangle a-b-c; negative = inside."""
    d = min(seg_dist(px, py, *a, *b), seg_dist(px, py, *b, *c),
            seg_dist(px, py, *c, *a))
    s1 = (b[0] - a[0]) * (py - a[1]) - (b[1] - a[1]) * (px - a[0])
    s2 = (c[0] - b[0]) * (py - b[1]) - (c[1] - b[1]) * (px - b[0])
    s3 = (a[0] - c[0]) * (py - c[1]) - (a[1] - c[1]) * (px - c[0])
    inside = (s1 >= 0 and s2 >= 0 and s3 >= 0) or (s1 <= 0 and s2 <= 0 and s3 <= 0)
    return -d if inside else d


def fill_tri(buf, S, a, b, c, round_r, color=None, alpha=1.0, grad=None):
    """Fills the triangle expanded by `round_r` (which rounds its corners)."""
    x0 = max(0, int(min(a[0], b[0], c[0]) - round_r - 1))
    x1 = min(S, int(max(a[0], b[0], c[0]) + round_r + 2))
    y0 = max(0, int(min(a[1], b[1], c[1]) - round_r - 1))
    y1 = min(S, int(max(a[1], b[1], c[1]) + round_r + 2))
    top, height = y0, max(1, y1 - y0)
    for y in range(y0, y1):
        col = grad((y + 0.5 - top) / height) if grad else color
        cr, cg, cb = col
        row = y * S
        for x in range(x0, x1):
            d = tri_dist(x + 0.5, y + 0.5, a, b, c) - round_r
            cov = min(max(0.5 - d, 0.0), 1.0)
            if cov > 0:
                blend(buf, (row + x) * 4, cr, cg, cb, cov * alpha)


def squircle(buf, S, color):
    m = S * 0.035
    fill_rr(buf, S, S, S / 2, S / 2, S - 2 * m, S - 2 * m, S * 0.2237, color=color)


def smile(buf, S, cx, cy, rx, ry, thick, color):
    """A closed, content eye: a shallow arc stroked with overlapping dots.

    Arcs survive being shrunk far better than pupils do — at 32px a drawn eyeball
    turns to mud, while the curve still reads.
    """
    n = 48
    for i in range(n + 1):
        t = -1 + 2 * i / n
        fill_circle(buf, S, S, cx + t * rx, cy - ry * (1 - t * t), thick, color)


def render(S, pal=NIGHT, bleed=False):
    """`bleed` fills the whole square instead of drawing a squircle — iOS wants an
    opaque, square icon and applies its own mask, so transparent corners there are
    a defect rather than a style."""
    buf = bytearray(S * S * 4)                 # transparent RGBA
    fur, white = pal["FUR"], pal["WHITE"]
    cx = S / 2

    if bleed:
        g = pal["GROUND"]
        for i in range(0, S * S * 4, 4):
            buf[i], buf[i + 1], buf[i + 2], buf[i + 3] = g[0], g[1], g[2], 255
    else:
        squircle(buf, S, pal["GROUND"])

    # Shoulders. The squircle crops them, which is what keeps her looking like
    # she is sitting in the icon rather than floating in it.
    chy, chw, chh = S * 0.880, S * 0.58, S * 0.30
    fill_rr(buf, S, S, cx, chy, chw, chh, S * 0.20, color=fur)

    hy, hr = S * 0.470, S * 0.250
    for sx in (-1, 1):
        fill_tri(buf, S,
                 (cx + sx * hr * 0.26, hy - hr * 0.72),
                 (cx + sx * hr * 1.04, hy - hr * 0.44),
                 (cx + sx * hr * 0.84, hy - hr * 1.44),
                 S * 0.028, color=fur)
    # Wider than tall: a round head reads as soft, a rounded square does not.
    fill_rr(buf, S, S, cx, hy, hr * 2.14, hr * 1.86, hr * 0.92, color=fur)

    # Chin from two overlapping circles rather than a rounded rect, so her
    # marking can lift one side of it without leaving a visible step.
    jaw = hy + hr * 0.74
    fill_circle(buf, S, S, cx - hr * 0.11, jaw + hr * 0.04, hr * 0.225, white)
    fill_circle(buf, S, S, cx + hr * 0.12, jaw + hr * 0.02, hr * 0.225, white)
    fill_tri(buf, S, (cx - hr * 0.52, jaw + hr * 0.04),
             (cx + hr * 0.52, jaw + hr * 0.04),
             (cx, chy + chh * 0.20), S * 0.040, color=white)

    # Eyes low and close together — the single thing that decides whether the
    # face looks friendly or vacant.
    ex, ey = hr * 0.46, hy + hr * 0.16
    for sx in (-1, 1):
        smile(buf, S, cx + sx * ex, ey + S * 0.012, S * 0.060, S * 0.044,
              S * 0.0165, pal["EYE"])

    # Her own fleck: it rises out of the chin under the nose, set off to the
    # viewer's right. A separate dot beside the nose is not what she has.
    chin_top = jaw - hr * 0.17
    fill_circle(buf, S, S, cx + hr * 0.17, chin_top + hr * 0.02, hr * 0.135, white)

    # Dark nose, pink only at the tip.
    nb = chin_top - hr * 0.26
    fill_tri(buf, S, (cx - S * 0.040, nb), (cx + S * 0.040, nb),
             (cx, nb + S * 0.054), S * 0.010, color=pal["SNOUT"])
    fill_circle(buf, S, S, cx, nb + S * 0.046, S * 0.013, pal["NOSE"])

    return buf

# ---------------------------------------------------------------- main

ICONSET = {
    16:  ["icon_16x16.png"],
    32:  ["icon_16x16@2x.png", "icon_32x32.png"],
    64:  ["icon_32x32@2x.png"],
    128: ["icon_128x128.png"],
    256: ["icon_128x128@2x.png", "icon_256x256.png"],
    512: ["icon_256x256@2x.png", "icon_512x512.png"],
    1024:["icon_512x512@2x.png"],
}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    res = os.path.normpath(os.path.join(here, "..", "Resources"))
    iconset = os.path.join(res, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)

    for size, names in sorted(ICONSET.items()):
        print(f"  rendering {size}px")
        buf = render(size)
        for name in names:
            write_png(os.path.join(iconset, name), size, size, buf)
        if size == 1024:
            write_png(os.path.join(res, "AppIcon.png"), size, size, buf)

    print(f"✓ wrote {iconset} and Resources/AppIcon.png")

    print("  rendering 512px (Paper)")
    write_png(os.path.join(res, "AppIconLight.png"), 512, 512, render(512, PAPER))
    print("✓ wrote Resources/AppIconLight.png")

    # One source for all three platforms: three icon sets drifting apart is how
    # an app ends up wearing a different face per operating system.
    root = os.path.normpath(os.path.join(here, ".."))

    linux = os.path.join(root, "Linux", "src-tauri", "icons")
    if os.path.isdir(linux):
        for name, size in (("32x32.png", 32), ("128x128.png", 128),
                           ("128x128@2x.png", 256), ("icon.png", 512)):
            write_png(os.path.join(linux, name), size, size, render(size))
        print("✓ wrote Linux/src-tauri/icons")

    ios = os.path.join(root, "iOS", "BeamerPresenter", "Assets.xcassets",
                       "AppIcon.appiconset")
    if os.path.isdir(ios):
        write_png(os.path.join(ios, "icon-1024.png"), 1024, 1024,
                  render(1024, bleed=True))
        print("✓ wrote iOS AppIcon.appiconset")


if __name__ == "__main__":
    main()
