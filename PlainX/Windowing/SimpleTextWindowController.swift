//
//  SimpleTextWindowController.swift
//  PlainX Editor
//
//  Read-only text window used for keyboard shortcuts and release notes.
//

import AppKit

final class SimpleTextWindowController: NSWindowController {
    static let shared = SimpleTextWindowController()

    private let textView = NSTextView()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.setFrameAutosaveName("PlainXTextWindow")
        super.init(window: window)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        if let contentView = window.contentView {
            contentView.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(title: String, text: String) {
        window?.title = title
        textView.string = text
        textView.scrollToBeginningOfDocument(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum ShortcutReference {
    static func markdown() -> String {
        var lines: [String] = ["PlainX Editor — Keyboard Shortcuts", ""]
        let categories = CommandRegistry.shared.categories
        for category in categories {
            let commands = CommandRegistry.shared.commands(inCategory: category)
                .filter { $0.keyBinding != nil }
            guard !commands.isEmpty else { continue }
            lines.append("\(category)")
            lines.append(String(repeating: "─", count: max(8, category.count)))
            for command in commands {
                let binding = command.keyBinding?.displayString ?? ""
                lines.append(String(format: "  %-34@ %@", command.title as NSString, binding))
            }
            lines.append("")
        }
        lines.append("The command palette (⇧⌘P) can run every command, including ones without shortcuts.")
        return lines.joined(separator: "\n")
    }
}

enum ReleaseNotes {
    static func text(version: String) -> String {
        """
        PlainX Editor \(version) — Release Notes

        Highlights
        • Native macOS text & code editor built on Scintilla and Lexilla.
        • Tabs, split views, session restore, and crash-safe recovery.
        • Powerful find/replace with regex, plus Find in Files with glob filters.
        • Large File Mode for very large logs (read-only, memory-mapped, searchable).
        • Built-in compare, macros, command palette, and developer transforms.
        • Encoding and line-ending conversion with conservative detection.
        • No telemetry, no accounts, local-only by default.

        See docs/performance.md in the repository for measured benchmarks and
        CHANGELOG.md for the detailed history.
        """
    }
}
