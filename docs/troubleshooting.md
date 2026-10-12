# Troubleshooting

## The app doesn't launch after building

- Make sure your checkout is not inside an iCloud-synced folder when you sign:
  codesign fails with "resource fork, Finder information, or similar detritus
  not allowed" if macOS keeps Finder/file-provider metadata on the built
  bundle. The build scripts default to
  `~/Library/Developer/PlainXBuild` for this reason, and the project contains
  a build phase that strips extended attributes before signing.
- If Xcode itself fails only at CodeSign, run
  `xattr -cr ~/Library/Developer/Xcode/DerivedData/PlainX-*/Build/Products/*/PlainX.app`
  and build again.

## A file opens as "garbage" characters

PlainX detects encodings conservatively. If a file is not valid UTF-8 you will
see a banner naming the assumed encoding (usually Windows-1252). Fix it with
the status-bar **Encoding** menu → *Reopen with Encoding…* and pick the right
one, then *Change Encoding* to convert and save as UTF-8.

## “This file changed on disk” banners

PlainX never overwrites a file that changed on disk after you opened it.
Choose:

- **Reload** – discard your in-editor changes and take the disk version.
- **Keep Mine** – keep editing; the next save asks again.
- **Save Anyway** – overwrite the disk version with your buffer.
- **Compare…** – open the built-in diff between disk and editor.

## A huge file opened in the regular editor

Large File Mode supports UTF-8 and common single-byte encodings. Files in
UTF-16/UTF-32 (or below your configured threshold when you set
"Open Normally") go through the regular editor. Adjust the threshold and
behavior in Settings → Large Files. "Open Normally…" in the viewer always
gives you a confirmation first because the whole file is loaded into memory.

## Follow mode says the file was rotated

Log rotation (rename + new file, or truncation) ends the original file
descriptor. PlainX shows a banner: **Reload** re-opens the path so you follow
the new file; **Keep Viewing** keeps the old mapping.

## Find in Files misses files

- Check the **Include** field (empty means "all text files") and the
  **Exclude** field; both accept `;`-separated globs.
- Directories listed under Settings → Search → *Ignored folders* are skipped
  (defaults: `.git`, `node_modules`, `build`, `DerivedData`, …).
- Files that look binary (NUL byte in the first 8 KiB) and files larger than
  the search limit are skipped; both produce a note in the results list.
- Hidden files are skipped by design.

## Settings feel stuck / want a clean slate

- Settings → Advanced → *Reset All Settings…* restores defaults.
- Sessions/recovery live in `~/Library/Application Support/PlainX`; quitting
  the app and removing that folder resets session, recovery snapshots, and
  macros.

## Reporting a problem

Run **Tools → Copy Diagnostics** (version, macOS, architecture, preference
flags — no document content), then open a GitHub issue with the output and
reproduction steps.
