#!/usr/bin/env bash
#
# Regenerates the app icon. Renders the .iconset with the pure-Python drawer
# (no dependencies) and, on macOS, compiles it into Resources/BeamerPresenter.icns
# with the built-in `iconutil`.
#
#   ./make-icon.sh
#
set -euo pipefail
cd "$(dirname "$0")"

python3 Tools/make_icon.py

if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns Resources/AppIcon.iconset -o Resources/BeamerPresenter.icns
    echo "✓ Built Resources/BeamerPresenter.icns"
else
    echo "ℹ iconutil not found (not macOS) — committed the .iconset; the .icns is"
    echo "  built during ./build-app.sh on macOS."
fi
