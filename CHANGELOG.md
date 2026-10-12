# Changelog

All notable changes to PlainX Editor are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-10-11

Initial release.

### Added

- Native AppKit editor shell with tabs (pin, reorder, reopen closed tab),
  split/cloned views, drag & drop, recent files, and window sessions.
- Scintilla 5.5.4 editing engine with a centralized Swift facade.
- 30+ languages via Lexilla 5.4.4 plus an original Swift lexer with nested
  block comments, multiline strings, interpolation, attributes, and folding.
- Semantic light/dark themes with system appearance following.
- Inline find/replace (regex, case, whole word, in-selection, wrap, Find All)
  and streaming Find in Files with include/exclude globs, binary skipping,
  cancellation, and review-before-replace writes.
- Encoding detection/conversion (UTF-8 with/without BOM, UTF-16 LE/BE, ASCII,
  Windows-1252, Latin-1) and LF/CRLF/CR conversion with mixed-EOL reporting.
- Atomic safe saves, external-change detection with Reload/Compare/Save Anyway,
  crash-safe recovery snapshots, and session restoration.
- Line operations, case conversions, whitespace tools, indentation conversion,
  multi-cursor and rectangular editing, bookmarks, folding, and word completion.
- Developer tools: JSON and XML formatting/validation, Base64, URL encode/decode,
  HTML escape, SHA-256/512 and legacy MD5/SHA-1 (of selection or file).
- Built-in side-by-side compare with synchronized scrolling and change navigation.
- Macro recording/replay with versioned storage and safety caps.
- Command palette (⇧⌘P) backed by the same command registry that drives menus
  and macros.
- Large File Mode: memory-mapped read-only viewer, lazy sparse line index,
  cancellable streaming search, follow/tail with rotation detection, log-level
  filtering, and safe copy limits.
- Preferences, About with brand logo, keyboard shortcut reference, diagnostics
  report, print support.
- Release engineering: universal 2 builds, DMG packaging with checksums,
  signing/notarization scripts, GitHub Actions CI and release workflows,
  Homebrew cask draft, developer benchmark scripts.

### Notes

- v1.0 ships English UI. Localization infrastructure is planned.
- Large File Mode is read-only by design; editing huge files remains out of
  scope for v1.0.
