#!/usr/bin/env python3
"""Generates the Linux app icon into src-tauri/icons/.

Reuses the dependency-free renderer in Tools/make_icon.py, so macOS and
Linux share one icon design (the Night Console play mark)."""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "Tools"))
from make_icon import render, write_png  # noqa: E402

icons = os.path.join(HERE, "src-tauri", "icons")
os.makedirs(icons, exist_ok=True)

# icon.png (512) plus the sizes the Tauri bundler expects.
for name, px in [("icon.png", 512), ("32x32.png", 32),
                 ("128x128.png", 128), ("128x128@2x.png", 256)]:
    print(f"  rendering {name} ({px}px)")
    write_png(os.path.join(icons, name), px, px, render(px))
print(f"✓ wrote {icons}")
