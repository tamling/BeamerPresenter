#!/usr/bin/env bash
#
# End-to-end test of the scanner, through the TestHost's --scan mode:
#
#   Scripts/scan-test.sh build/TestHost
#
# Makes a fixture music folder, scans it into a cache again and again while
# the folder changes, and stops at the first failure with exit status 1. Works
# in a temporary folder that it deletes at the end.
#
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <path/to/TestHost>" >&2
    exit 1
fi
HOST="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/make-fixtures.py"
T="$(mktemp -d)"
LOCKER=""
cleanup() {
    if [ -n "$LOCKER" ]; then kill "$LOCKER" 2>/dev/null || true; fi
    rm -rf "$T"
}
trap cleanup EXIT
MUSIC="$T/music"
CACHE="$T/cache"

fail() {
    echo "✗ $*" >&2
    exit 1
}

# scan <folder> <word>…: scans <folder> into the cache; each word must be in the summary.
scan() {
    local folder="$1" line word
    shift
    line="$("$HOST" --scan "$folder" --cache "$CACHE")" || fail "TestHost --scan exited with status $?"
    echo "  $line"
    for word in "$@"; do
        [[ " $line " == *" $word "* ]] || fail "expected $word"
    done
}

# expect_covers <n>: covers/ holds exactly n files.
expect_covers() {
    local count
    count="$(find "$CACHE/covers" -type f | wc -l | tr -d ' ')"
    [ "$count" = "$1" ] || fail "covers/ holds $count files, not $1"
}

checksum() {
    if command -v shasum >/dev/null; then shasum -a 256 "$1"; else sha256sum "$1"; fi
}

# Every folder and every file (hidden ones too) of the music folder, files with their checksums.
manifest() {
    (
        cd "$MUSIC"
        find . -type d | LC_ALL=C sort | sed 's/^/folder /'
        find . -type f | LC_ALL=C sort | while IFS= read -r file; do checksum "$file"; done
    )
}

echo "▶︎ 1. Fixtures"
python3 "$FIXTURES" mp3 "$MUSIC" >/dev/null
manifest >"$T/before"
echo "  $(grep -vc '^folder ' "$T/before") files"

echo "▶︎ 2. First scan: three albums from seven files; the hidden one is skipped"
scan "$MUSIC" outcome=complete albums=3 files=7 new=3
expect_covers 3
if command -v sips >/dev/null; then
    # Square JPEGs: the 1000×800 cover scaled down to 640, the 64×48 ones not scaled up.
    sizes="$(for cover in "$CACHE"/covers/*; do
        sips -g format -g pixelWidth -g pixelHeight "$cover" |
            awk '$1 == "format:" { f = $2 } $1 == "pixelWidth:" { w = $2 } $1 == "pixelHeight:" { h = $2 }
                 END { print f, w "x" h }'
    done | LC_ALL=C sort -u | tr '\n' ';')"
    echo "  covers: $sizes"
    [ "$sizes" = "jpeg 48x48;jpeg 640x640;" ] || fail "covers should be jpeg 48x48 and 640x640"
fi

echo "▶︎ 3. Nothing changed: nothing new"
scan "$MUSIC" outcome=complete albums=3 files=7 new=0

echo "▶︎ 4. A new album; a track with another title but loose.mp3's picture joins that album"
python3 "$FIXTURES" mp3-one "$MUSIC/C/01.mp3" "Album C" 255,160,0 >/dev/null
python3 "$FIXTURES" mp3-one "$MUSIC/C/02.mp3" "Album D" 30,200,30 >/dev/null
scan "$MUSIC" outcome=complete albums=4 files=9 new=1
expect_covers 4

echo "▶︎ 5. The only track of album B deleted: album and cover go"
rm "$MUSIC/B/01.mp3"
scan "$MUSIC" outcome=complete albums=3 files=8 new=0
expect_covers 3

echo "▶︎ 6. Music folder missing: the cache stays as it is"
cp "$CACHE/index.json" "$T/index-before.json"
scan "$T/missing" outcome=unavailable
cmp -s "$CACHE/index.json" "$T/index-before.json" || fail "index.json changed"
expect_covers 3
[ ! -e "$T/missing" ] || fail "the scan made the missing folder"

echo "▶︎ 7. Two scans at once on the same cache"
for round in 1 2 3 4 5; do
    # Without an index both scans have every file to read, so they overlap.
    rm "$CACHE/index.json"
    "$HOST" --scan "$MUSIC" --cache "$CACHE" >"$T/scan-1" &
    first=$!
    "$HOST" --scan "$MUSIC" --cache "$CACHE" >"$T/scan-2" &
    second=$!
    wait "$first" || fail "round $round: a TestHost --scan failed"
    wait "$second" || fail "round $round: a TestHost --scan failed"
    echo "  round $round: $(tr '\n' ' ' <"$T/scan-1")| $(tr '\n' ' ' <"$T/scan-2")"
    grep -Eq '^outcome=(complete|busy) ' "$T/scan-1" || fail "round $round: unexpected outcome"
    grep -Eq '^outcome=(complete|busy) ' "$T/scan-2" || fail "round $round: unexpected outcome"
    grep -q '^outcome=complete ' "$T/scan-1" "$T/scan-2" || fail "round $round: no scan completed"
    python3 -m json.tool "$CACHE/index.json" >/dev/null || fail "round $round: index.json is not valid JSON"
done
# While another process holds the lock, a scan does nothing.
python3 -c '
import fcntl, sys, time
lock = open(sys.argv[1], "a")
fcntl.flock(lock, fcntl.LOCK_EX)
print("locked", flush=True)
time.sleep(60)
' "$CACHE/scan.lock" >"$T/locker" &
LOCKER=$!
for _ in $(seq 100); do
    if grep -q locked "$T/locker"; then break; fi
    sleep 0.1
done
grep -q locked "$T/locker" || fail "could not take the lock for the test"
cp "$CACHE/index.json" "$T/index-before.json"
scan "$MUSIC" outcome=busy
cmp -s "$CACHE/index.json" "$T/index-before.json" || fail "a busy scan changed index.json"
kill "$LOCKER"
wait "$LOCKER" 2>/dev/null || true
LOCKER=""
scan "$MUSIC" outcome=complete albums=3 files=8 new=0
expect_covers 3

echo "▶︎ 8. The music folder is as the steps left it: the scans only read"
manifest >"$T/after"
grep -v -e ' \./B/01\.mp3$' "$T/before" >"$T/before-kept"
grep -v -e '^folder \./C$' -e ' \./C/0[12]\.mp3$' "$T/after" >"$T/after-kept"
diff "$T/before-kept" "$T/after-kept" || fail "the music folder changed"

echo "✓ scan test passed"
