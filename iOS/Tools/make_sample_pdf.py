#!/usr/bin/env python3
"""Dependency-free generator for a small sample slide deck (16:9 PDF), bundled so
the iPad app has something to present out of the box."""

import os


def content(i: int, n: int) -> str:
    parts = [
        "0.33 0.41 1.0 rg 0 470 960 70 re f",                       # indigo top bar
        "BT /F1 28 Tf 1 1 1 rg 40 492 Td (BeamerPresenter - Sample Deck) Tj ET",
        f"BT /F1 96 Tf 0.10 0.10 0.12 rg 40 300 Td (Slide {i + 1}) Tj ET",
        f"BT /F1 24 Tf 0.35 0.35 0.40 rg 40 250 Td (Page {i + 1} of {n}) Tj ET",
    ]
    bullets = ["Tap the right / left half to navigate",
               "Swipe left or right between slides",
               "Turn on the pen and draw on the slide"]
    y = 180
    for b in bullets:
        parts.append(f"BT /F1 22 Tf 0.2 0.2 0.2 rg 60 {y} Td (- {b}) Tj ET")
        y -= 36
    return "\n".join(parts)


def make_pdf(path: str, count: int):
    n = count
    content_start, page_start = 4, 4 + n
    objs: dict[int, bytes] = {}
    kids = " ".join(f"{page_start + i} 0 R" for i in range(n))
    objs[1] = b"<< /Type /Catalog /Pages 2 0 R >>"
    objs[2] = f"<< /Type /Pages /Kids [{kids}] /Count {n} >>".encode()
    objs[3] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>"
    for i in range(n):
        stream = content(i, n).encode("latin-1")
        objs[content_start + i] = b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream"
        objs[page_start + i] = (
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 960 540] "
            "/Resources << /Font << /F1 3 0 R >> >> "
            f"/Contents {content_start + i} 0 R >>").encode()

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    last = page_start + n - 1
    offsets: dict[int, int] = {}
    for num in range(1, last + 1):
        offsets[num] = len(out)
        out += f"{num} 0 obj\n".encode() + objs[num] + b"\nendobj\n"

    xref = len(out)
    out += f"xref\n0 {last + 1}\n".encode()
    out += b"0000000000 65535 f \n"
    for num in range(1, last + 1):
        out += f"{offsets[num]:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {last + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF".encode()

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(out)
    print(f"✓ wrote {path} ({n} slides, {len(out)} bytes)")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    make_pdf(os.path.join(here, "..", "BeamerPresenter", "Resources", "sample.pdf"), count=6)
