#!/usr/bin/env bash
#
# Builds a release binary with SwiftPM and wraps it into a double-clickable
# BeamerPresenter.app bundle. Run on macOS:
#
#   ./build-app.sh                 # universal (Apple Silicon + Intel) — default
#   ARCHS="arm64" ./build-app.sh   # Apple Silicon only
#   ARCHS="x86_64" ./build-app.sh  # Intel only
#
# A universal build runs on both Apple Silicon and Intel Macs from one .app.
# (The x86_64 slice cross-compiles fine on an Apple Silicon Mac.)
#
# Optional: pass a Developer ID to codesign the result:
#
#   ./build-app.sh "Developer ID Application: Your Name (TEAMID)"
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BeamerPresenter"
CONFIG="release"
ARCHS="${ARCHS:-arm64 x86_64}"        # space-separated list of architectures
SIGN_IDENTITY="${1:-}"

# A universal (multi-arch) build uses Xcode's build system (xcbuild), which is
# only in the full Xcode — not the standalone Command Line Tools. If xcode-select
# points at the CLT, fall back to the host's native arch with a clear hint.
DEVDIR="$(xcode-select -p 2>/dev/null || true)"
if [ "$(echo "$ARCHS" | wc -w | tr -d ' ')" -gt 1 ] && [[ "$DEVDIR" == *CommandLineTools* ]]; then
    echo "⚠︎ Universal build needs full Xcode (xcbuild), but xcode-select points to:"
    echo "    $DEVDIR"
    echo "  → For a universal (Intel + Apple Silicon) build, switch to Xcode once:"
    echo "      sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "  Falling back to this Mac's native arch ($(uname -m)) for now."
    ARCHS="$(uname -m)"
fi

ARCH_FLAGS=()
for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done

echo "▶︎ Building ($CONFIG, $ARCHS)…"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"

BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[ -x "$BIN" ] || { echo "✗ Binary not found at $BIN"; exit 1; }
echo "▶︎ Binary architectures: $(lipo -archs "$BIN" 2>/dev/null || echo "$ARCHS")"

echo "▶︎ Building app icon…"
python3 Tools/make_icon.py
iconutil -c icns Resources/AppIcon.iconset -o Resources/BeamerPresenter.icns

APP="build/$APP_NAME.app"
echo "▶︎ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/BeamerPresenter.icns "$APP/Contents/Resources/BeamerPresenter.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "▶︎ Codesigning with: $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --verbose "$APP"
fi

echo "✓ Built $APP"
echo "  Open it with:  open \"$APP\""
