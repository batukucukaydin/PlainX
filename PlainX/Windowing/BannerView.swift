//
//  BannerView.swift
//  PlainX Editor
//
//  Non-blocking banner used for external-change notices, large-file
//  decisions, and similar contextual prompts.
//

import AppKit

final class BannerView: NSView {
    enum Style {
        case info
        case warning
    }

    struct Action {
        let title: String
        let handler: () -> Void
        var isDestructive: Bool = false
    }

    private let label = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let buttonStack = NSStackView()
    private let dismissButton = NSButton()
    private var actions: [Action] = []

    var onDismiss: (() -> Void)?

    init() {
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.isBordered = false
        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        dismissButton.contentTintColor = .secondaryLabelColor
        dismissButton.target = self
        dismissButton.action = #selector(handleDismiss)

        addSubview(iconView)
        addSubview(label)
        addSubview(buttonStack)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.leadingAnchor.constraint(equalTo: buttonStack.trailingAnchor, constant: 10),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    func show(message: String, actions: [Action], style: Style = .warning) {
        self.actions = actions
        label.stringValue = message
        iconView.image = NSImage(systemSymbolName: style == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill",
                                 accessibilityDescription: nil)
        iconView.contentTintColor = style == .warning ? .systemOrange : .controlAccentColor
        layer?.backgroundColor = (style == .warning ? NSColor.systemOrange : NSColor.controlAccentColor)
            .withAlphaComponent(0.10).cgColor

        buttonStack.arrangedSubviews.forEach {
            buttonStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.title, target: self, action: #selector(handleAction(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = index
            if action.isDestructive {
                button.hasDestructiveAction = true
            }
            buttonStack.addArrangedSubview(button)
        }
    }

    @objc private func handleAction(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < actions.count else { return }
        let handler = actions[index].handler
        handler()
    }

    @objc private func handleDismiss() {
        onDismiss?()
    }
}
