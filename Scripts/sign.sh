#!/bin/bash
#
# PlainX Editor - sign a Release app with a Developer ID Application identity.
#
# Requires:
#   DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
#
# The certificate must already be installed in the login keychain. Secrets
# must never be committed to the repository.
#
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="${DERIVED_DATA:-build}"
APP_PATH="$DERIVED_DATA/Build/Products/Release/PlainX.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: Release app not found at $APP_PATH. Run Scripts/make-universal.sh first." >&2
  exit 1
fi

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "error: DEVELOPER_ID_APPLICATION is not set." >&2
  echo "Export it, e.g.:" >&2
  echo "  export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'" >&2
  exit 1
fi

IDENTITY="$DEVELOPER_ID_APPLICATION"

echo "==> Signing embedded code first (frameworks/helpers), then the app"

find "$APP_PATH/Contents/Frameworks" -type d -name "*.framework" 2>/dev/null | while read -r framework; do
  echo "    signing $(basename "$framework")"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$framework"
done

find "$APP_PATH/Contents/MacOS" -type f ! -name PlainX 2>/dev/null | while read -r helper; do
  echo "    signing $(basename "$helper")"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$helper"
done

echo "==> Signing PlainX.app"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$IDENTITY" \
  "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier|Runtime" || true

echo "==> Checking Gatekeeper assessment (expected to fail until notarized)"
spctl --assess --type execute --verbose=2 "$APP_PATH" || true
