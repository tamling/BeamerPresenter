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

# Stamp a combined build ID ("<YYMMDD>-<commit-as-decimal>") into BuildInfo.swift.
echo "▶︎ Stamping build info…"
DATE6="$(date -u +%y%m%d)"
HEX="$(git rev-parse --short=6 HEAD 2>/dev/null || echo 0)"
BUILD_ID="${DATE6}-$(printf '%d' "0x$HEX" 2>/dev/null || echo 0)"
cat > Sources/BeamerPresenter/BuildInfo.swift <<EOF
// Generated at build time by build-app.sh — do not edit.
enum BuildInfo {
    static let id = "$BUILD_ID"
}
EOF

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
# Bundle the Night Console fonts (registered via ATSApplicationFontsPath = Fonts).
[ -d Resources/Fonts ] && cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -z "$SIGN_IDENTITY" ]; then
    # macOS remembers folder permissions (TCC) per code signature — a *stable*
    # identity stops the repeated "access files in your Documents folder"
    # prompts after rebuilds. Prefer a real identity, then the self-signed one
    # from Tools/make-signing-cert.sh.
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    for candidate in "Developer ID Application" "Apple Development" "BeamerPresenter Dev"; do
        match="$(echo "$IDENTITIES" | grep "$candidate" | head -1 || true)"
        if [ -n "$match" ]; then
            SIGN_IDENTITY="$(echo "$match" | sed 's/.*"\(.*\)".*/\1/')"
            break
        fi
    done
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "▶︎ Codesigning with: $SIGN_IDENTITY"
    # Self-signed identities can't get an Apple timestamp — fall back quietly.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP" 2>/dev/null \
        || codesign --force --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --verbose "$APP"
else
    echo "▶︎ Codesigning ad-hoc (no identity found)."
    echo "  ⚠︎ macOS will re-ask for Documents/Downloads access after every"
    echo "    rebuild, because ad-hoc signatures change each build. Create a"
    echo "    stable identity once:  Tools/make-signing-cert.sh"
    codesign --force --sign - "$APP"
fi

echo "✓ Built $APP"
echo "  Open it with:  open \"$APP\""
