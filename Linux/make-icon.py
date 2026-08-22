#!/usr/bin/env python3
"""Generates the Linux app icon (Night Console style, "two screens" motif)
into src-tauri/icons/icon.png. Requires Pillow."""

from PIL import Image, ImageDraw
from pathlib import Path

S = 512
BASE = (0x15, 0x17, 0x1C, 255)      # Theme.base
KEY = (0x23, 0x27, 0x2E, 255)       # Theme.key
ACCENT = (0xC7, 0xF2, 0x4E, 255)    # Theme.accent (electric lime)

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# Dark rounded-square plate.
d.rounded_rectangle([16, 16, S - 16, S - 16], radius=110, fill=BASE)

# Back screen (audience): lime outline, slightly up-left.
d.rounded_rectangle([120, 138, 356, 306], radius=26, outline=ACCENT, width=14)

# Front screen (console): filled key surface with lime outline, down-right.
d.rounded_rectangle([188, 226, 424, 394], radius=26, fill=KEY,
                    outline=ACCENT, width=14)

# A "slide" line on the front screen.
d.rounded_rectangle([228, 286, 384, 306], radius=10, fill=ACCENT)

icons = Path(__file__).parent / "src-tauri" / "icons"
icons.mkdir(parents=True, exist_ok=True)
img.save(icons / "icon.png")
# The sizes the Tauri bundler expects for the .deb / desktop entry.
for name, px in [("32x32.png", 32), ("128x128.png", 128), ("128x128@2x.png", 256)]:
    img.resize((px, px), Image.LANCZOS).save(icons / name)
print(f"wrote {icons}/icon.png + 32/128/256 sizes")
