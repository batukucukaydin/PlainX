#!/bin/bash
#
# PlainX Editor - build.
#
#   Scripts/build.sh [Debug|Release] [extra xcodebuild arguments...]
#
# Examples:
#   Scripts/build.sh
#   Scripts/build.sh Release
#   Scripts/build.sh Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
#
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-Debug}"
shift || true

DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/PlainXBuild}"

echo "==> Building PlainX ($CONFIGURATION)"
xcodebuild \
  -project PlainX.xcodeproj \
  -scheme PlainX \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  "$@" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/PlainX.app"
if [[ -d "$APP_PATH" ]]; then
  echo
  echo "==> Built: $APP_PATH"
  echo "==> Architectures: $(lipo -archs "$APP_PATH/Contents/MacOS/PlainX" 2>/dev/null || echo unknown)"
  echo "==> Bundle size: $(du -sh "$APP_PATH" | cut -f1)"
fi
