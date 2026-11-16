#!/usr/bin/env bash
#
# Rebuilds docs/banner.png — the strip at the top of the README.
#
#   Tools/make_banner.sh
#
# The app icon comes from the same renderer the app's icons do, so the banner
# cannot fall behind the brand the way it did when it was a hand-made PNG that
# nothing regenerated. The type is the app's own: Space Grotesk for the name,
# JetBrains Mono for the strapline, IBM Plex for the platforms.
#
# Needs ImageMagick, which is why this is a separate script rather than part of
# make-icon.sh: the icons must be buildable with nothing but Python, and they
# are. Nobody has to run this to build or ship the app — if ImageMagick is not
# installed, the committed banner is used as it is, and Tools/check_colors.py
# still fails if it has drifted away from the brand.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v convert >/dev/null 2>&1 || {
    echo "✗ ImageMagick's 'convert' is not installed — nothing to do." >&2
    exit 1
}

BRAND="$(sed -n 's/^BRAND = "\(#[0-9A-Fa-f]\{6\}\)"/\1/p' Tools/make_icon.py)"
[ -n "$BRAND" ] || { echo "✗ could not read BRAND from Tools/make_icon.py" >&2; exit 1; }
echo "▶︎ brand $BRAND"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The icon, from the renderer rather than from a file lying around.
python3 - "$TMP/mark.png" <<'PY'
import sys, os
sys.path.insert(0, os.path.join(os.getcwd(), "Tools"))
from make_icon import render, write_png
write_png(sys.argv[1], 256, 256, render(256))
PY

F=Resources/Fonts
convert -size 1400x420 xc:"#15171C" \
    \( "$TMP/mark.png" -resize 208x208 \) -geometry +72+106 -composite \
    -font "$F/SpaceGrotesk-Bold.ttf"    -pointsize 76 -fill "#E9ECF0" \
        -annotate +330+185 "BeamerPresenter" \
    -font "$F/JetBrainsMono-Bold.ttf"   -pointsize 27 -fill "#FFA0A8" \
        -kerning 7 -annotate +334+243 "PRESENT · NOTES · TWO SCREENS" \
    -font "$F/IBMPlexSans-Regular.ttf"  -pointsize 27 -fill "#929AA5" \
        -kerning 0 -annotate +334+296 "macOS · iPadOS · Linux" \
    -depth 8 -strip \
    docs/banner.png

echo "✓ wrote docs/banner.png"
