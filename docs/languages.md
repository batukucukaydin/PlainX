# Languages

PlainX ships syntax highlighting through Lexilla plus one original lexer.

## How detection works

1. Explicit user choice from the **Language** menu or the status bar
   (persisted per document).
2. Exact file name (`Dockerfile`, `Makefile`, `Rakefile`, `.zshrc`, …).
3. Extension (case-insensitive), including compound names such as `.d.ts`.
4. Plain text fallback.

Switching the language never touches the document text or the undo history.

## Supported languages

| Language | Lexer | Folding | Notes |
|---|---|---|---|
| Plain Text | none | – | default |
| Swift | `swift` (PlainX lexer) | yes | nested block comments, multiline strings, interpolation, attributes, `#available` |
| C | `cpp` | yes | C keywords/type set |
| C++ | `cpp` | yes | full keyword set |
| Objective-C / Objective-C++ | `cpp` | yes | Objective-C additions |
| C# | `cpp` | yes | C# keyword set |
| Java | `cpp` | yes | Java keyword set |
| JavaScript | `cpp` | yes | JS/Node keyword set; template literals style as strings |
| TypeScript | `cpp` | yes | TS keywords + type names |
| Go | `cpp` | yes | Go keywords |
| Python | `python` | yes | f-strings, decorators |
| Ruby | `ruby` | yes | classes, symbols, heredocs |
| Rust | `rust` | yes | word lists for types/macros |
| PHP | `phpscript` | yes | |
| Perl | `perl` | yes | |
| Shell (bash/zsh) | `bash` | yes | builtin/command word lists |
| PowerShell | `powershell` | yes | cmdlet list |
| Batch | `batch` | no | |
| Dockerfile | `bash` | no | Docker keywords layered on the shell lexer |
| SQL | `sql` | yes | standard+common dialect keywords |
| HTML | `hypertext` | yes | embedded JS/CSS |
| XML | `xml` | yes | |
| CSS | `css` | yes | |
| JSON | `json` | yes | |
| YAML | `yaml` | yes | |
| TOML | `toml` | yes | |
| INI / Properties | `props` | no | `.ini`, `.conf`, `.editorconfig`, `*.properties` |
| Markdown | `markdown` | yes | |
| Makefile | `makefile` | no | |
| Diff | `diff` | no | added/removed line styling |
| Assembly | `asm` | no | |
| Visual Basic | `vb` | yes | |

Comments, indentation, and folding behavior come from the language
definition in `PlainX/Editor/Languages/LanguageRegistry.swift`.

## Regex dialect

Find/Replace and Find in Files use Scintilla's ECMAScript-compatible engine
(`SCFIND_CXX11REGEX`), so patterns like `([a-z]+) (\d+)` and `\1`
backreferences work as expected from Notepad++-style editing.

## Adding a language

1. Add or adjust a `LanguageDefinition` in `LanguageRegistry.swift`
   (extensions, file names, keywords, comment tokens, style map).
2. If it uses a new Lexilla lexer, add the lexer's `.cxx` to `LEXILLA_LEXERS`
   in `Scripts/generate-project.py`, declare it in `PXSciBridge.mm`, and
   regenerate the project.
3. Add a unit test fixture exercising detection and style mapping.
