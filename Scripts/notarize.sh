#!/bin/bash
#
# PlainX Editor - notarize a signed DMG and staple the ticket.
#
# Requires either:
#   notarytool keychain profile:  NOTARY_PROFILE="plainx-notary"
# or the three Apple ID credentials:
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD (app-specific password)
#
# Create a keychain profile once with:
#   xcrun notarytool store-credentials plainx-notary \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <path-to-dmg-or-zip>" >&2
  exit 1
fi

ARTIFACT="$1"

if [[ ! -f "$ARTIFACT" ]]; then
  echo "error: artifact not found: $ARTIFACT" >&2
  exit 1
fi

echo "==> Submitting $(basename "$ARTIFACT") for notarization"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ARTIFACT" --keychain-profile "$NOTARY_PROFILE" --wait
else
  if [[ -z "${NOTARY_APPLE_ID:-}" || -z "${NOTARY_TEAM_ID:-}" || -z "${NOTARY_PASSWORD:-}" ]]; then
    echo "error: set NOTARY_PROFILE or NOTARY_APPLE_ID + NOTARY_TEAM_ID + NOTARY_PASSWORD." >&2
    exit 1
  fi
  xcrun notarytool submit "$ARTIFACT" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait
fi

echo "==> Stapling the ticket"
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"

echo "==> Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature --verbose=2 "$ARTIFACT" || true

echo "==> Notarization complete"
