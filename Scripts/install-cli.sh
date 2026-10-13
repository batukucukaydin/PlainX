#!/bin/bash
#
# PlainX Editor - install the optional `plainx` command.
#
#   Scripts/install-cli.sh            # installs to /usr/local/bin (may need sudo)
#   PREFIX=~/.local Scripts/install-cli.sh
#
# The shim hands off to the running GUI app (or launches it), so the CLI is
# never a second editor implementation. Set PLAINX_APP to point at a
# non-installed build, e.g. PLAINX_APP="$HOME/Library/Developer/PlainXBuild/Build/Products/Release/PlainX.app".
#
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="$PREFIX/bin"
TARGET="$BIN_DIR/plainx"

mkdir -p "$BIN_DIR" 2>/dev/null || {
  echo "error: cannot create $BIN_DIR (try: sudo Scripts/install-cli.sh)" >&2
  exit 1
}

cat > "$TARGET" <<'SHIM'
#!/bin/sh
# PlainX Editor CLI shim: hands files/folders to the running app.
# Usage: plainx [--wait] file-or-folder [...]
APP="${PLAINX_APP:-PlainX}"
if [ ! -d "/Applications/PlainX.app" ] && [ -z "${PLAINX_APP:-}" ]; then
  echo "plainx: PlainX.app not found in /Applications." >&2
  echo "Install it from the DMG, or set PLAINX_APP to the app bundle path." >&2
  exit 1
fi
WAIT_FLAG=""
if [ "${1:-}" = "--wait" ]; then
  WAIT_FLAG="-W"
  shift
fi
exec open $WAIT_FLAG -a "$APP" -- "$@"
SHIM
chmod +x "$TARGET"

echo "Installed: $TARGET"
echo "Try: plainx README.md   (or: PLAINX_APP=... plainx file.txt)"
