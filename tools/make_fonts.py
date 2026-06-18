#!/usr/bin/env python3
"""Fetch the three Night Console typefaces and instantiate the exact static
weights the app's `Font` helper references, writing them into both the iOS and
macOS font folders. Run once (needs network + fonttools):

    pip install fonttools brotli
    python3 tools/make_fonts.py

Typefaces (SIL OFL): Space Grotesk, IBM Plex Sans, JetBrains Mono.
"""

import os
import urllib.request
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

RAW = "https://github.com/google/fonts/raw/main/ofl"
SRC = {
    "spacegrotesk":  f"{RAW}/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf",
    "jetbrainsmono": f"{RAW}/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf",
    "ibmplexsans":   f"{RAW}/ibmplexsans/IBMPlexSans%5Bwdth,wght%5D.ttf",
}

# (source key, axes, PostScript name) — the PS name must match Font.custom(...).
TARGETS = [
    ("spacegrotesk",  {"wght": 700},               "SpaceGrotesk-Bold"),
    ("ibmplexsans",   {"wght": 400, "wdth": 100},  "IBMPlexSans-Regular"),
    ("ibmplexsans",   {"wght": 500, "wdth": 100},  "IBMPlexSans-Medium"),
    ("ibmplexsans",   {"wght": 600, "wdth": 100},  "IBMPlexSans-SemiBold"),
    ("jetbrainsmono", {"wght": 400},               "JetBrainsMono-Regular"),
    ("jetbrainsmono", {"wght": 700},               "JetBrainsMono-Bold"),
]

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT_DIRS = [
    os.path.join(ROOT, "iOS", "BeamerPresenter", "Fonts"),
    os.path.join(ROOT, "Resources", "Fonts"),
]


def set_names(font, ps):
    family, _, sub = ps.partition("-")
    spaced = family.replace("Grotesk", " Grotesk").replace("PlexSans", " Plex Sans") \
                   .replace("BrainsMono", "Brains Mono")
    name = font["name"]
    for nid, val in [(1, spaced), (2, sub), (4, ps.replace("-", " ")), (6, ps)]:
        name.setName(val, nid, 3, 1, 0x409)   # Windows / Unicode
        name.setName(val, nid, 1, 0, 0)        # Macintosh / Roman


def main():
    cache = {}
    for d in OUT_DIRS:
        os.makedirs(d, exist_ok=True)

    for key, url in SRC.items():
        path = f"/tmp/_{key}.ttf"
        if not os.path.exists(path):
            print(f"↓ {key}")
            urllib.request.urlretrieve(url, path)
        cache[key] = path

    for key, axes, ps in TARGETS:
        font = TTFont(cache[key])
        instantiateVariableFont(font, axes, inplace=True, updateFontNames=False)
        set_names(font, ps)
        for d in OUT_DIRS:
            out = os.path.join(d, ps + ".ttf")
            font.save(out)
        print(f"✓ {ps}.ttf")

    print("done →", ", ".join(OUT_DIRS))


if __name__ == "__main__":
    main()
