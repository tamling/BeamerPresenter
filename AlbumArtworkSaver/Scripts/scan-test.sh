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
    # A step that failed may have left a folder that cannot be listed.
    chmod -R u+rwX "$T" 2>/dev/null || true
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

# album_of <path>: the album the index gives the music file <path> ("-" for none).
album_of() {
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["files"][sys.argv[2]].get("album", "-"))' \
        "$CACHE/index.json" "$1"
}

# modified_of <path>: the modification date the index has for the music file <path>.
modified_of() {
    python3 -c 'import json, sys; print(repr(json.load(open(sys.argv[1]))["files"][sys.argv[2]]["stamp"]["modified"]))' \
        "$CACHE/index.json" "$1"
}

# expect_album <id>: the index knows the album <id>, and its cover is there.
expect_album() {
    python3 -c 'import json, sys; sys.exit(sys.argv[2] not in json.load(open(sys.argv[1]))["albums"])' \
        "$CACHE/index.json" "$1" || fail "album $1 is not in the index"
    [ -f "$CACHE/covers/$1.jpg" ] || fail "the cover of album $1 is gone"
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
scan "$MUSIC" outcome=complete albums=3 files=7 new=3 read=7
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

echo "▶︎ 3. Nothing changed: no file is read again"
scan "$MUSIC" outcome=complete albums=3 files=7 new=0 read=0

echo "▶︎ 4. A new album; a track with another title but loose.mp3's picture joins that album"
python3 "$FIXTURES" mp3-one "$MUSIC/C/01.mp3" "Album C" 255,160,0 >/dev/null
python3 "$FIXTURES" mp3-one "$MUSIC/C/02.mp3" "Album D" 30,200,30 >/dev/null
scan "$MUSIC" outcome=complete albums=4 files=9 new=1 read=2
expect_covers 4

echo "▶︎ 5. The only track of album B deleted: album and cover go"
rm "$MUSIC/B/01.mp3"
scan "$MUSIC" outcome=complete albums=3 files=8 new=0 read=0
expect_covers 3

echo "▶︎ 6. Music folder missing: the cache stays as it is"
cp "$CACHE/index.json" "$T/index-before.json"
scan "$T/missing" outcome=unavailable read=0
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
scan "$MUSIC" outcome=busy read=0
cmp -s "$CACHE/index.json" "$T/index-before.json" || fail "a busy scan changed index.json"
kill "$LOCKER"
wait "$LOCKER" 2>/dev/null || true
LOCKER=""
scan "$MUSIC" outcome=complete albums=3 files=8 new=0 read=0
expect_covers 3

echo "▶︎ 8. An unreadable file is kept, read again later, and removes nothing meanwhile"
# C/01.mp3 is the only track of album C. Changed and unreadable, it must not be
# recorded as a file without a cover, which would orphan album C and delete it.
album_c="$(album_of C/01.mp3)"
[ "$album_c" != "-" ] || fail "C/01.mp3 has no album"
modified="$(modified_of C/01.mp3)"
touch "$MUSIC/C/01.mp3"
chmod 000 "$MUSIC/C/01.mp3"
if [ -r "$MUSIC/C/01.mp3" ]; then
    echo "  skipped: this user can read a file with mode 000 (root?)"
else
    scan "$MUSIC" outcome=incomplete albums=3 files=8 new=0 read=0
    [ "$(album_of C/01.mp3)" = "$album_c" ] || fail "C/01.mp3 lost its album"
    [ "$(modified_of C/01.mp3)" = "$modified" ] || fail "the unreadable C/01.mp3 was recorded"
    expect_album "$album_c"
    expect_covers 3
fi
chmod 644 "$MUSIC/C/01.mp3"
scan "$MUSIC" outcome=complete albums=3 files=8 new=0 read=1
[ "$(modified_of C/01.mp3)" != "$modified" ] || fail "C/01.mp3 was not read again"
[ "$(album_of C/01.mp3)" = "$album_c" ] || fail "C/01.mp3 lost its album"
expect_album "$album_c"
expect_covers 3

echo "▶︎ 9. A subfolder that cannot be listed: its files count as missed, not gone, and nothing is removed"
album_a="$(album_of A/01.mp3)"
[ "$album_a" != "-" ] || fail "A/01.mp3 has no album"
chmod 000 "$MUSIC/A"
if ls "$MUSIC/A" >/dev/null 2>&1; then
    echo "  skipped: this user can list a folder with mode 000 (root?)"
else
    scan "$MUSIC" outcome=incomplete albums=3 files=8 new=0 read=0
    [ "$(album_of A/01.mp3)" = "$album_a" ] || fail "A/01.mp3 was forgotten"
    expect_album "$album_a"
    expect_covers 3
fi
chmod 755 "$MUSIC/A"
scan "$MUSIC" outcome=complete albums=3 files=8 new=0 read=0
expect_album "$album_a"
expect_covers 3

echo "▶︎ 10. The track a cover came from, tagged with another picture: the cover changes"
# C/01.mp3 is album C's only track, so its cover came from it.
cover_c="$CACHE/covers/$album_c.jpg"
[ -f "$cover_c" ] || fail "album C has no cover"
cover_before="$(checksum "$cover_c" | cut -d ' ' -f 1)"
python3 "$FIXTURES" mp3-one "$MUSIC/C/01.mp3" "Album C" 0,90,255 >/dev/null
scan "$MUSIC" outcome=complete albums=3 files=8 new=0 read=1
[ "$(album_of C/01.mp3)" = "$album_c" ] || fail "C/01.mp3 lost its album"
expect_album "$album_c"
expect_covers 3
[ "$(checksum "$cover_c" | cut -d ' ' -f 1)" != "$cover_before" ] || fail "the cover of album C did not change"
scan "$MUSIC" outcome=complete albums=3 files=8 new=0 read=0

echo "▶︎ 11. An empty folder in its place (a mount point without its disk): the cache stays as it is"
mkdir "$T/empty-mount"
cp "$CACHE/index.json" "$T/index-before.json"
find "$CACHE/covers" -type f | LC_ALL=C sort >"$T/covers-before"
scan "$T/empty-mount" outcome=incomplete albums=3 files=8 new=0 read=0
cmp -s "$CACHE/index.json" "$T/index-before.json" || fail "index.json changed"
find "$CACHE/covers" -type f | LC_ALL=C sort | diff "$T/covers-before" - || fail "covers/ changed"
[ -z "$(ls -A "$T/empty-mount")" ] || fail "the scan wrote into the folder"

echo "▶︎ 12. The music folder is as the steps left it: the scans only read"
manifest >"$T/after"
grep -v -e ' \./B/01\.mp3$' "$T/before" >"$T/before-kept"
grep -v -e '^folder \./C$' -e ' \./C/0[12]\.mp3$' "$T/after" >"$T/after-kept"
diff "$T/before-kept" "$T/after-kept" || fail "the music folder changed"

echo "✓ scan test passed"
