#!/bin/bash
#
# PlainX Editor - build a Universal 2 (arm64 + x86_64) Release app.
#
# Requires both architectures to be available in the installed Xcode SDK
# (standard on Apple Silicon with Rosetta-capable SDKs).
#
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/PlainXBuild}"

echo "==> Building Universal 2 Release"
xcodebuild \
  -project PlainX.xcodeproj \
  -scheme PlainX \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/PlainX.app"
BINARY="$APP_PATH/Contents/MacOS/PlainX"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: build product not found at $APP_PATH" >&2
  exit 1
fi

# Strip extended attributes (Finder/iCloud metadata) that break codesign.
xattr -cr "$APP_PATH" 2>/dev/null || true

ARCHS_FOUND="$(lipo -archs "$BINARY")"
echo "==> Architectures: $ARCHS_FOUND"

if [[ "$ARCHS_FOUND" != *"arm64"* || "$ARCHS_FOUND" != *"x86_64"* ]]; then
  echo "error: expected a Universal 2 binary containing arm64 and x86_64" >&2
  exit 1
fi

echo "==> Universal binary verified"
echo "==> App bundle size: $(du -sh "$APP_PATH" | cut -f1)"
