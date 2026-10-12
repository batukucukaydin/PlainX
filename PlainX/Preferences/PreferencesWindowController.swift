//
//  PreferencesWindowController.swift
//  PlainX Editor
//
//  Compact, native preferences window. Every setting has a real default and
//  an immediate effect.
//

import AppKit

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private unowned var coordinator: AppCoordinator?
    private var tabView: NSTabView!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "PlainX Editor Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        refreshFromPreferences()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI construction helpers

    private let preferences = Preferences.shared

    private var fontNamePopup: NSPopUpButton!
    private var fontSizeField: NSTextField!
    private var themePopup: NSPopUpButton!
    private var lineNumbersCheckbox: NSButton!
    private var whitespaceCheckbox: NSButton!
    private var eolCheckbox: NSButton!
    private var indentGuidesCheckbox: NSButton!
    private var currentLineCheckbox: NSButton!
    private var wrapCheckbox: NSButton!
    private var tabWidthPopup: NSPopUpButton!
    private var useTabsCheckbox: NSButton!
    private var sessionCheckbox: NSButton!
    private var recoveryCheckbox: NSButton!
    private var recoveryIntervalField: NSTextField!
    private var recoverOnLaunchCheckbox: NSButton!
    private var updatesCheckbox: NSButton!
    private var defaultEOLPopup: NSPopUpButton!
    private var defaultEncodingPopup: NSPopUpButton!
    private var trimOnSaveCheckbox: NSButton!
    private var finalNewlineCheckbox: NSButton!
    private var excludedDirectoriesField: NSTextField!
    private var largeFileThresholdField: NSTextField!
    private var largeFileModePopup: NSPopUpButton!

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder
        contentView.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])

        tabView.addTabViewItem(makeTab("General", view: buildGeneral()))
        tabView.addTabViewItem(makeTab("Editor", view: buildEditor()))
        tabView.addTabViewItem(makeTab("Appearance", view: buildAppearance()))
        tabView.addTabViewItem(makeTab("Files & Encoding", view: buildFiles()))
        tabView.addTabViewItem(makeTab("Search", view: buildSearch()))
        tabView.addTabViewItem(makeTab("Large Files", view: buildLargeFiles()))
        tabView.addTabViewItem(makeTab("Advanced", view: buildAdvanced()))
    }

    private func makeTab(_ label: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = view
        return item
    }

    private func makeGrid(rows: [NSView], title: String) -> NSView {
        let container = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let header = NSTextField(labelWithString: title)
        header.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        stack.addArrangedSubview(header)
        for row in rows {
            stack.addArrangedSubview(row)
        }
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
        ])
        return container
    }

    private func checkbox(_ title: String, value: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = value ? .on : .off
        return button
    }

    private func label(_ text: String, width: CGFloat = 130) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func row(_ labelText: String, _ control: NSView) -> NSView {
        let stack = NSStackView(views: [label(labelText), control])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    // MARK: - Tabs

    private func buildGeneral() -> NSView {
        sessionCheckbox = checkbox("Restore windows and tabs on launch", value: true, action: #selector(sessionChanged))
        recoveryCheckbox = checkbox("Save recovery snapshots of unsaved documents", value: true, action: #selector(recoveryChanged))
        recoverOnLaunchCheckbox = checkbox("Offer to recover unsaved documents after a crash", value: true, action: #selector(recoverOnLaunchChanged))
        recoveryIntervalField = NSTextField(string: "5")
        recoveryIntervalField.target = self
        recoveryIntervalField.action = #selector(recoveryIntervalChanged)
        recoveryIntervalField.translatesAutoresizingMaskIntoConstraints = false
        recoveryIntervalField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        updatesCheckbox = checkbox("Check for updates automatically (disabled by default)", value: false, action: #selector(updatesChanged))

        return makeGrid(rows: [
            sessionCheckbox,
            recoveryCheckbox,
            recoverOnLaunchCheckbox,
            row("Snapshot interval (s):", recoveryIntervalField),
            updatesCheckbox,
        ], title: "Session & Recovery")
    }

    private func buildEditor() -> NSView {
        fontNamePopup = NSPopUpButton()
        let families = NSFontManager.shared.availableFontFamilies.filter { family in
            NSFont(name: family, size: 12) != nil
        }
        let monospaced = ["SF Mono", "Menlo", "Monaco", "Courier New"].filter { families.contains($0) }
        fontNamePopup.addItems(withTitles: monospaced + families.filter { !monospaced.contains($0) }.sorted())
        fontNamePopup.target = self
        fontNamePopup.action = #selector(fontChanged)
        fontNamePopup.translatesAutoresizingMaskIntoConstraints = false

        fontSizeField = NSTextField(string: "13")
        fontSizeField.target = self
        fontSizeField.action = #selector(fontChanged)
        fontSizeField.translatesAutoresizingMaskIntoConstraints = false
        fontSizeField.widthAnchor.constraint(equalToConstant: 50).isActive = true

        lineNumbersCheckbox = checkbox("Show line numbers", value: true, action: #selector(editorTogglesChanged))
        whitespaceCheckbox = checkbox("Show whitespace", value: false, action: #selector(editorTogglesChanged))
        eolCheckbox = checkbox("Show end-of-line characters", value: false, action: #selector(editorTogglesChanged))
        indentGuidesCheckbox = checkbox("Show indent guides", value: false, action: #selector(editorTogglesChanged))
        currentLineCheckbox = checkbox("Highlight current line", value: true, action: #selector(editorTogglesChanged))
        wrapCheckbox = checkbox("Wrap long lines by default", value: false, action: #selector(editorTogglesChanged))
        useTabsCheckbox = checkbox("Indent using tabs", value: false, action: #selector(editorTogglesChanged))

        tabWidthPopup = NSPopUpButton()
        tabWidthPopup.addItems(withTitles: ["2", "4", "8"])
        tabWidthPopup.target = self
        tabWidthPopup.action = #selector(editorTogglesChanged)

        let fontRow = NSStackView(views: [label("Font:"), fontNamePopup, fontSizeField])
        fontRow.orientation = .horizontal
        fontRow.spacing = 8

        return makeGrid(rows: [
            fontRow,
            tabWidthPopupWidthRow(),
            useTabsCheckbox,
            lineNumbersCheckbox,
            wrapCheckbox,
            whitespaceCheckbox,
            eolCheckbox,
            indentGuidesCheckbox,
            currentLineCheckbox,
        ], title: "Editor")
    }

    private func tabWidthPopupWidthRow() -> NSView {
        row("Tab width:", tabWidthPopup)
    }

    private func buildAppearance() -> NSView {
        themePopup = NSPopUpButton()
        themePopup.addItems(withTitles: ThemeChoice.allCases.map(\.displayName))
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        return makeGrid(rows: [
            row("Theme:", themePopup),
        ], title: "Appearance")
    }

    private func buildFiles() -> NSView {
        defaultEOLPopup = NSPopUpButton()
        defaultEOLPopup.addItems(withTitles: ["Unix (LF)", "Windows (CRLF)", "Classic Mac (CR)"])
        defaultEOLPopup.target = self
        defaultEOLPopup.action = #selector(filesChanged)

        defaultEncodingPopup = NSPopUpButton()
        defaultEncodingPopup.addItems(withTitles: TextEncoding.selectable.filter { !$0.hasBOM }.map(\.displayName))
        defaultEncodingPopup.target = self
        defaultEncodingPopup.action = #selector(filesChanged)

        trimOnSaveCheckbox = checkbox("Trim trailing whitespace on save", value: false, action: #selector(filesChanged))
        finalNewlineCheckbox = checkbox("Ensure a final newline on save", value: false, action: #selector(filesChanged))

        return makeGrid(rows: [
            row("New file line endings:", defaultEOLPopup),
            row("New file encoding:", defaultEncodingPopup),
            trimOnSaveCheckbox,
            finalNewlineCheckbox,
        ], title: "Files & Encoding")
    }

    private func buildSearch() -> NSView {
        excludedDirectoriesField = NSTextField(string: "")
        excludedDirectoriesField.translatesAutoresizingMaskIntoConstraints = false
        excludedDirectoriesField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        excludedDirectoriesField.target = self
        excludedDirectoriesField.action = #selector(searchChanged)
        excludedDirectoriesField.placeholderString = ".git, node_modules, build…"
        return makeGrid(rows: [
            row("Ignored folders:", excludedDirectoriesField),
        ], title: "Find in Files")
    }

    private func buildLargeFiles() -> NSView {
        largeFileThresholdField = NSTextField(string: "64")
        largeFileThresholdField.target = self
        largeFileThresholdField.action = #selector(largeFileChanged)
        largeFileThresholdField.translatesAutoresizingMaskIntoConstraints = false
        largeFileThresholdField.widthAnchor.constraint(equalToConstant: 70).isActive = true

        largeFileModePopup = NSPopUpButton()
        largeFileModePopup.addItems(withTitles: LargeFileOpenMode.allCases.map(\.displayName))
        largeFileModePopup.target = self
        largeFileModePopup.action = #selector(largeFileChanged)

        let note = NSTextField(wrappingLabelWithString:
            "Files at or above this size open in the read-only Large File Viewer, which never loads the whole file into memory. Search, copy, and follow/tail remain available.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 420

        return makeGrid(rows: [
            row("Threshold (MB):", largeFileThresholdField),
            row("When a large file is opened:", largeFileModePopup),
            note,
        ], title: "Large Files")
    }

    private func buildAdvanced() -> NSView {
        let diagnosticsButton = NSButton(title: "Copy Diagnostics", target: self, action: #selector(copyDiagnostics))
        diagnosticsButton.bezelStyle = .rounded
        let resetButton = NSButton(title: "Reset All Settings…", target: self, action: #selector(resetDefaults))
        resetButton.bezelStyle = .rounded
        let note = NSTextField(wrappingLabelWithString:
            "PlainX Editor stores preferences in your user defaults, and session/macro/recovery data in Application Support. Nothing is transmitted anywhere.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 420
        return makeGrid(rows: [diagnosticsButton, resetButton, note], title: "Advanced")
    }

    // MARK: - Refresh & actions

    private func refreshFromPreferences() {
        sessionCheckbox.state = preferences.sessionRestoreEnabled ? .on : .off
        recoveryCheckbox.state = preferences.recoveryEnabled ? .on : .off
        recoverOnLaunchCheckbox.state = preferences.recoverUnsavedOnLaunch ? .on : .off
        recoveryIntervalField.stringValue = "\(Int(preferences.recoveryInterval))"
        updatesCheckbox.state = preferences.checkForUpdates ? .on : .off

        fontNamePopup.selectItem(withTitle: preferences.fontName)
        fontSizeField.stringValue = "\(Int(preferences.fontSize))"
        lineNumbersCheckbox.state = preferences.showLineNumbers ? .on : .off
        whitespaceCheckbox.state = preferences.showWhitespace ? .on : .off
        eolCheckbox.state = preferences.showEOL ? .on : .off
        indentGuidesCheckbox.state = preferences.showIndentGuides ? .on : .off
        currentLineCheckbox.state = preferences.highlightCurrentLine ? .on : .off
        wrapCheckbox.state = preferences.wordWrapDefault ? .on : .off
        useTabsCheckbox.state = preferences.useTabs ? .on : .off
        tabWidthPopup.selectItem(withTitle: "\(preferences.tabWidth)")

        switch preferences.themeChoice {
        case .system: themePopup.selectItem(at: 0)
        case .light: themePopup.selectItem(at: 1)
        case .dark: themePopup.selectItem(at: 2)
        }

        switch preferences.defaultEOL {
        case .lf: defaultEOLPopup.selectItem(at: 0)
        case .crlf: defaultEOLPopup.selectItem(at: 1)
        case .cr: defaultEOLPopup.selectItem(at: 2)
        case .mixed: defaultEOLPopup.selectItem(at: 0)
        }
        defaultEncodingPopup.selectItem(withTitle: preferences.defaultEncoding.displayName)
        trimOnSaveCheckbox.state = preferences.trimTrailingWhitespaceOnSave ? .on : .off
        finalNewlineCheckbox.state = preferences.ensureFinalNewlineOnSave ? .on : .off
        excludedDirectoriesField.stringValue = preferences.searchExcludedDirectories.joined(separator: ", ")
        largeFileThresholdField.stringValue = "\(preferences.largeFileThresholdMB)"
        largeFileModePopup.selectItem(withTitle: preferences.largeFileOpenMode.displayName)
    }

    private func propagateEditorChanges() {
        for window in coordinator?.windows ?? [] {
            for tab in window.tabs {
                guard let editorTab = tab as? DocumentTabController else { continue }
                for pane in editorTab.panes {
                    pane.applyEditorPreferences()
                }
            }
        }
    }

    @objc private func sessionChanged() {
        preferences.sessionRestoreEnabled = sessionCheckbox.state == .on
    }

    @objc private func recoveryChanged() {
        preferences.recoveryEnabled = recoveryCheckbox.state == .on
        coordinator?.startRecoveryTimer()
    }

    @objc private func recoverOnLaunchChanged() {
        preferences.recoverUnsavedOnLaunch = recoverOnLaunchCheckbox.state == .on
    }

    @objc private func recoveryIntervalChanged() {
        if let value = Double(recoveryIntervalField.stringValue), value >= 1 {
            preferences.recoveryInterval = value
            coordinator?.startRecoveryTimer()
        }
    }

    @objc private func updatesChanged() {
        preferences.checkForUpdates = updatesCheckbox.state == .on
    }

    @objc private func fontChanged() {
        preferences.fontName = fontNamePopup.titleOfSelectedItem ?? Preferences.defaultFontName
        if let size = Double(fontSizeField.stringValue), size >= 6, size <= 72 {
            preferences.fontSize = CGFloat(size)
        }
        propagateEditorChanges()
    }

    @objc private func editorTogglesChanged() {
        preferences.showLineNumbers = lineNumbersCheckbox.state == .on
        preferences.showWhitespace = whitespaceCheckbox.state == .on
        preferences.showEOL = eolCheckbox.state == .on
        preferences.showIndentGuides = indentGuidesCheckbox.state == .on
        preferences.highlightCurrentLine = currentLineCheckbox.state == .on
        preferences.wordWrapDefault = wrapCheckbox.state == .on
        preferences.useTabs = useTabsCheckbox.state == .on
        if let width = Int(tabWidthPopup.titleOfSelectedItem ?? "4") {
            preferences.tabWidth = width
        }
        propagateEditorChanges()
    }

    @objc private func themeChanged() {
        switch themePopup.indexOfSelectedItem {
        case 1: preferences.themeChoice = .light
        case 2: preferences.themeChoice = .dark
        default: preferences.themeChoice = .system
        }
        for window in coordinator?.windows ?? [] {
            window.applyThemeChange()
        }
    }

    @objc private func filesChanged() {
        switch defaultEOLPopup.indexOfSelectedItem {
        case 1: preferences.defaultEOL = .crlf
        case 2: preferences.defaultEOL = .cr
        default: preferences.defaultEOL = .lf
        }
        if let encoding = TextEncoding.selectable.first(where: { $0.displayName == defaultEncodingPopup.titleOfSelectedItem }) {
            preferences.defaultEncoding = encoding
        }
        preferences.trimTrailingWhitespaceOnSave = trimOnSaveCheckbox.state == .on
        preferences.ensureFinalNewlineOnSave = finalNewlineCheckbox.state == .on
    }

    @objc private func searchChanged() {
        preferences.searchExcludedDirectories = excludedDirectoriesField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @objc private func largeFileChanged() {
        if let value = Int(largeFileThresholdField.stringValue), value > 0 {
            preferences.largeFileThresholdMB = value
        }
        switch largeFileModePopup.indexOfSelectedItem {
        case 1: preferences.largeFileOpenMode = .ask
        case 2: preferences.largeFileOpenMode = .alwaysRegular
        default: preferences.largeFileOpenMode = .automatic
        }
    }

    @objc private func copyDiagnostics() {
        coordinator?.copyDiagnostics()
    }

    @objc private func resetDefaults() {
        let alert = NSAlert()
        alert.messageText = "Reset all PlainX settings to defaults?"
        alert.informativeText = "Session, recovery, and macro data are not affected."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let bundleID = Bundle.main.bundleIdentifier,
           let domain = UserDefaults.standard.persistentDomain(forName: bundleID) {
            for key in domain.keys where key.hasPrefix("editor.") || key.hasPrefix("files.")
                || key.hasPrefix("session.") || key.hasPrefix("recovery.") || key.hasPrefix("largeFiles.")
                || key.hasPrefix("updates.") || key.hasPrefix("appearance.") || key.hasPrefix("search.")
                || key.hasPrefix("app.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        refreshFromPreferences()
        propagateEditorChanges()
    }
}
