//
//  WelcomeTabController.swift
//  PlainX Editor
//
//  First-launch / empty-window screen: brand, primary actions, recent files,
//  and a few keyboard hints. Restrained and native — no animation, no noise.
//

import AppKit

final class WelcomeTabController: DocumentTab {
    let id = UUID()
    let document: PlainXDocument
    weak var tabDelegate: DocumentTabControllerDelegate?
    weak var window: MainWindowController?

    private let viewController: WelcomeViewController

    var tabContentView: NSView { viewController.view }
    var isSplit: Bool { false }
    var isLargeFileViewer: Bool { false }
    var isWelcome: Bool { true }

    init(document: PlainXDocument, coordinator: AppCoordinator, window: MainWindowController) {
        self.document = document
        self.window = window
        self.viewController = WelcomeViewController(coordinator: coordinator, window: window)
    }

    func statusSnapshot() -> StatusBarView.State {
        StatusBarView.State(encodingName: "", encodingTooltip: "", eolName: "", eolTooltip: "",
                            languageName: "", languageTooltip: "", indentationName: "",
                            line: 0, column: 0, selectionSummary: "", fileSizeSummary: "",
                            modeSummary: "")
    }

    func saveViewStates() {}
    func markClean() { document.isDirty = false }
    func markDirtyIfNeeded() {}
    func focusContent() {
        window?.window?.makeFirstResponder(viewController.primaryButton)
    }
}

final class WelcomeViewController: NSViewController {
    private unowned let coordinator: AppCoordinator
    private weak var window: MainWindowController?
    private(set) var primaryButton = NSButton()

    init(coordinator: AppCoordinator, window: MainWindowController) {
        self.coordinator = coordinator
        self.window = window
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let title = NSTextField(labelWithString: "PlainX Editor")
        title.font = NSFont.systemFont(ofSize: 26, weight: .semibold)

        let tagline = NSTextField(labelWithString: "Plain text. Extra power.")
        tagline.font = NSFont.systemFont(ofSize: 13)
        tagline.textColor = .secondaryLabelColor

        primaryButton = NSButton(title: "New File", target: self, action: #selector(newFile))
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.setAccessibilityLabel("Create a new file")

        let openButton = NSButton(title: "Open File…", target: self, action: #selector(openFile))
        openButton.bezelStyle = .rounded
        openButton.setAccessibilityLabel("Open a file")

        let openFolderButton = NSButton(title: "Open Folder for Search…", target: self, action: #selector(openFolder))
        openFolderButton.bezelStyle = .rounded
        openFolderButton.setAccessibilityLabel("Open a folder for Find in Files")

        let buttonRow = NSStackView(views: [primaryButton, openButton, openFolderButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(tagline)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(buttonRow)

        // Recent files
        let recents = Array(coordinator.recentURLs.prefix(8))
        if !recents.isEmpty {
            let recentTitle = NSTextField(labelWithString: "Recent Files")
            recentTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            recentTitle.textColor = .secondaryLabelColor
            let recentStack = NSStackView()
            recentStack.orientation = .vertical
            recentStack.alignment = .leading
            recentStack.spacing = 2
            for url in recents {
                let button = NSButton(title: url.lastPathComponent, target: self, action: #selector(openRecent(_:)))
                button.isBordered = false
                button.bezelStyle = .recessed
                button.contentTintColor = .linkColor
                button.font = NSFont.systemFont(ofSize: 12)
                button.toolTip = url.path
                button.alignment = .left
                button.lineBreakMode = .byTruncatingMiddle
                button.identifier = NSUserInterfaceItemIdentifier(url.path)
                recentStack.addArrangedSubview(button)
            }
            stack.addArrangedSubview(NSView())
            stack.addArrangedSubview(recentTitle)
            stack.addArrangedSubview(recentStack)
        }

        // Shortcut hints
        let hints = NSTextField(labelWithString:
            "⌘F Find   ⇧⌘F Find in Files   ⇧⌘P Command Palette   ⌘L Go to Line   ⌘/ Toggle Comment")
        hints.font = NSFont.systemFont(ofSize: 11)
        hints.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(hints)

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -20),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -40),
        ])
        view = root
    }

    @objc private func newFile() {
        coordinator.newDocument(in: window)
    }

    @objc private func openFile() {
        coordinator.showOpenPanel(in: window)
    }

    @objc private func openFolder() {
        coordinator.showOpenFolderPanel(in: window)
    }

    @objc private func openRecent(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        coordinator.open(urls: [URL(fileURLWithPath: path)], in: window)
    }
}
