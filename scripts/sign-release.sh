#!/bin/bash
# Signs a release for the in-app updater: writes an appcast.xml that offers the
# release's ZIP, with the ZIP's EdDSA signature, so installed copies of Deck
# Beat update themselves to it. The release workflow runs it on every release,
# with the key from its secret; it also runs on a Mac that holds the key.
#
#   bash scripts/sign-release.sh <folder> [update-notes.md]    a folder from pack-release.sh: sign in place
#   bash scripts/sign-release.sh <version> [update-notes.md]   a published release: fetch, sign, upload
#
# Before anything is written, the signature is checked with the public key
# inside the app in the ZIP, as Sparkle will check it: a wrong key fails here.
# For a published release, the ZIP is downloaded with gh, checked against the
# release's SHA256SUMS.txt, and the signed appcast.xml replaces the release's.
# See docs/UPDATES.md.
#
# Environment:
#   SPARKLE_BIN   Sparkle's tools (default ~/Library/Application Support/pitch.dog/Sparkle/2.10.0/bin)
#   SPARKLE_KEY   the private EdDSA key file (default …/pitch.dog/Release Keys/sparkle-ed25519-private.key)
#   DOWNLOAD_URL  where the ZIP is served (default: the GitHub release for its version)
set -euo pipefail
cd "$(dirname "$0")/.."
WHAT="${1:?usage: sign-release.sh <version|folder> [update-notes.md]}"; NOTES="${2:-}"
SUPPORT="$HOME/Library/Application Support/pitch.dog"
SPARKLE_BIN="${SPARKLE_BIN:-$SUPPORT/Sparkle/2.10.0/bin}"
SPARKLE_KEY="${SPARKLE_KEY:-$SUPPORT/Release Keys/sparkle-ed25519-private.key}"
REPO="bomkino/deck-beat"
STEM="Deck-Beat"
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "Sparkle tools missing at $SPARKLE_BIN"; exit 1; }
[ -f "$SPARKLE_KEY" ] || { echo "signing key missing at $SPARKLE_KEY"; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [ -d "$WHAT" ]; then
  DIR="$WHAT"
  ZIP="$(cd "$DIR" && ls "$STEM"-*-macOS-arm64.zip | head -1)"
  [ -n "$ZIP" ] || { echo "no $STEM ZIP in $DIR"; exit 1; }
  VERSION="${ZIP#"$STEM"-}"; VERSION="${VERSION%-macOS-arm64.zip}"
  (cd "$DIR" && grep " $ZIP\$" SHA256SUMS.txt | shasum -a 256 -c - >/dev/null) || { echo "$ZIP doesn't match SHA256SUMS.txt"; exit 1; }
else
  VERSION="${WHAT#v}"
  DIR="$work/release"
  ZIP="$STEM-$VERSION-macOS-arm64.zip"
  gh release download "v$VERSION" -R "$REPO" -p "$ZIP" -p SHA256SUMS.txt -D "$DIR"
  (cd "$DIR" && grep " $ZIP\$" SHA256SUMS.txt | shasum -a 256 -c - >/dev/null) || { echo "$ZIP doesn't match SHA256SUMS.txt"; exit 1; }
fi
DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/$REPO/releases/download/v$VERSION/}"

# The app inside the ZIP: its version, and the public key it trusts.
ditto -x -k "$DIR/$ZIP" "$work/app"
PLIST="$(ls -d "$work"/app/*.app | head -1)/Contents/Info.plist"
SHORT="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"
PUBLIC="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST")"
[ "$SHORT" = "$VERSION" ] || { echo "the ZIP holds $SHORT, not $VERSION"; exit 1; }

# generate_appcast signs every archive in its folder, so it works in its own.
mkdir -p "$work/cast"
cp "$DIR/$ZIP" "$work/cast/"
# Notes shown in the update window: a Markdown file named like the archive.
if [ -n "$NOTES" ]; then cp "$NOTES" "$work/cast/${ZIP%.zip}.md"; fi
"$SPARKLE_BIN/generate_appcast" --ed-key-file "$SPARKLE_KEY" --download-url-prefix "$DOWNLOAD_URL" \
  --link "https://github.com/$REPO/releases" --embed-release-notes --maximum-versions 1 -o "$work/appcast.xml" "$work/cast" \
  > "$work/generate.log" || { cat "$work/generate.log"; echo "generate_appcast failed"; exit 1; }
grep -Eq "sparkle:shortVersionString(>|=\")${VERSION}[<\"]" "$work/appcast.xml" || { echo "appcast.xml doesn't name $VERSION"; exit 1; }
grep -q "url=\"$DOWNLOAD_URL$ZIP\"" "$work/appcast.xml" || { echo "appcast.xml doesn't point at $DOWNLOAD_URL$ZIP"; exit 1; }
SIG="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$work/appcast.xml" | head -1)"
# Sparkle signs only with the key whose public half is in the app; with any
# other key it warns and leaves the feed unsigned.
if [ -z "$SIG" ]; then
  grep -i "warning\|error" "$work/generate.log" || true
  echo "the app wouldn't accept this feed: Sparkle left it unsigned. Is the key the one whose public half is $PUBLIC?"; exit 1
fi

# The check Sparkle makes: the signature against the public key inside the app.
cat > "$work/verify.swift" <<'SWIFT'
import CryptoKit
import Foundation
let a = CommandLine.arguments
guard let key = Data(base64Encoded: a[1]), let sig = Data(base64Encoded: a[2]),
      let file = FileManager.default.contents(atPath: a[3]),
      let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: key) else { exit(2) }
exit(pub.isValidSignature(sig, for: file) ? 0 : 1)
SWIFT
swift "$work/verify.swift" "$PUBLIC" "$SIG" "$DIR/$ZIP" \
  || { echo "the app wouldn't accept this signature: is the key the one whose public half is $PUBLIC?"; exit 1; }
cp "$work/appcast.xml" "$DIR/appcast.xml"
echo "Signed $VERSION, and the app inside accepts the signature (key $PUBLIC)"

if [ ! -d "$WHAT" ]; then
  gh release upload "v$VERSION" -R "$REPO" "$DIR/appcast.xml" --clobber
  echo "The feed now offers:"
  curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" | grep -Eo 'sparkle:shortVersionString(>[^<]+|="[^"]+")' \
    || echo "nothing yet: v$VERSION may not be the Latest release"
fi
