#!/bin/bash
# Packs the built app for a release: a disk image for people, a ZIP for the
# in-app updater, their checksums, and an appcast.xml that offers no update
# until scripts/sign-release.sh signs it.
#
#   bash scripts/pack-release.sh <out-dir>
#
# Run after `bash scripts/build.sh release`. The release workflow runs both.
# See docs/UPDATES.md.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: pack-release.sh <out-dir>}"
REPO="bomkino/deck-beat"
BUNDLE="${BUNDLE_NAME_OVERRIDE:-Deck Beat}"
STEM="Deck-Beat"
SRC="../dist/$BUNDLE.app"
[ -d "$SRC" ] || { echo "build $SRC first"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SRC/Contents/Info.plist")"
DMG="$STEM-$VERSION-macOS-arm64.dmg"
ZIP="$STEM-$VERSION-macOS-arm64.zip"

mkdir -p "$OUT"
rm -f "$OUT/$DMG" "$OUT/$ZIP" "$OUT/appcast.xml" "$OUT/SHA256SUMS.txt"
codesign -v --strict "$SRC"
stage="$(mktemp -d)"
ditto "$SRC" "$stage/$BUNDLE.app"
ln -s /Applications "$stage/Applications"
# hdiutil sometimes finds the volume busy on a fresh machine; it gets three tries.
for try in 1 2 3; do
  hdiutil create -quiet -volname "$BUNDLE" -srcfolder "$stage" -ov -format UDZO -fs HFS+ "$OUT/$DMG" && break
  [ "$try" = 3 ] && exit 1
  sleep 5
done
rm -rf "$stage"
# The updater takes a ZIP: nothing is mounted, so macOS never offers to
# "install" a disk image in the middle of an update.
ditto -c -k --sequesterRsrc --keepParent "$SRC" "$OUT/$ZIP"
(cd "$OUT" && shasum -a 256 "$DMG" "$ZIP" > SHA256SUMS.txt)
# A feed with nothing in it: installed copies read it and stay as they are.
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Deck Beat</title>
    <link>https://github.com/$REPO/releases</link>
    <description>Deck Beat $VERSION, not yet signed for in-app updates.</description>
  </channel>
</rss>
XML
ls -1 "$OUT"
