#!/bin/bash
#
# PlainX Editor - bootstrap a fresh clone.
#
# Verifies the toolchain and vendored dependencies, regenerates the Xcode
# project, and performs a Debug build so a new contributor can run the app
# immediately afterwards with:  open PlainX.xcodeproj
#
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> PlainX bootstrap"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: Xcode command line tools not found. Install Xcode from the App Store." >&2
  exit 1
fi
xcodebuild -version | head -2

if [[ ! -d Vendor/scintilla/src || ! -d Vendor/lexilla/lexers ]]; then
  echo "error: vendored Scintilla/Lexilla sources are missing." >&2
  echo "Download them with:" >&2
  echo "  Vendor/scintilla: https://sourceforge.net/projects/scintilla/files/scintilla/5.5.4/scintilla554.tgz" >&2
  echo "  Vendor/lexilla:   https://sourceforge.net/projects/scintilla/files/lexilla/5.4.4/lexilla544.tgz" >&2
  exit 1
fi

if [[ ! -f Config/Info.plist || ! -f PlainX.xcodeproj/project.pbxproj ]]; then
  echo "==> Regenerating Xcode project"
  python3 Scripts/generate-project.py
fi

echo "==> Building Debug configuration (this can take a few minutes on first run)"
xcodebuild -project PlainX.xcodeproj -scheme PlainX -configuration Debug build \
  | tail -5

echo
echo "Bootstrap complete. Open the project with:"
echo "  open PlainX.xcodeproj"
echo "Run the unit tests with:"
echo "  Scripts/test.sh"
