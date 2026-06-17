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

# Palette
TOP   = (84, 104, 255)     # indigo
BOT   = (139, 92, 246)     # violet
WHITE = (255, 255, 255)
INK1  = (79, 102, 241)     # bar colours (light -> dark)
INK2  = (99, 91, 240)
INK3  = (124, 92, 246)
TITLE = (255, 176, 32)     # warm title accent on the slide
LASER = (255, 59, 48)      # red laser dot


def render(S):
    buf = bytearray(S * S * 4)               # transparent RGBA

    def bg_grad(t):
        # main vertical gradient with a soft highlight near the top
        base = lerp(TOP, BOT, min(max(t, 0), 1))
        hi = max(0.0, 1 - t * 2.2) * 0.18
        return tuple(min(255, c + (255 - c) * hi) for c in base)

    # Background squircle (full-bleed with a hair of margin).
    m = S * 0.035
    fill_rr(buf, S, S, S / 2, S / 2, S - 2 * m, S - 2 * m, S * 0.2237, grad=bg_grad)

    # Presentation screen — soft shadow then a white panel.
    sw, sh = S * 0.66, S * 0.44
    scx, scy = S * 0.5, S * 0.435
    sr = S * 0.045
    fill_rr(buf, S, S, scx, scy + S * 0.012, sw, sh, sr, color=(0, 0, 0), alpha=0.18)
    fill_rr(buf, S, S, scx, scy, sw, sh, sr, color=WHITE)

    # Slide content: a little bar chart + a title bar.
    pad = S * 0.055
    inner_l = scx - sw / 2 + pad
    inner_r = scx + sw / 2 - pad
    base_y = scy + sh / 2 - pad
    top_y = scy - sh / 2 + pad

    # Title accent bar (top-left of the slide).
    tw = (inner_r - inner_l) * 0.5
    th = S * 0.028
    fill_rr(buf, S, S, inner_l + tw / 2, top_y + th / 2, tw, th, th / 2, color=TITLE)

    # Three bars growing left-to-right.
    bw = S * 0.072
    gap = S * 0.045
    chart_left = inner_l + bw / 2
    heights = [S * 0.11, S * 0.175, S * 0.135]
    colors = [INK1, INK2, INK3]
    for i, (bh, col) in enumerate(zip(heights, colors)):
        bx = chart_left + i * (bw + gap)
        fill_rr(buf, S, S, bx, base_y - bh / 2, bw, bh, bw * 0.18, color=col)

    # Laser dot in the slide's top-right corner.
    fill_circle(buf, S, S, inner_r - S * 0.03, top_y + S * 0.045, S * 0.026, LASER)

    # Stand: neck + base, in translucent white.
    neck_w = S * 0.03
    neck_top = scy + sh / 2
    neck_bot = S * 0.72
    fill_rr(buf, S, S, scx, (neck_top + neck_bot) / 2, neck_w, neck_bot - neck_top,
            neck_w / 2, color=WHITE, alpha=0.92)
    fill_rr(buf, S, S, scx, neck_bot + S * 0.018, S * 0.26, S * 0.036, S * 0.018,
            color=WHITE, alpha=0.92)

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
