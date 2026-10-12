//
//  StatusBarView.swift
//  PlainX Editor
//
//  The editor status bar. Fields are clickable where a quick action makes
//  sense (encoding, line endings, language, indentation).
//

import AppKit

protocol StatusBarViewDelegate: AnyObject {
    func statusBarDidRequestEncodingMenu(_ statusBar: StatusBarView, anchor: NSView)
    func statusBarDidRequestEOLMenu(_ statusBar: StatusBarView, anchor: NSView)
    func statusBarDidRequestLanguageMenu(_ statusBar: StatusBarView, anchor: NSView)
    func statusBarDidRequestIndentationMenu(_ statusBar: StatusBarView, anchor: NSView)
    func statusBarDidRequestGoToLine(_ statusBar: StatusBarView)
}

final class StatusBarView: NSView {
    weak var delegate: StatusBarViewDelegate?

    private let encodingButton = StatusBarView.makeButton()
    private let eolButton = StatusBarView.makeButton()
    private let languageButton = StatusBarView.makeButton()
    private let indentationButton = StatusBarView.makeButton()
    private let positionLabel = StatusBarView.makeLabel()
    private let selectionLabel = StatusBarView.makeLabel()
    private let sizeLabel = StatusBarView.makeLabel()
    private let modeLabel = StatusBarView.makeLabel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private static func makeButton() -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .recessed
        button.font = NSFont.systemFont(ofSize: 11)
        button.contentTintColor = .secondaryLabelColor
        button.setButtonType(.momentaryChange)
        return button
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let stack = NSStackView(views: [
            encodingButton, eolButton, languageButton, indentationButton,
            NSView(), positionLabel, selectionLabel, sizeLabel, modeLabel,
        ])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        stack.views[4].setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.views[4].setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(stack)

        encodingButton.target = self
        encodingButton.action = #selector(handleEncoding)
        eolButton.target = self
        eolButton.action = #selector(handleEOL)
        languageButton.target = self
        languageButton.action = #selector(handleLanguage)
        indentationButton.target = self
        indentationButton.action = #selector(handleIndentation)

        positionLabel.toolTip = "Go to Line…"
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleGoToLine))
        positionLabel.addGestureRecognizer(clickGesture)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: separator.bottomAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    struct State {
        var encodingName: String
        var encodingTooltip: String
        var eolName: String
        var eolTooltip: String
        var languageName: String
        var languageTooltip: String
        var indentationName: String
        var line: Int
        var column: Int
        var selectionSummary: String
        var fileSizeSummary: String
        var modeSummary: String
    }

    func update(state: State) {
        encodingButton.title = state.encodingName
        encodingButton.toolTip = state.encodingTooltip
        eolButton.title = state.eolName
        eolButton.toolTip = state.eolTooltip
        languageButton.title = state.languageName
        languageButton.toolTip = state.languageTooltip
        indentationButton.title = state.indentationName
        positionLabel.stringValue = "Ln \(state.line + 1), Col \(state.column + 1)"
        selectionLabel.stringValue = state.selectionSummary
        sizeLabel.stringValue = state.fileSizeSummary
        modeLabel.stringValue = state.modeSummary
        modeLabel.textColor = state.modeSummary.isEmpty ? .secondaryLabelColor : .systemOrange
    }

    @objc private func handleEncoding() { delegate?.statusBarDidRequestEncodingMenu(self, anchor: encodingButton) }
    @objc private func handleEOL() { delegate?.statusBarDidRequestEOLMenu(self, anchor: eolButton) }
    @objc private func handleLanguage() { delegate?.statusBarDidRequestLanguageMenu(self, anchor: languageButton) }
    @objc private func handleIndentation() { delegate?.statusBarDidRequestIndentationMenu(self, anchor: indentationButton) }
    @objc private func handleGoToLine() { delegate?.statusBarDidRequestGoToLine(self) }
}
