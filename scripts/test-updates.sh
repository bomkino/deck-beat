#!/bin/bash
# Proves in-app updates end to end with a throwaway key, as CI runs it: a copy
# of Deck Beat at 9.0.0 (under another name and identifier, so the real app
# and its settings are never touched) updates itself to 9.0.1 from a feed on
# a local web server, and refuses a ZIP with one byte changed.
#
#   bash scripts/test-updates.sh
#
# Downloads Sparkle 2.10.0's tools from its GitHub release and checks their
# checksum. The key is made here and thrown away; the real key is never used.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
PORT=8765
SERVER=""
APP_PID=""
cleanup() {
  [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
  pkill -f "Deck Beat Update Test.app/Contents/MacOS/DeckBeat" 2>/dev/null || true
  [ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# Sparkle's tools, checked against the checksum of its 2.10.0 release.
curl -fsSL -o "$WORK/sparkle.tar.xz" https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz
echo "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  $WORK/sparkle.tar.xz" | shasum -a 256 -c -
mkdir -p "$WORK/sparkle" && tar -xf "$WORK/sparkle.tar.xz" -C "$WORK/sparkle"
export SPARKLE_BIN="$WORK/sparkle/bin"

# A throwaway EdDSA key, made with CryptoKit as the real one was.
cat > "$WORK/keygen.swift" <<'SWIFT'
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
keys="$(swift "$WORK/keygen.swift")"
umask 077
echo "$keys" | sed -n 1p > "$WORK/test.key"
export SPARKLE_KEY="$WORK/test.key"
export SPARKLE_PUBLIC_KEY_OVERRIDE="$(echo "$keys" | sed -n 2p)"
export BUNDLE_NAME_OVERRIDE="Deck Beat Update Test" BUNDLE_ID_OVERRIDE="dog.pitch.deckbeat.updatetest"
TEST_APP="$WORK/install/Deck Beat Update Test.app"
version() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TEST_APP/Contents/Info.plist"; }

# The copy people have: 9.0.0.
VERSION_OVERRIDE=9.0.0 bash scripts/build.sh release > "$WORK/build-old.log" 2>&1 || { cat "$WORK/build-old.log"; exit 1; }
mkdir -p "$WORK/install" && ditto "../dist/Deck Beat Update Test.app" "$WORK/old.app"
codesign -v --strict "$WORK/old.app"
# The update: 9.0.1, packed and signed as a release.
VERSION_OVERRIDE=9.0.1 bash scripts/build.sh release > "$WORK/build-new.log" 2>&1 || { cat "$WORK/build-new.log"; exit 1; }
bash scripts/pack-release.sh "$WORK/feed" > /dev/null
DOWNLOAD_URL="http://127.0.0.1:$PORT/" bash scripts/sign-release.sh "$WORK/feed"
grep -q 'sparkle:shortVersionString="9.0.1"' "$WORK/feed/appcast.xml"
grep -q 'sparkle:edSignature=' "$WORK/feed/appcast.xml"
(cd "$WORK/feed" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 > "$WORK/server.log" 2>&1) &
SERVER=$!
sleep 1

# Opens the installed copy against the test feed and waits up to `limit` seconds for `want`.
run() {
  local want="$1" limit="$2"
  STUDIO_UPDATE_TEST=1 STUDIO_UPDATE_FEED="http://127.0.0.1:$PORT/appcast.xml" "$TEST_APP/Contents/MacOS/DeckBeat" > "$WORK/app.log" 2>&1 &
  APP_PID=$!
  for _ in $(seq 1 "$limit"); do
    [ "$(version)" = "$want" ] && break
    sleep 1
  done
  kill "$APP_PID" 2>/dev/null || true
  pkill -f "Deck Beat Update Test.app/Contents/MacOS/DeckBeat" 2>/dev/null || true
  APP_PID=""
  sleep 2
}

# 1. A signed update installs itself.
ditto "$WORK/old.app" "$TEST_APP"
run 9.0.1 90
got="$(version)"
if [ "$got" != "9.0.1" ]; then
  echo "update: FAILED, still $got"; cat "$WORK/app.log" "$WORK/server.log"; exit 1
fi
codesign -v --strict "$TEST_APP"
echo "update: 9.0.0 updated itself to 9.0.1 from the signed feed"

# 2. The same update with one byte changed is refused.
rm -rf "$TEST_APP" && ditto "$WORK/old.app" "$TEST_APP"
ZIP="$(ls "$WORK/feed"/*.zip)"
size="$(stat -f %z "$ZIP")"
offset=$((size / 2))
byte="$(dd if="$ZIP" bs=1 skip="$offset" count=1 2>/dev/null | xxd -p)"
printf "$(printf '\\x%02x' $(( (0x$byte + 1) % 256 )))" | dd of="$ZIP" bs=1 seek="$offset" count=1 conv=notrunc 2>/dev/null
before="$(grep -c "GET /$(basename "$ZIP")" "$WORK/server.log" || true)"
run 9.0.1 40
got="$(version)"
if [ "$got" != "9.0.0" ]; then
  echo "tampered update: FAILED, it installed $got"; exit 1
fi
# It must have fetched the tampered ZIP and turned it down, not just never looked.
after="$(grep -c "GET /$(basename "$ZIP")" "$WORK/server.log" || true)"
if [ "$after" -le "$before" ]; then
  echo "tampered update: inconclusive, the copy never fetched the ZIP"; cat "$WORK/server.log"; exit 1
fi
echo "tampered update: fetched and refused, the copy stays at 9.0.0"
grep -i "signature\|error" "$WORK/app.log" | head -5 || true
