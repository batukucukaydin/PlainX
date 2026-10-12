#!/bin/bash
#
# PlainX Editor - run the automated test suite (unit + integration + perf).
#
#   Scripts/test.sh [extra xcodebuild test arguments...]
#
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/PlainXBuild}"

echo "==> Running PlainXTests"
xcodebuild \
  -project PlainX.xcodeproj \
  -scheme PlainX \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS' \
  "$@" \
  test \
  -only-testing:PlainXTests

echo "UI tests are skipped by default; run them with:"
echo "  xcodebuild test -scheme PlainX -destination 'platform=macOS' -only-testing:PlainXUITests"
