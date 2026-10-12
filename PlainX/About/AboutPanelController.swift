//
//  AboutPanelController.swift
//  PlainX Editor
//

import AppKit

enum AboutPanelController {
    static func show() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "About PlainX Editor"
        window.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        if let logo = NSImage(named: "PlainX-Logo") ?? Bundle.main.image(forResource: "PlainX-Logo") {
            icon.image = logo
        } else {
            icon.image = NSApp.applicationIconImage
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 120).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let title = NSTextField(labelWithString: "PlainX Editor")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        let tagline = NSTextField(labelWithString: "Plain text. Extra power.")
        tagline.font = NSFont.systemFont(ofSize: 13)
        tagline.textColor = .secondaryLabelColor

        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build)) · \(Hardware.architectureString())")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor

        let description = NSTextField(wrappingLabelWithString:
            "A fast, lightweight and powerful native text & code editor for macOS. Local-first: no accounts, no telemetry, no document contents leave your Mac.")
        description.alignment = .center
        description.font = NSFont.systemFont(ofSize: 11)
        description.textColor = .secondaryLabelColor
        description.preferredMaxLayoutWidth = 340

        let license = NSTextField(labelWithString: "MIT licensed · Built with Scintilla & Lexilla")
        license.font = NSFont.systemFont(ofSize: 11)
        license.textColor = .tertiaryLabelColor

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(tagline)
        stack.addArrangedSubview(versionLabel)
        stack.addArrangedSubview(description)
        stack.addArrangedSubview(license)

        if let contentView = window.contentView {
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            ])
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        aboutWindow = window
    }

    private static var aboutWindow: NSWindow?
}
