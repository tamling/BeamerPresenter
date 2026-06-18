#!/usr/bin/env python3
"""Dependency-free renderer for the BeamerPresenter iPad app icon.

Draws the icon analytically (signed-distance rounded rects + circles with 1px
anti-aliasing) and writes a 1024px PNG into the iOS asset catalog's
`AppIcon.appiconset` (single-size universal icon). No third-party libraries —
just the standard library — so it runs anywhere.

    python3 iOS/Tools/make_app_icon.py
"""

import json
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

# Night Console icon: a near-black tile with a glowing lime bar chart.
BG_TOP = (32, 36, 44)     # raised-ish, top-left light
BG_BOT = (9, 10, 13)      # stage / blackout
LIME   = (198, 240, 74)   # electric lime signal


GLOW_PASSES = 16
GLOW_MAX = 0.060        # outer radius of the glow, as a fraction of S
GLOW_ALPHA = 0.05       # per-pass alpha; overlap builds a smooth falloff


def glow_rr(buf, S, cx, cy, w, h, r, color):
    """A rounded rect with a soft outer glow (many low-alpha passes, big→small)."""
    for k in range(GLOW_PASSES, 0, -1):
        t = k / GLOW_PASSES
        grow = S * GLOW_MAX * t
        fill_rr(buf, S, S, cx, cy, w + 2 * grow, h + 2 * grow, r + grow,
                color=color, alpha=GLOW_ALPHA)
    fill_rr(buf, S, S, cx, cy, w, h, r, color=color)


def glow_circle(buf, S, cx, cy, rad, color):
    for k in range(GLOW_PASSES, 0, -1):
        t = k / GLOW_PASSES
        grow = S * GLOW_MAX * t
        fill_circle(buf, S, S, cx, cy, rad + grow, color, alpha=GLOW_ALPHA)
    fill_circle(buf, S, S, cx, cy, rad, color)


def render(S):
    buf = bytearray(S * S * 4)

    def bg_grad(t):
        # diagonal-ish dark gradient with a faint top highlight
        base = lerp(BG_TOP, BG_BOT, min(max(t, 0), 1))
        hi = max(0.0, 1 - t * 2.4) * 0.10
        return tuple(min(255, c + (255 - c) * hi) for c in base)

    # iOS icons are full-bleed (the system applies the mask), so no margin.
    fill_rr(buf, S, S, S / 2, S / 2, S, S, S * 0.2237, grad=bg_grad)

    # Three lime bars, bottom-aligned, the middle one tallest.
    bw = S * 0.135
    gap = S * 0.052
    total = 3 * bw + 2 * gap
    x0 = S / 2 - total / 2 + bw / 2
    base_y = S * 0.80
    heights = [S * 0.32, S * 0.50, S * 0.36]
    r = bw * 0.30
    for i, h in enumerate(heights):
        cx = x0 + i * (bw + gap)
        glow_rr(buf, S, cx, base_y - h / 2, bw, h, r, LIME)

    # A dot floating above the middle bar.
    mid_cx = x0 + (bw + gap)
    mid_top = base_y - heights[1]
    dot_r = S * 0.052
    glow_circle(buf, S, mid_cx, mid_top - S * 0.03 - dot_r, dot_r, LIME)

    return buf

# ---------------------------------------------------------------- main

CONTENTS = {
    "images": [
        {"filename": "icon-1024.png", "idiom": "universal",
         "platform": "ios", "size": "1024x1024"}
    ],
    "info": {"author": "xcode", "version": 1},
}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    iconset = os.path.normpath(os.path.join(
        here, "..", "BeamerPresenter", "Assets.xcassets", "AppIcon.appiconset"))
    os.makedirs(iconset, exist_ok=True)

    print("  rendering 1024px")
    write_png(os.path.join(iconset, "icon-1024.png"), 1024, 1024, render(1024))
    with open(os.path.join(iconset, "Contents.json"), "w") as f:
        json.dump(CONTENTS, f, indent=2)

    # Asset catalog root needs its own Contents.json too.
    assets = os.path.dirname(iconset)
    with open(os.path.join(assets, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

    print(f"✓ wrote {iconset}")


if __name__ == "__main__":
    main()
