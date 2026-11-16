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


# Border thickness, given at 1024 and scaled from there. 8 is the value that
# survives being made small: 12 and 18 both close up by 32px, until the mark is
# a red blob with a white hole in it. The floor of one pixel is what keeps the
# ring from disappearing instead — 8/1024 of a 32px icon is a quarter of a
# pixel, which anti-aliases away to nothing.
BORDER_AT_1024 = 8.0

# The chest bib, as a fraction of the head radius (width) and of the shoulder
# height (how far it drops). On the black-furred icon this could be large: it
# was a light shape inside a dark mass. In red on white it is a gap in her, so
# it is sized to stay well inside the shoulders and read as a marking.
# 0.34/-0.26, chosen by rendering 0.52/-0.12 (what the black-furred icon used),
# 0.34/-0.26, 0.26/-0.34 and no bib at all, at 128, 48 and 32px, and looking.
# The old width splits the shoulders into two lumps with a white wedge between
# them — at 48px it reads as a bow tie. Dropping the bib entirely gives the
# cleanest silhouette but takes away a marking that is hers. This keeps the
# shoulders a single red mass with the bib sitting inside it.
BIB_HALF_WIDTH = 0.34
BIB_DROP = -0.26


def border_width(S):
    return max(1.0, S * BORDER_AT_1024 / 1024.0)


# Mina on a white field inside a brand-red ring, drawn in the brand red. Her
# white markings — the bib, the chin, the fleck under her nose — are the field
# showing through rather than a colour of their own, which is also why they
# hold together when the icon is small: they are the largest shapes in it.
#
# The eyes are the field too. Amber arcs on black fur needed a third colour to
# read; white arcs punched out of the red do not, and two colours survive being
# shrunk in a way that five never did.
#
# NIGHT is the shipped icon; PAPER is swapped into the Dock at runtime for the
# light appearance, and differs only in that its field is warmed very slightly
# so it does not glare against a pale desktop.
NIGHT = dict(GROUND=(255, 255, 255), RING=_hex(BRAND), FUR=_hex(BRAND),
             WHITE=(255, 255, 255), EYE=(255, 255, 255),
             NOSE=(255, 255, 255), SNOUT=(154, 4, 13))
PAPER = dict(GROUND=(252, 250, 248), RING=_hex(BRAND), FUR=_hex(BRAND),
             WHITE=(252, 250, 248), EYE=(252, 250, 248),
             NOSE=(252, 250, 248), SNOUT=(154, 4, 13))


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


def clip_to_squircle(buf, S, inset=0.0, radius=None, margin=None):
    """Clears everything outside the squircle inset by `inset`.

    The drawing below runs past the icon's edge on purpose — the crop is what
    makes her look like she is sitting in the frame rather than floating in it
    — but nothing was actually doing the cropping. On the old icon the ground
    was dark and so was her fur, so the overspill was invisible; against a
    white field her shoulders broke straight through the bottom of the ring.
    """
    m = S * 0.035 + inset if margin is None else margin
    r = (max(0.0, S * 0.2237 - inset) if radius is None else radius)
    for y in range(S):
        row = y * S
        for x in range(S):
            idx = (row + x) * 4
            if buf[idx + 3] and rr_dist(x + 0.5, y + 0.5, S / 2, S / 2,
                                        S - 2 * m, S - 2 * m, r) > 0.5:
                buf[idx + 3] = 0


def squircle(buf, S, color, inset=0.0):
    m = S * 0.035 + inset
    fill_rr(buf, S, S, S / 2, S / 2, S - 2 * m, S - 2 * m,
            max(0.0, S * 0.2237 - inset), color=color)


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
    bw = border_width(S)

    # The ring first, as a solid shape; the field and the motif go on top of it
    # clipped to the inside, so what is left of the ring is an even band and
    # nothing she is drawn with can cross it.
    if bleed:
        # iOS wants an opaque square and applies its own mask, so the ring is
        # the whole square with the field inset into it: whatever the mask
        # trims off the corners, an even band of red is left around the edge.
        r = pal["RING"]
        for i in range(0, S * S * 4, 4):
            buf[i], buf[i + 1], buf[i + 2], buf[i + 3] = r[0], r[1], r[2], 255
        field_inset = bw - S * 0.035
    else:
        squircle(buf, S, pal["RING"])
        field_inset = bw

    motif = bytearray(S * S * 4)
    if bleed:
        g = pal["GROUND"]
        for i in range(0, S * S * 4, 4):
            motif[i], motif[i + 1], motif[i + 2], motif[i + 3] = g[0], g[1], g[2], 255
    else:
        # Not squircle(): that helper ties the corner radius to the margin,
        # and here they must differ. The field has to sit `bw` in from the
        # square edge while keeping the mask's own radius less `bw`, or its
        # corners are rounder than the mask and the ring swells into four red
        # wedges — which is what this did at first.
        fill_rr(motif, S, S, S / 2, S / 2, S - 2 * bw, S - 2 * bw,
                max(0.0, S * 0.2237 - bw), color=pal["GROUND"])

    # Shoulders. The squircle crops them, which is what keeps her looking like
    # she is sitting in the icon rather than floating in it.
    chy, chw, chh = S * 0.880, S * 0.58, S * 0.30
    fill_rr(motif, S, S, cx, chy, chw, chh, S * 0.20, color=fur)

    hy, hr = S * 0.470, S * 0.250
    for sx in (-1, 1):
        fill_tri(motif, S,
                 (cx + sx * hr * 0.26, hy - hr * 0.72),
                 (cx + sx * hr * 1.04, hy - hr * 0.44),
                 (cx + sx * hr * 0.84, hy - hr * 1.44),
                 S * 0.028, color=fur)
    # Wider than tall: a round head reads as soft, a rounded square does not.
    fill_rr(motif, S, S, cx, hy, hr * 2.14, hr * 1.86, hr * 0.92, color=fur)

    # Chin from two overlapping circles rather than a rounded rect, so her
    # marking can lift one side of it without leaving a visible step.
    jaw = hy + hr * 0.74
    fill_circle(motif, S, S, cx - hr * 0.11, jaw + hr * 0.04, hr * 0.225, white)
    fill_circle(motif, S, S, cx + hr * 0.12, jaw + hr * 0.02, hr * 0.225, white)
    # The bib stops short of the shoulders' lower edge. On the old black-furred
    # icon it could run to the bottom of the squircle, because black surrounded
    # it; now that the markings and the field are the same white, anything that
    # reaches the silhouette's edge stops being a marking and becomes a bite
    # taken out of her. There has to be red left underneath it.
    if BIB_HALF_WIDTH > 0:
        fill_tri(motif, S, (cx - hr * BIB_HALF_WIDTH, jaw + hr * 0.04),
                 (cx + hr * BIB_HALF_WIDTH, jaw + hr * 0.04),
                 (cx, chy + chh * BIB_DROP), S * 0.040, color=white)

    # Eyes low and close together — the single thing that decides whether the
    # face looks friendly or vacant.
    ex, ey = hr * 0.46, hy + hr * 0.16
    for sx in (-1, 1):
        smile(motif, S, cx + sx * ex, ey + S * 0.012, S * 0.060, S * 0.044,
              S * 0.0165, pal["EYE"])

    # Her own fleck: it rises out of the chin under the nose, set off to the
    # viewer's right. A separate dot beside the nose is not what she has.
    chin_top = jaw - hr * 0.17
    fill_circle(motif, S, S, cx + hr * 0.17, chin_top + hr * 0.02, hr * 0.135, white)

    # Dark nose, pink only at the tip.
    nb = chin_top - hr * 0.26
    fill_tri(motif, S, (cx - S * 0.040, nb), (cx + S * 0.040, nb),
             (cx, nb + S * 0.054), S * 0.010, color=pal["SNOUT"])
    fill_circle(motif, S, S, cx, nb + S * 0.046, S * 0.013, pal["NOSE"])

    # Crop her to the field, then lay the result over the ring. In bleed mode
    # the field is a plain rounded rect, so clip to that instead.
    clip_to_squircle(motif, S, inset=field_inset,
                     radius=max(0.0, S * 0.2237 - bw) if bleed else None,
                     margin=bw if bleed else None)
    for i in range(0, S * S * 4, 4):
        a = motif[i + 3] / 255.0
        if a:
            blend(buf, i, motif[i], motif[i + 1], motif[i + 2], a)

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
