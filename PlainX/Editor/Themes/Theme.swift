//
//  Theme.swift
//  PlainX Editor
//
//  Semantic editor themes. Style numbers coming from lexers are mapped to
//  semantic tokens per language (see LanguageRegistry) so themes stay
//  data-driven and a future user-theme file format can reuse the same model.
//

import AppKit

enum SemanticStyle: String, CaseIterable, Codable {
    case text
    case comment
    case docComment
    case keyword
    case keywordSecondary
    case type
    case string
    case character
    case number
    case operatorSymbol
    case identifier
    case function
    case preprocessor
    case attribute
    case constant
    case error
    case diffAdded
    case diffRemoved
    case diffChanged
}

struct StyleAttributes: Equatable {
    var foreground: NSColor
    var background: NSColor?
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false

    static func == (lhs: StyleAttributes, rhs: StyleAttributes) -> Bool {
        lhs.foreground == rhs.foreground
            && lhs.background == rhs.background
            && lhs.bold == rhs.bold
            && lhs.italic == rhs.italic
            && lhs.underline == rhs.underline
    }
}

struct EditorTheme: Equatable {
    let name: String
    let isDark: Bool

    // Editor chrome
    let background: NSColor
    let foreground: NSColor
    let caret: NSColor
    let caretLineBackground: NSColor
    let selectionBackground: NSColor
    let selectionForeground: NSColor?
    let lineNumberForeground: NSColor
    let lineNumberActiveForeground: NSColor
    let lineNumberBackground: NSColor
    let indentGuide: NSColor
    let whitespaceForeground: NSColor
    let foldMarkerForeground: NSColor

    // Search / diff indicators
    let searchMatchFill: NSColor
    let searchMatchOutline: NSColor
    let searchCurrentFill: NSColor
    let bookmarkColor: NSColor
    let diffAddedFill: NSColor
    let diffRemovedFill: NSColor
    let diffChangedFill: NSColor
    let foldLineHighlight: NSColor

    // Semantic syntax styles
    let styles: [SemanticStyle: StyleAttributes]

    func attributes(for semantic: SemanticStyle) -> StyleAttributes {
        styles[semantic] ?? StyleAttributes(foreground: foreground)
    }

    static func == (lhs: EditorTheme, rhs: EditorTheme) -> Bool {
        lhs.name == rhs.name && lhs.isDark == rhs.isDark
    }

    // MARK: - Built-in themes

    static let systemLight: EditorTheme = {
        func color(_ hex: UInt32) -> NSColor { NSColor(pxHex: hex) }
        let styles: [SemanticStyle: StyleAttributes] = [
            .text: .init(foreground: color(0x1F1F24)),
            .comment: .init(foreground: color(0x5D6C79), italic: true),
            .docComment: .init(foreground: color(0x47715F), italic: true),
            .keyword: .init(foreground: color(0x9B2393), bold: false),
            .keywordSecondary: .init(foreground: color(0x9B2393)),
            .type: .init(foreground: color(0x0B4F79)),
            .string: .init(foreground: color(0xC41A16)),
            .character: .init(foreground: color(0xC41A16)),
            .number: .init(foreground: color(0x1C00CF)),
            .operatorSymbol: .init(foreground: color(0x2F2F35)),
            .identifier: .init(foreground: color(0x1F1F24)),
            .function: .init(foreground: color(0x3E6B8A)),
            .preprocessor: .init(foreground: color(0x78492A)),
            .attribute: .init(foreground: color(0x3F6E74)),
            .constant: .init(foreground: color(0x1C00CF)),
            .error: .init(foreground: color(0xB00020), underline: true),
            .diffAdded: .init(foreground: color(0x0B5F2A)),
            .diffRemoved: .init(foreground: color(0xA12A2A)),
            .diffChanged: .init(foreground: color(0x7A5B00)),
        ]
        return EditorTheme(
            name: "System Light",
            isDark: false,
            background: color(0xFFFFFF),
            foreground: color(0x1F1F24),
            caret: color(0x1F1F24),
            caretLineBackground: color(0xF3F4F6),
            selectionBackground: color(0xB9D6FB),
            selectionForeground: nil,
            lineNumberForeground: color(0x8A8A8E),
            lineNumberActiveForeground: color(0x3A3A3E),
            lineNumberBackground: color(0xF6F6F8),
            indentGuide: color(0xE2E2E6),
            whitespaceForeground: color(0xC9C9CE),
            foldMarkerForeground: color(0x8A8A8E),
            searchMatchFill: color(0xFFF1A8),
            searchMatchOutline: color(0xE6C700),
            searchCurrentFill: color(0xFFD84D),
            bookmarkColor: color(0x1E7AF0),
            diffAddedFill: color(0xD3F5DD),
            diffRemovedFill: color(0xFFD6D6),
            diffChangedFill: color(0xFFF1C2),
            foldLineHighlight: color(0xEDEDF2),
            styles: styles
        )
    }()

    static let systemDark: EditorTheme = {
        func color(_ hex: UInt32) -> NSColor { NSColor(pxHex: hex) }
        let styles: [SemanticStyle: StyleAttributes] = [
            .text: .init(foreground: color(0xDFDFE0)),
            .comment: .init(foreground: color(0x7F8C98), italic: true),
            .docComment: .init(foreground: color(0x86A88F), italic: true),
            .keyword: .init(foreground: color(0xFF7AB2)),
            .keywordSecondary: .init(foreground: color(0xFF7AB2)),
            .type: .init(foreground: color(0x6BDFFF)),
            .string: .init(foreground: color(0xFF8170)),
            .character: .init(foreground: color(0xFF8170)),
            .number: .init(foreground: color(0xD0BF69)),
            .operatorSymbol: .init(foreground: color(0xCED0D4)),
            .identifier: .init(foreground: color(0xDFDFE0)),
            .function: .init(foreground: color(0x86B6E0)),
            .preprocessor: .init(foreground: color(0xD9A66B)),
            .attribute: .init(foreground: color(0x9FD6C6)),
            .constant: .init(foreground: color(0xD0BF69)),
            .error: .init(foreground: color(0xFF6B6B), underline: true),
            .diffAdded: .init(foreground: color(0x8FE2A4)),
            .diffRemoved: .init(foreground: color(0xFF9B9B)),
            .diffChanged: .init(foreground: color(0xE7D27C)),
        ]
        return EditorTheme(
            name: "System Dark",
            isDark: true,
            background: color(0x1F1F24),
            foreground: color(0xDFDFE0),
            caret: color(0x66D4FF),
            caretLineBackground: color(0x27272D),
            selectionBackground: color(0x3A4A5F),
            selectionForeground: nil,
            lineNumberForeground: color(0x6E7178),
            lineNumberActiveForeground: color(0xB8BABF),
            lineNumberBackground: color(0x1B1B20),
            indentGuide: color(0x323238),
            whitespaceForeground: color(0x4A4A50),
            foldMarkerForeground: color(0x8A8F98),
            searchMatchFill: color(0x6B5B1F),
            searchMatchOutline: color(0xC9A227),
            searchCurrentFill: color(0x8A6B2A),
            bookmarkColor: color(0x4A9EFF),
            diffAddedFill: color(0x1F3A27),
            diffRemovedFill: color(0x3D2222),
            diffChangedFill: color(0x3D3620),
            foldLineHighlight: color(0x28282E),
            styles: styles
        )
    }()

    static func theme(for appearance: NSAppearance) -> EditorTheme {
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .systemDark : .systemLight
    }
}

extension NSColor {
    /// Creates a color from a 0xRRGGBB literal.
    convenience init(pxHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    var pxHexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
