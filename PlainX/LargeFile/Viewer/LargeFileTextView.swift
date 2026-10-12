//
//  LargeFileTextView.swift
//  PlainX Editor
//
//  Custom, scroll-efficient renderer for Large File Mode. Only the visible
//  lines are decoded and drawn; the view never builds the whole document.
//

import AppKit

struct LargeFileHighlightRules {
    var tokens: [(token: String, color: NSColor)] = [
        ("ERROR", .systemRed),
        ("FATAL", .systemRed),
        ("WARN", .systemOrange),
        ("WARNING", .systemOrange),
        ("INFO", .systemBlue),
        ("DEBUG", .secondaryLabelColor),
        ("TRACE", .tertiaryLabelColor),
    ]
    var isEnabled = true
}

final class LargeFileTextView: NSView {
    let backing: LargeFileBacking
    var theme: EditorTheme
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    var highlightRules = LargeFileHighlightRules()

    /// Optional filtered line numbers (real line numbers). When set, only
    /// these lines are displayed.
    var filteredLines: [Int]? {
        didSet { resetHeightCache() }
    }

    /// Search highlights: line number → range in UTF-16 units plus current flag.
    var searchMatches: [Int: NSRange] = [:]
    var currentSearchLine: Int?

    /// Line-based selection (inclusive).
    private(set) var selectedLineRange: ClosedRange<Int>?

    var onSelectionChanged: (() -> Void)?
    var onVisibleLineChanged: (() -> Void)?

    private static let gutterWidth: CGFloat = 72
    private static let horizontalPadding: CGFloat = 6

    private var lastReportedFirstLine = -1

    init(backing: LargeFileBacking, theme: EditorTheme) {
        self.backing = backing
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        // The view is intentionally not layer-backed: its frame can be tens of
        // millions of points tall, and a layer backing store would attempt to
        // allocate for the full bounds instead of just the visible region.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Geometry

    var lineHeight: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((font.ascender - font.descender + font.leading) + 1)
    }

    private var displayedLineCount: Int {
        filteredLines?.count ?? max(1, backing.lineCount)
    }

    func resetHeightCache() {
        updateFrameHeight()
        needsDisplay = true
    }

    func updateFrameHeight() {
        let height = max(CGFloat(displayedLineCount) * lineHeight + 12, bounds.height)
        if abs(frame.height - height) > 0.5 {
            setFrameSize(NSSize(width: max(frame.width, 900), height: height))
        }
    }

    private func displayIndexToRealLine(_ index: Int) -> Int {
        if let filteredLines {
            guard filteredLines.indices.contains(index) else { return 0 }
            return filteredLines[index]
        }
        return index
    }

    private func realLineToDisplayIndex(_ line: Int) -> Int? {
        guard let filteredLines else { return line }
        // Binary search for the first filtered line >= line.
        var lower = 0
        var upper = filteredLines.count - 1
        while lower <= upper {
            let mid = (lower + upper) / 2
            if filteredLines[mid] == line { return mid }
            if filteredLines[mid] < line { lower = mid + 1 } else { upper = mid - 1 }
        }
        return nil
    }

    var firstVisibleDisplayIndex: Int {
        max(0, Int(floor(visibleRect.origin.y / lineHeight)))
    }

    var lastVisibleDisplayIndex: Int {
        min(displayedLineCount - 1, Int(ceil((visibleRect.origin.y + visibleRect.height) / lineHeight)))
    }

    func scrollToLine(_ line: Int, centered: Bool = true) {
        guard let displayIndex = realLineToDisplayIndex(line) else { return }
        let y = CGFloat(displayIndex) * lineHeight
        let target = centered ? y - bounds.height / 3 : y
        scroll(NSPoint(x: bounds.origin.x, y: max(0, target)))
    }

    func scrollToBottom() {
        let maxY = max(0, frame.height - (superview?.bounds.height ?? frame.height))
        scroll(NSPoint(x: bounds.origin.x, y: maxY))
    }

    var isAtBottom: Bool {
        guard let clip = superview else { return true }
        return bounds.maxY >= clip.bounds.maxY - lineHeight * 2
    }

    // MARK: - Drawing

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(theme.background.cgColor)
        context.fill(dirtyRect)

        let height = lineHeight
        let first = firstVisibleDisplayIndex
        // The view can be tens of millions of points tall; never render more
        // than the visible window (plus a small margin) regardless of what the
        // dirty rect covers.
        let last = min(lastVisibleDisplayIndex, first + 200)
        guard last >= first else { return }

        let lineNumberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(9, font.pointSize - 2), weight: .regular),
            .foregroundColor: theme.lineNumberForeground,
        ]
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.foreground,
        ]

        // Gutter background
        context.setFillColor(theme.lineNumberBackground.cgColor)
        context.fill(CGRect(x: 0, y: dirtyRect.minY, width: Self.gutterWidth, height: dirtyRect.height))

        for displayIndex in first...last {
            let realLine = displayIndexToRealLine(displayIndex)
            let y = CGFloat(displayIndex) * height

            if let selected = selectedLineRange, selected.contains(realLine) {
                context.setFillColor(theme.selectionBackground.cgColor)
                context.fill(CGRect(x: Self.gutterWidth, y: y, width: dirtyRect.width, height: height))
            }
            if let range = searchMatches[realLine] {
                let isCurrent = realLine == currentSearchLine
                context.setFillColor((isCurrent ? theme.searchCurrentFill : theme.searchMatchFill).cgColor)
                let x = Self.gutterWidth + Self.horizontalPadding + CGFloat(range.location) * approximateCharacterWidth
                context.fill(CGRect(x: x, y: y, width: max(4, CGFloat(range.length) * approximateCharacterWidth), height: height))
            }

            let lineNumber = "\(realLine + 1)"
            let numberSize = (lineNumber as NSString).size(withAttributes: lineNumberAttributes)
            let numberPoint = NSPoint(x: Self.gutterWidth - numberSize.width - 8, y: y)
            (lineNumber as NSString).draw(at: numberPoint, withAttributes: lineNumberAttributes)

            let text = backing.lineText(at: realLine)
            let displayText = text.count > 2000 ? String(text.prefix(2000)) + " …" : text
            let attributed = attributedLine(displayText, baseAttributes: textAttributes)
            attributed.draw(at: NSPoint(x: Self.gutterWidth + Self.horizontalPadding, y: y))

            if realLine == currentSearchLine {
                context.setFillColor(theme.searchCurrentFill.withAlphaComponent(0.12).cgColor)
                context.fill(CGRect(x: Self.gutterWidth, y: y, width: dirtyRect.width, height: height))
            }
        }

        if !backing.isIndexReady, displayedLineCount <= 1 {
            let message = "Indexing file… \(Int(backing.indexProgress * 100))%"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let size = (message as NSString).size(withAttributes: attributes)
            (message as NSString).draw(at: NSPoint(x: Self.gutterWidth + 20, y: 20), withAttributes: attributes)
            _ = size
        }

        let firstReal = displayIndexToRealLine(first)
        if firstReal != lastReportedFirstLine {
            lastReportedFirstLine = firstReal
            onVisibleLineChanged?()
        }
    }

    private var approximateCharacterWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font]).width
    }

    private func attributedLine(_ text: String, baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
        guard highlightRules.isEnabled, !text.isEmpty else { return attributed }
        let upper = text.uppercased()
        for (token, color) in highlightRules.tokens {
            if let found = upper.range(of: token) {
                let location = upper.distance(from: upper.startIndex, to: found.lowerBound)
                let length = token.count
                if location + length <= attributed.length {
                    attributed.addAttribute(.foregroundColor, value: color,
                                            range: NSRange(location: location, length: length))
                }
            }
        }
        return attributed
    }

    // MARK: - Selection and copy

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let displayIndex = max(0, min(displayedLineCount - 1, Int(floor(point.y / lineHeight))))
        let realLine = displayIndexToRealLine(displayIndex)
        selectedLineRange = realLine...realLine
        needsDisplay = true
        onSelectionChanged?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = selectedLineRange?.lowerBound else { return }
        let point = convert(event.locationInWindow, from: nil)
        let displayIndex = max(0, min(displayedLineCount - 1, Int(floor(point.y / lineHeight))))
        let realLine = displayIndexToRealLine(displayIndex)
        selectedLineRange = min(anchor, realLine)...max(anchor, realLine)
        needsDisplay = true
        onSelectionChanged?()
    }

    var selectedText: String {
        guard let range = selectedLineRange else { return "" }
        let lineCount = range.upperBound - range.lowerBound + 1
        // Copy cap keeps memory bounded on enormous selections.
        let capped = min(lineCount, 100_000)
        var lines: [String] = []
        lines.reserveCapacity(capped)
        for line in range.lowerBound..<(range.lowerBound + capped) {
            lines.append(backing.lineText(at: line))
        }
        var text = lines.joined(separator: "\n")
        if lineCount > capped {
            text += "\n… copied first \(capped) of \(lineCount) selected lines (PlainX copy cap)."
        }
        return text
    }

    @objc func copy(_ sender: Any?) {
        let text = selectedText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc override func selectAll(_ sender: Any?) {
        selectedLineRange = 0...max(0, displayedLineCount - 1)
        needsDisplay = true
        onSelectionChanged?()
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            copy(nil)
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a" {
            selectAll(nil)
            return
        }
        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func accessibilityLabel() -> String? {
        "Large file viewer, read-only"
    }
}
