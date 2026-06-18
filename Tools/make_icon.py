#!/usr/bin/env python3
"""Dependency-free renderer for the BeamerPresenter app icon.

Draws the icon analytically (signed-distance rounded rects + circles with 1px
anti-aliasing) at every size macOS needs and writes a `.iconset` folder plus a
1024px master PNG. No third-party libraries — just the standard library — so it
runs anywhere. On macOS, `iconutil` turns the `.iconset` into `BeamerPresenter.icns`
(see make-icon.sh / build-app.sh).
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


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

# ---------------------------------------------------------------- the icon

# Night Console palette: near-black tile + glowing lime bar chart.
BG_TOP = (32, 36, 44)
BG_BOT = (9, 10, 13)
LIME   = (198, 240, 74)

GLOW_PASSES = 16
GLOW_MAX = 0.060
GLOW_ALPHA = 0.05


def glow_rr(buf, S, cx, cy, w, h, r, color):
    for k in range(GLOW_PASSES, 0, -1):
        grow = S * GLOW_MAX * (k / GLOW_PASSES)
        fill_rr(buf, S, S, cx, cy, w + 2 * grow, h + 2 * grow, r + grow,
                color=color, alpha=GLOW_ALPHA)
    fill_rr(buf, S, S, cx, cy, w, h, r, color=color)


def glow_circle(buf, S, cx, cy, rad, color):
    for k in range(GLOW_PASSES, 0, -1):
        grow = S * GLOW_MAX * (k / GLOW_PASSES)
        fill_circle(buf, S, S, cx, cy, rad + grow, color, alpha=GLOW_ALPHA)
    fill_circle(buf, S, S, cx, cy, rad, color)


def render(S):
    buf = bytearray(S * S * 4)               # transparent RGBA

    def bg_grad(t):
        base = lerp(BG_TOP, BG_BOT, min(max(t, 0), 1))
        hi = max(0.0, 1 - t * 2.4) * 0.10
        return tuple(min(255, c + (255 - c) * hi) for c in base)

    # Background squircle (full-bleed with a hair of margin).
    m = S * 0.035
    fill_rr(buf, S, S, S / 2, S / 2, S - 2 * m, S - 2 * m, S * 0.2237, grad=bg_grad)

    # Three lime bars, bottom-aligned, the middle one tallest.
    bw = S * 0.135
    gap = S * 0.052
    total = 3 * bw + 2 * gap
    x0 = S / 2 - total / 2 + bw / 2
    base_y = S * 0.78
    heights = [S * 0.31, S * 0.48, S * 0.35]
    r = bw * 0.30
    for i, h in enumerate(heights):
        cx = x0 + i * (bw + gap)
        glow_rr(buf, S, cx, base_y - h / 2, bw, h, r, LIME)

    # A dot floating above the middle bar.
    mid_cx = x0 + (bw + gap)
    mid_top = base_y - heights[1]
    dot_r = S * 0.050
    glow_circle(buf, S, mid_cx, mid_top - S * 0.03 - dot_r, dot_r, LIME)

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


if __name__ == "__main__":
    main()
