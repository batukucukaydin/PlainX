#!/bin/bash
#
# PlainX Editor - package a Release build into a distributable DMG.
#
#   Scripts/package-dmg.sh [--unsigned]
#
# Output:
#   build/dist/PlainX-Editor-v<version>-<arch>.dmg
#   build/dist/PlainX-Editor-v<version>-<arch>.dmg.sha256
#
# The DMG contains PlainX.app and an /Applications symlink. The mounted
# volume is named "PlainX Editor".
#
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/PlainXBuild}"
DIST_DIR="$DERIVED_DATA/dist"
APP_PATH="$DERIVED_DATA/Build/Products/Release/PlainX.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: Release app not found. Run Scripts/make-universal.sh first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0.0")"
ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/PlainX" 2>/dev/null || echo "unknown")"
if [[ "$ARCHS" == *"arm64"* && "$ARCHS" == *"x86_64"* ]]; then
  ARCH_LABEL="universal"
else
  ARCH_LABEL="$ARCHS"
fi

mkdir -p "$DIST_DIR"
STAGING="$(mktemp -d /tmp/plainx-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT

echo "==> Staging app bundle"
cp -R "$APP_PATH" "$STAGING/PlainX.app"
xattr -cr "$STAGING/PlainX.app" 2>/dev/null || true
ln -s /Applications "$STAGING/Applications"

DMG_NAME="PlainX-Editor-v${VERSION}-${ARCH_LABEL}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "==> Creating $DMG_NAME"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "PlainX Editor" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH" >/dev/null

echo "==> Signing DMG (skipped when no identity is available)"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
if [[ -n "$IDENTITY" && "${1:-}" != "--unsigned" ]]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
else
  echo "    (set DEVELOPER_ID_APPLICATION to sign the DMG)"
fi

"$(dirname "$0")/generate-checksums.sh" "$DMG_PATH"

echo
echo "==> DMG ready: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"
