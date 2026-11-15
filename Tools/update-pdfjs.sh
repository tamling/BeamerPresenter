#!/usr/bin/env bash
#
# Verifies — or refreshes — the pdf.js bundles vendored under
# Linux/ui/vendor/pdfjs, against the facts recorded beside them in VERSION.
#
#   Tools/update-pdfjs.sh                 # check the working tree against VERSION
#   Tools/update-pdfjs.sh 4.11.0          # fetch that release and rewrite VERSION
#
# Checking needs nothing but sha256sum. Refreshing needs curl and tar, and
# downloads from the npm registry.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR="Linux/ui/vendor/pdfjs"
VERSION_FILE="$DIR/VERSION"
[ -f "$VERSION_FILE" ] || { echo "✗ $VERSION_FILE is missing" >&2; exit 1; }

# Read the recorded facts. Only the keys below are taken, so a stray line in the
# file cannot set a variable in this script.
read_key() { sed -n "s/^$1=//p" "$VERSION_FILE" | head -1; }
PACKAGE="$(read_key package)"
VERSION="$(read_key version)"
FLAVOUR="$(read_key flavour)"
WANT_PDF="$(read_key sha256_pdf)"
WANT_WORKER="$(read_key sha256_worker)"

sum() { sha256sum "$1" | cut -d' ' -f1; }

check() {
    local ok=0
    for pair in "pdf.min.mjs:$WANT_PDF" "pdf.worker.min.mjs:$WANT_WORKER"; do
        local file="${pair%%:*}" want="${pair##*:}" got
        if [ ! -f "$DIR/$file" ]; then
            echo "✗ $DIR/$file is missing" >&2; ok=1; continue
        fi
        got="$(sum "$DIR/$file")"
        if [ "$got" = "$want" ]; then
            echo "✓ $file matches VERSION ($PACKAGE $VERSION, $FLAVOUR)"
        else
            echo "✗ $file does not match VERSION" >&2
            echo "    recorded: $want" >&2
            echo "    on disk:  $got" >&2
            ok=1
        fi
    done
    return $ok
}

if [ $# -eq 0 ]; then
    check
    exit $?
fi

NEW="$1"
case "$NEW" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "✗ '$NEW' is not a version like 4.11.0" >&2; exit 1 ;;
esac

TARBALL="https://registry.npmjs.org/$PACKAGE/-/$PACKAGE-$NEW.tgz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▶︎ Fetching $PACKAGE $NEW"
curl -sSL -o "$TMP/pdfjs.tgz" "$TARBALL"
# Extracted into a scratch directory first: a tarball is untrusted input, and
# nothing should land in the repo before its contents have been seen.
tar -xzf "$TMP/pdfjs.tgz" -C "$TMP" \
    "package/$FLAVOUR/pdf.min.mjs" "package/$FLAVOUR/pdf.worker.min.mjs"

NEW_PDF="$(sum "$TMP/package/$FLAVOUR/pdf.min.mjs")"
NEW_WORKER="$(sum "$TMP/package/$FLAVOUR/pdf.worker.min.mjs")"

cp "$TMP/package/$FLAVOUR/pdf.min.mjs" "$TMP/package/$FLAVOUR/pdf.worker.min.mjs" "$DIR/"

cat > "$VERSION_FILE" <<EOF
# What is vendored in this directory, in a form a tool can read.
# Refresh and verify with Tools/update-pdfjs.sh; the same facts are explained in
# prose in Linux/README.md.
package=$PACKAGE
version=$NEW
flavour=$FLAVOUR
tarball=$TARBALL
sha256_pdf=$NEW_PDF
sha256_worker=$NEW_WORKER
EOF

echo "✓ Vendored $PACKAGE $NEW and rewrote $VERSION_FILE"
echo
echo "  Still to do by hand:"
echo "    - update the version in Linux/README.md (prose, checksums and layout note)"
echo "    - open a deck in the Linux app and check that it renders"
