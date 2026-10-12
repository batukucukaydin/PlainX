# Releasing PlainX Editor

This document describes the complete release path, from version bump to
notarized DMG. Everything can be produced locally; the GitHub Actions release
workflow automates the same steps.

## One-time setup

1. **Apple Developer Program** membership for a Developer ID Application
   certificate (needed only for signed distribution).
2. Create the certificate in Xcode (Settings → Accounts → Manage Certificates →
   Developer ID Application) or download it from the developer portal and
   install it in your login keychain.
3. Store notarization credentials once:

   ```bash
   xcrun notarytool store-credentials plainx-notary \
     --apple-id you@example.com \
     --team-id TEAMID \
     --password <app-specific-password>
   ```

4. GitHub repository secrets (for `release.yml`):
   - `DEVELOPER_ID_APPLICATION` – e.g. `Developer ID Application: Name (TEAMID)`
   - `DEVELOPER_ID_CERTIFICATE_P12` – base64 of the exported `.p12`
   - `DEVELOPER_ID_CERTIFICATE_PASSWORD`
   - `KEYCHAIN_PASSWORD` – any password for the temporary CI keychain
   - `NOTARY_PROFILE` – `plainx-notary` (import the profile in the CI step)
     or the `NOTARY_APPLE_ID` / `NOTARY_TEAM_ID` / `NOTARY_PASSWORD` trio

   Without these secrets the workflow still builds and uploads an
   unsigned/ad-hoc DMG.

## Local release checklist

```bash
# 1. Update the version
#    - Scripts: MARKETING_VERSION in Scripts/generate-project.py
#    - CHANGELOG.md entry
python3 Scripts/generate-project.py

# 2. Verify the code
Scripts/test.sh

# 3. Universal 2 Release build (arm64 + x86_64)
Scripts/make-universal.sh

# 4. Signature (needs the certificate)
export DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)"
Scripts/sign.sh

# 5. DMG + checksums
Scripts/package-dmg.sh

# 6. Notarize and staple
export NOTARY_PROFILE=plainx-notary
Scripts/notarize.sh "$HOME/Library/Developer/PlainXBuild/dist/PlainX-Editor-v1.0.0-universal.dmg"
Scripts/generate-checksums.sh "$HOME/Library/Developer/PlainXBuild/dist/PlainX-Editor-v1.0.0-universal.dmg"

# 7. Git tag + GitHub release
git tag v1.0.0 && git push origin v1.0.0
#    or: gh release create v1.0.0 --notes-file CHANGELOG.md \
#          ~/Library/Developer/PlainXBuild/dist/PlainX-Editor-v1.0.0-universal.dmg*
```

## Manual verification on a clean machine

1. Download the DMG, verify the checksum:

   ```bash
   shasum -a 256 -c PlainX-Editor-v1.0.0-universal.dmg.sha256
   ```

2. Open the DMG, drag **PlainX.app** to Applications.
3. First launch: Gatekeeper should allow it without warnings when signed and
   notarized. Unsigned builds require right-click → Open.
4. Spot-check: open a text file, edit/save, open a large log, tail it,
   Find in Files, compare two files, quit and relaunch (session restored).

## Homebrew cask

Once the first signed release exists, publish the cask from
`docs/homebrew/plainx.rb` (update `version` and `sha256`) to a tap, then:

```bash
brew install --cask plainx
```

## Versioning

- `CFBundleShortVersionString` follows semver (`MARKETING_VERSION` in
  `Scripts/generate-project.py`).
- `CFBundleVersion` is monotonic (`CURRENT_PROJECT_VERSION`).
- Tags are `vMAJOR.MINOR.PATCH`.

## Rollback

Releases are immutable artifacts. If a release is bad:

1. Mark the GitHub release as a pre-release or delete it and its tag.
2. Publish the previous DMG as a new patch release with a fix note.
3. If a Homebrew cask was published, revert the cask version promptly.
