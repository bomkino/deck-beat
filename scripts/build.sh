#!/bin/bash
# Builds Deck Beat as a signed (ad-hoc) .app bundle in ../dist.
#
#   bash scripts/build.sh [debug|release]
#
# Uses the Command Line Tools only. The macOS 26.5 SDK is used because the
# macOS 27 SDK expands SwiftUI's @State with a macro plugin that ships only
# with Xcode.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${1:-release}"
shift || true
APPS=("${@:-DeckBeat}")
if [ "${#APPS[@]}" -eq 1 ]; then read -r -a APPS <<< "${APPS[0]}"; fi

SDK_CANDIDATES=(
  /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  /Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk
  /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
  /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
)
for s in "${SDK_CANDIDATES[@]}"; do
  if [ -d "$s" ]; then export SDKROOT="$s"; break; fi
done
echo "SDK: ${SDKROOT:-default}"

DIST="$ROOT/../dist"
mkdir -p "$DIST"

for APP in "${APPS[@]}"; do
  # Projects are packages: project.json plus a Media folder, as in Drift.
  case "$APP" in
    DeckBeat) BUNDLE_NAME="Deck Beat"; BUNDLE_ID="dog.pitch.deckbeat"; UTI="dog.pitch.deckbeat.project"; EXT="deckbeat"; DOC_NAME="Deck Beat Project"; VERSION="2.0.0" ;;
    *) echo "unknown app $APP"; exit 2 ;;
  esac

  echo "== Building $APP ($CONFIG)"
  swift build -c "$CONFIG" --product "$APP" 2>&1 | grep -E "error|warning: unre|Compiling|Build comp" | grep -v "^\[" || true
  BIN="$(swift build -c "$CONFIG" --product "$APP" --show-bin-path)/$APP"
  [ -x "$BIN" ] || { echo "missing binary $BIN"; exit 1; }

  # The bundle name has a space, so every path below stays quoted.
  APPDIR="$DIST/$BUNDLE_NAME.app"
  rm -rf "$APPDIR"
  mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"
  cp "$BIN" "$APPDIR/Contents/MacOS/$APP"
  if [ -f "$ROOT/Resources/Icons/$APP.icns" ]; then
    cp "$ROOT/Resources/Icons/$APP.icns" "$APPDIR/Contents/Resources/AppIcon.icns"
  fi
  cp "$ROOT/NOTICES.md" "$APPDIR/Contents/Resources/NOTICES.md" 2>/dev/null || true

  BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
  cat > "$APPDIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$BUNDLE_NAME</string>
  <key>CFBundleDisplayName</key><string>$BUNDLE_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 pitch.dog</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>$DOC_NAME</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>$UTI</string></array>
      <key>LSTypeIsPackage</key><true/>
      <key>NSDocumentClass</key><string>NSDocument</string>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>$UTI</string>
      <key>UTTypeDescription</key><string>$DOC_NAME</string>
      <key>UTTypeConformsTo</key><array><string>com.apple.package</string><string>public.composite-content</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>$EXT</string></array></dict>
    </dict>
  </array>
</dict>
</plist>
PLIST
  codesign --force --deep --sign - "$APPDIR" >/dev/null 2>&1 || echo "codesign failed (continuing unsigned)"
  echo "   → $APPDIR"
done
