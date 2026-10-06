#!/bin/bash
# Builds Deck Beat, runs the beat-lab checks, then renders every look
# headlessly in a tall and a wide frame and checks that each still was written
# and is not blank. Ends with beat-lab's contact sheet and demo clip. A few
# minutes on an M2.
#
#   bash scripts/verify.sh [parent-folder]
#
# Writes into a deck-beat-verify folder inside the parent (the temporary folder
# by default), replacing only that folder.
set -uo pipefail
PARENT="${1:-${TMPDIR:-/tmp}}"
mkdir -p "$PARENT" || exit 1
PARENT="$(cd "$PARENT" && pwd)"
cd "$(dirname "$0")/.."
OUT="$PARENT/deck-beat-verify"
rm -rf "$OUT"
mkdir -p "$OUT"

bash scripts/build.sh release > "$OUT/build.log" 2>&1 || { echo "build: FAILED (see $OUT/build.log)"; exit 1; }
APP="../dist/Deck Beat.app/Contents/MacOS/DeckBeat"
failures=0

# Song analysis, choreography plans, layout and scenes, on the CPU.
if swift run -c release beat-lab check > "$OUT/check.log" 2>&1; then
  echo "beat-lab check: passed"
else
  echo "beat-lab check: FAILED (see $OUT/check.log)"
  failures=$((failures + 1))
fi

LOOKS="screening-room night-shift ripple read-through equaliser gallery-wall light-box"
blank=0
count=0
for look in $LOOKS; do
  for format in reel landscape; do
    file="$OUT/$look-$format.png"
    "$APP" --still "$file" --look "$look" --format "$format" --time 2 >/dev/null 2>&1
    count=$((count + 1))
    # A blank frame compresses to almost nothing; a look never does.
    size=$(stat -f %z "$file" 2>/dev/null || echo 0)
    if [ "$size" -lt 20000 ]; then
      printf '%-28s FAIL %s bytes\n' "$look ($format)" "$size"
      blank=$((blank + 1))
    fi
  done
done
if [ "$blank" -eq 0 ]; then
  echo "stills: all $count rendered"
else
  echo "stills: $blank of $count failed"
  failures=$((failures + 1))
fi

# The contact sheet and demo clip need Metal; without it beat-lab says
# "skipped:" and exits 0.
if ! swift run -c release beat-lab render --out "$OUT/lab" > "$OUT/lab.log" 2>&1; then
  echo "beat-lab render: FAILED (see $OUT/lab.log)"
  failures=$((failures + 1))
elif grep -q '^skipped:' "$OUT/lab.log"; then
  echo "beat-lab render: $(grep -m 1 '^skipped:' "$OUT/lab.log")"
elif [ -s "$OUT/lab/contact-sheet.png" ] && [ -s "$OUT/lab/demo-clip.mp4" ]; then
  echo "beat-lab render: contact sheet and demo clip written"
else
  echo "beat-lab render: FAILED, output missing (see $OUT/lab.log)"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "All checks passed. Output in $OUT"
else
  echo "$failures of 3 checks failed. Output in $OUT"
  exit 1
fi
