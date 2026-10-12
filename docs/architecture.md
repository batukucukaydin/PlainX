# Architecture

PlainX Editor is a native AppKit application written in Swift with a small
Objective-C++ bridge to the vendored Scintilla/Lexilla C++ sources. This
document describes the moving parts and the rules that keep the app fast,
safe, and maintainable.

## High-level structure

```text
PlainX.app
|
+-- Application/           AppDelegate, AppCoordinator, dialog flows
+-- Windowing/              MainWindowController, tabs, status bar, banners
+-- Commands/               CommandRegistry + StandardCommands (menus, palette, macros)
+-- Menus/                  NSMenu construction from the registry
+-- Editor/                 Scintilla facade, editor panes, languages, themes
|   +-- Bridge/             Objective-C++ boundary (PXSciBridge), bridging header
|   +-- Languages/          LanguageRegistry + LexSwiftPx (PlainX Swift lexer)
+-- Documents/              Document model, encoding/EOL, file IO, sessions, recovery
+-- LargeFile/              Memory-mapped reader, sparse line index, streaming search,
|                           follow/tail, read-only viewer
+-- Features/               Search, SearchInFiles, Diff, Macros, Transformations,
|                           CommandPalette
+-- Preferences/            Typed UserDefaults model + Settings window
+-- About/ Shared/          About panel, logging, utilities
+-- Vendor/                 Pinned Scintilla 5.5.4 + Lexilla 5.4.4 (read-only)
```

## Editing engine (Scintilla)

- The authoritative live text buffer for a regular document lives in Scintilla.
  Swift stores metadata and per-pane view state, never a duplicate of the text.
- `Editor/ScintillaFacade.swift` is the **only** place that references raw
  Scintilla message IDs. Everything else uses typed Swift APIs (`facade.text`,
  `facade.setSelection(...)`, indicators, search targets, etc.).
- `Editor/EditorPaneController.swift` hosts one `ScintillaView` per pane and
  translates Scintilla notifications into typed delegate callbacks.
- A document can be shown in two panes (split/cloned view). Text is mirrored at
  the modification level (`SCN_MODIFIED` ranges), not by copying whole buffers.
- The bridge (`PlainX/Bridge/PXSciBridge.*`) is the only Objective-C++ in the
  app. It creates lexer instances (custom Swift lexer first, then the curated
  Lexilla set) and applies them via `SCI_SETILEXER`.

### Lexer strategy

Lexilla's aggregate `Lexilla.cxx` (which references every shipped lexer) is
intentionally **not** linked. `PXSciBridge.mm` contains a small factory table
for the curated language set, which keeps the binary smaller and the build
faster. Languages that Lexilla does not ship dedicated lexers for (Swift,
Java, Go, JavaScript, TypeScript, C#) are mapped to the closest lexer or to
the original PlainX Swift lexer (`LexSwiftPx.cxx`). See
[languages.md](languages.md).

## Documents and file safety

- `PlainXDocument` is the metadata model: URL, encoding/BOM policy, EOL mode,
  language override, dirty state, bookmarks, last known file metadata,
  per-pane caret/scroll state.
- `FileLoader` performs conservative encoding detection (BOM → strict UTF-8 →
  ASCII → UTF-16 heuristics → Windows-1252 fallback) and never silently drops
  bytes; diagnostics are surfaced in the UI when confidence is low.
- `FileSaver` implements the atomic save path: encode → write to a sibling
  temporary file → preserve POSIX permissions → `replaceItemAt`. A failed save
  never destroys the original, and external modifications are detected before
  overwriting.
- `FileWatcher` uses dispatch file-system events to detect external changes
  (and appends for tail mode).

## Large File Mode

- `ChunkReader` memory-maps the file read-only and clamps reads to EOF; pages
  become resident only as they are touched.
- `LineIndex` stores sparse checkpoints (default every 1 MB) and resolves
  exact lines by scanning a bounded window from the nearest checkpoint, so
  memory is proportional to size/stride rather than line count. It supports
  incremental `extend(to:)` for follow mode.
- `StreamingSearch` scans line-aligned chunks with overlap so matches at chunk
  boundaries are never lost, reports progress, and is cancellable.
- `LargeFileViewController`/`LargeFileTextView` render only visible lines,
  support line selection + copy (with a cap), log-level highlighting and
  filtering, and follow/tail with rotation/truncation detection.

## Commands, menus, palette, macros

`CommandRegistry` is the single source of truth: every command has a stable ID,
title, category, optional shortcut, enablement predicate, checked state, and
keywords. Menus, the Command Palette (⇧⌘P), and the macro engine all dispatch
through it, which is also the extension point for future plugins.

## Concurrency model

- UI state lives on the main actor/thread.
- Heavy work runs off-main: indexing and search of large files, folder search,
  diff computation, hashing, recovery pruning.
- Long operations are cancellable and report progress.
- Scintilla and all AppKit views are main-thread only, by rule.

## Persistence

| Data | Location | Format |
|---|---|---|
| Preferences | `UserDefaults` (registered defaults + schema version) | plist |
| Session | `~/Library/Application Support/PlainX/Session.json` | versioned JSON |
| Recovery snapshots | `~/Library/Application Support/PlainX/Recovery/*.json` | versioned JSON |
| Macros | `~/Library/Application Support/PlainX/Macros.json` | versioned JSON |

No databases, no network, no telemetry.

## Build system

`PlainX.xcodeproj` is generated deterministically by
`Scripts/generate-project.py`. Swift sources and resources are included through
Xcode 16 file-system synchronized groups, so new files under `PlainX/` are
picked up automatically. Vendored Scintilla/Lexilla sources are enumerated
explicitly (curated lexer list) and compiled directly into the app target.

A "Strip Extended Attributes" build phase removes Finder/iCloud metadata from
the product before codesigning; without it, codesign can fail when the
checkout lives in an iCloud-synced folder.

## Known v1.0 limitations

- UI strings are English-only; localization infrastructure is a planned
  follow-up (strings are kept as whole sentences to keep that tractable).
- Large File Mode is read-only and UTF-8/single-byte only (UTF-16 huge files
  fall back to a regular open with an explanation).
- Large-file text selection is line-based.
- Text diff is line-level; intra-line highlighting is a future enhancement.
- The plugin API is intentionally out of scope; the command/service
  architecture is the designed foundation.
