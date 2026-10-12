#!/bin/bash
#
# PlainX Editor - generate SHA-256 checksums for release artifacts.
#
#   Scripts/generate-checksums.sh <file-or-directory> [...]
#
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <file> [files...]" >&2
  exit 1
fi

for target in "$@"; do
  if [[ "$target" == *.sha256 ]]; then
    continue
  fi
  echo "==> sha256: $target"
  ( cd "$(dirname "$target")" && shasum -a 256 "$(basename "$target")" > "$(basename "$target").sha256" )
  cat "$target.sha256"
done
