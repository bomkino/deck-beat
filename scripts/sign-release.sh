#!/bin/bash
# Signs a release for the in-app updater, on the Mac that holds the update key:
# writes an appcast.xml that offers the release's ZIP, with the ZIP's EdDSA
# signature, so installed copies of Deck Beat update themselves to it.
#
#   bash scripts/sign-release.sh <version> [update-notes.md]   a published release: fetch, sign, upload
#   bash scripts/sign-release.sh <folder> [update-notes.md]    a folder from pack-release.sh: sign in place
#
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

# generate_appcast signs every archive in its folder, so it works in its own.
mkdir -p "$work/cast"
cp "$DIR/$ZIP" "$work/cast/"
# Notes shown in the update window: a Markdown file named like the archive.
if [ -n "$NOTES" ]; then cp "$NOTES" "$work/cast/${ZIP%.zip}.md"; fi
"$SPARKLE_BIN/generate_appcast" --ed-key-file "$SPARKLE_KEY" --download-url-prefix "$DOWNLOAD_URL" \
  --link "https://github.com/$REPO/releases" --embed-release-notes --maximum-versions 1 -o "$DIR/appcast.xml" "$work/cast" >/dev/null
grep -q "sparkle:edSignature=" "$DIR/appcast.xml" || { echo "appcast.xml has no signature"; exit 1; }
grep -Eo 'sparkle:shortVersionString(>[^<]+|="[^"]+")|url="[^"]*"' "$DIR/appcast.xml" | head -2

if [ ! -d "$WHAT" ]; then
  gh release upload "v$VERSION" -R "$REPO" "$DIR/appcast.xml" --clobber
  echo "The feed now offers:"
  curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" | grep -Eo 'sparkle:shortVersionString(>[^<]+|="[^"]+")' \
    || echo "nothing yet: v$VERSION may not be the Latest release"
fi
