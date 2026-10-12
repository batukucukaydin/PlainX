# Third-Party Notices

PlainX Editor is MIT licensed. It bundles the following third-party
components. Full license texts are kept next to the sources under `Vendor/`.

## Scintilla 5.5.4

- Purpose: text editing engine (the authoritative editing buffer for regular documents).
- Source: https://sourceforge.net/projects/scintilla/ (vendored at `Vendor/scintilla`).
- License: "License for Lexilla, Scintilla, and SciTE" — a permissive MIT-style
  license: `Vendor/scintilla/License.txt`.

```
Copyright 1998-2021 by Neil Hodgson <neilh@scintilla.org>
All Rights Reserved

Permission to use, copy, modify, and distribute this software and its
documentation for any purpose and without fee is hereby granted, provided
that the above copyright notice appear in all copies and that both that
copyright notice and this permission notice appear in supporting
documentation.

NEIL HODGSON DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS; IN NO EVENT
SHALL NEIL HODGSON BE LIABLE FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL
DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS
ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS
SOFTWARE.
```

## Lexilla 5.4.4

- Purpose: lexers / syntax highlighting (`Vendor/lexilla`).
- License: same permissive license as Scintilla: `Vendor/lexilla/License.txt`.

## PlainX Swift lexer (`PlainX/Editor/Languages/LexSwiftPx.cxx`)

- Original work by the PlainX Editor contributors, MIT licensed.
- Not derived from Notepad++ or any GPL source.

## Not bundled

PlainX intentionally ships without Electron, Chromium, Node.js, Python,
Java, Sparkle (updates are GitHub Releases based), or any telemetry SDK.
There are no other runtime dependencies at v1.0.
