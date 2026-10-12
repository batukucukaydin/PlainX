<p align="center">
  <img src="PlainX/Resources/Branding/PlainX-Logo.png" width="180" alt="PlainX Editor logo">
</p>

<h1 align="center">PlainX Editor</h1>

<p align="center"><strong>Plain text. Extra power.</strong></p>

<p align="center">
  PlainX Editor is a fast, lightweight and powerful native text &amp; code editor for macOS.
</p>

---

## Why PlainX

- **Native, not a browser.** Built with Swift and AppKit on top of Scintilla and
  Lexilla. No Electron, no Chromium, no Node.js.
- **Instant.** Launches in under half a second warm, opens ordinary files immediately.
- **Large files are first-class.** A dedicated, memory-mapped Large File Mode opens
  multi-hundred-megabyte logs read-only without freezing, with streaming search
  and follow/tail.
- **Everything you miss from Notepad++.** Tabs, split views, regex replace,
  multi-cursor and column editing, macros, diff, line operations, encoding and
  line-ending tools, find in files.
- **Local-first and private.** No accounts, no telemetry, no document contents
  ever leave your Mac.

## Feature highlights

| Area | What you get |
|---|---|
| Editing | Tabs with pin/reorder, split & cloned views, multi-cursor, rectangular selection, bookmarks, folding, word wrap, zoom, indent guides |
| Search | Inline find/replace with regex (ECMAScript), case/whole-word, in-selection, Find All, and streaming Find in Files with include/exclude globs |
| Syntax | 30+ languages including Swift, C/C++, Objective-C, C#, Java, JavaScript/TypeScript, Go, Python, Ruby, Rust, PHP, Shell, PowerShell, SQL, HTML, XML, CSS, JSON, YAML, TOML, INI, Markdown, Makefile, Dockerfile |
| Files | Atomic safe saves, external-change detection, rename, reveal in Finder, recent files, drag & drop |
| Sessions | Window/tab/caret restoration, crash-safe recovery snapshots (never uploaded) |
| Tools | JSON format/minify/validate, XML format/validate (no external entities), Base64, URL encode/decode, HTML escape, SHA-256/512 (+legacy MD5/SHA-1), hashes of open files |
| Compare | Built-in side-by-side diff with synchronized scrolling, change navigation, ignore-whitespace |
| Macros | Record/replay semantic commands with persistence and safety caps |
| Large files | Read-only memory-mapped viewer, lazy line index, cancellable streaming search, follow/tail with rotation detection, log level filtering |
| macOS | Command palette (⇧⌘P), native menus/shortcuts, light/dark themes, VoiceOver labels, diagnostics report |

## Requirements

- macOS 13 Ventura or later
- Universal 2 builds support both Apple Silicon and Intel Macs

## Download

Grab the latest DMG from [Releases](../../releases):

```
PlainX-Editor-v1.0.0-universal.dmg
```

Open the DMG and drag **PlainX.app** into **Applications**.

Unsigned development builds are also available as an artifact from the release
workflow when signing certificates are not configured; macOS may require
right-click → Open the first time.

### Homebrew (once the cask is published)

```bash
brew install --cask plainx
```

A cask recipe draft is available at `docs/homebrew/plainx.rb`.

## Building from source

Prerequisites: Xcode 15+ and Python 3 (for the project generator).

```bash
git clone https://github.com/your-org/plainx-editor.git
cd plainx-editor
Scripts/bootstrap.sh        # regenerates the project and builds Debug
open PlainX.xcodeproj       # or: Scripts/build.sh Release
```

Run the test suite:

```bash
Scripts/test.sh
```

Build a Universal 2 Release and package a DMG:

```bash
Scripts/make-universal.sh
Scripts/package-dmg.sh
```

Signing and notarization scripts (`Scripts/sign.sh`, `Scripts/notarize.sh`)
explain exactly which certificate/secret is needed; see `docs/release.md`.

## Privacy

PlainX Editor collects nothing. There is no telemetry, no analytics, no
account, and no automatic network access. Update checks are off by default.
Recovery snapshots are stored only in `~/Library/Application Support/PlainX`
on your own Mac. Tools → Copy Diagnostics produces a version/platform/preference
report you can review before pasting it anywhere.

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and
the architecture notes in [docs/architecture.md](docs/architecture.md).

- Bug reports and feature requests use the GitHub issue templates.
- Please run `Scripts/test.sh` before opening a pull request.
- Data safety first: never regress atomic saves or external-change detection.

## License

PlainX Editor is released under the [MIT License](LICENSE).
Bundled third-party components (Scintilla, Lexilla) use a permissive
MIT-style license; see [NOTICE.md](NOTICE.md).
