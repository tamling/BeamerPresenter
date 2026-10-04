#!/usr/bin/env bash
#
# One-time setup: creates a self-signed code-signing certificate named
# "BeamerPresenter Dev" in your login keychain.
#
# Why: macOS remembers folder permissions (Documents/Downloads/Desktop — the
# "would like to access files in…" dialogs) per code signature. An unsigned or
# ad-hoc-signed build gets a new identity on every rebuild, so macOS asks
# again and again. With this certificate, build-app.sh signs every build with
# the *same* identity and macOS remembers your "Allow" permanently.
#
#   Tools/make-signing-cert.sh   # once
#   ./build-app.sh               # picks the identity up automatically
#
set -euo pipefail
NAME="BeamerPresenter Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "✓ Code-signing identity '$NAME' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▶︎ Creating self-signed certificate '$NAME'…"
openssl req -new -x509 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE" >/dev/null 2>&1

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/cert.p12" -passout pass:beamer >/dev/null 2>&1

echo "▶︎ Importing into the login keychain…"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P beamer -T /usr/bin/codesign >/dev/null

echo "▶︎ Trusting it for code signing (macOS may ask for your password)…"
if ! security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>/dev/null; then
    echo "  ⚠︎ Could not set trust automatically. Open Keychain Access, double-click"
    echo "    '$NAME' → Trust → Code Signing: Always Trust — then re-run this script."
fi

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "✓ '$NAME' is ready. Rebuild with ./build-app.sh — after one final"
    echo "  permission prompt, macOS remembers your folder access across rebuilds."
else
    echo "✗ The identity is not usable yet (trust missing?). See the hint above."
    exit 1
fi
