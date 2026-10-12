//
//  AppCoordinator+Actions.swift
//  PlainX Editor
//
//  Command implementations that need dialogs or multi-step UI flows.
//

import AppKit

extension AppCoordinator {

    // MARK: - Open panels

    func showOpenPanel(in window: MainWindowController?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files to open. Folders become search roots."
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK else { return }
            self.openDroppedItems(panel.urls, in: window)
        }
        if let window = window?.window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    func showOpenFolderPanel(in window: MainWindowController?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to search"
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: "search.lastRoot")
            self.promptFindInFiles(root: url)
        }
        if let window = window?.window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    // MARK: - Rename

    func promptRename(tab: DocumentTabController?) {
        guard let tab, let url = tab.document.url, let window = tab.controller.window else { return }
        TextPrompt.present(title: "Rename File",
                           message: "Enter a new name for “\(url.lastPathComponent)”.",
                           initialValue: url.lastPathComponent,
                           in: window) { [weak self] newName in
            guard let self else { return }
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != url.lastPathComponent else { return }
            let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed)
            do {
                try FileManager.default.moveItem(at: url, to: destination)
                tab.document.rename(to: destination)
                if let metadata = FileLoader.metadata(for: destination) {
                    tab.document.lastKnownMetadata = metadata
                }
                if tab.document.languageOverrideID == nil {
                    tab.activePane.setLanguage(LanguageRegistry.language(for: destination))
                }
                tab.controller.stopWatching(tab.document)
                tab.controller.startWatching(tab.document)
                tab.controller.updateTabStrip()
                tab.controller.updateWindowTitle()
                self.addRecentFile(destination)
            } catch {
                self.presentError(error, in: tab.controller)
            }
        }
    }

    // MARK: - Split lines

    func promptSplitLines(tab: DocumentTabController?) {
        guard let tab, let window = tab.controller.window else { return }
        TextPrompt.present(title: "Split Lines",
                           message: "Split every line at this delimiter.",
                           initialValue: ",",
                           in: window) { [weak self] delimiter in
            guard let self, !delimiter.isEmpty else { return }
            tab.performSyncedEdit { pane in
                TransformService.apply(to: pane) {
                    TransformService.splitLinesOnSeparator(delimiter, in: $0)
                }
            }
            tab.markDirtyIfNeeded()
            _ = self
        }
    }

    // MARK: - Comments

    func toggleComment(tab: DocumentTabController?) {
        guard let tab else { return }
        let language = tab.document.language
        if let lineComment = language.lineComment {
            toggleLineComment(tab: tab, token: lineComment)
        } else if let blockComment = language.blockComment {
            toggleBlockComment(tab: tab, start: blockComment.start, end: blockComment.end)
        } else {
            NSSound.beep()
        }
    }

    private func toggleLineComment(tab: DocumentTabController, token: String) {
        let pane = tab.activePane
        let selections = pane.facade.allSelections()
        var lineRanges: [(first: Int, last: Int)] = []
        for selection in selections {
            let first = pane.facade.line(from: selection.lowerBound)
            let last = pane.facade.line(from: max(selection.upperBound - (selection.isEmpty ? 0 : 1), selection.lowerBound))
            lineRanges.append((first, last))
        }
        // Determine whether every line is already commented.
        var allCommented = true
        for range in lineRanges {
            for line in range.first...range.last {
                let text = pane.facade.lineText(line).trimmingCharacters(in: .whitespaces)
                if !text.hasPrefix(token) {
                    allCommented = false
                    break
                }
            }
            if !allCommented { break }
        }

        pane.facade.beginUndoAction()
        for range in lineRanges.reversed() {
            for line in stride(from: range.last, through: range.first, by: -1) {
                let start = pane.facade.lineStart(line)
                if allCommented {
                    let text = pane.facade.lineText(line)
                    if let tokenRange = text.range(of: token) {
                        let offset = text.distance(from: text.startIndex, to: tokenRange.lowerBound)
                        var length = token.utf8.count
                        let textAfter = String(text[tokenRange.upperBound...])
                        if textAfter.hasPrefix(" ") { length += 1 }
                        pane.facade.deleteRange(location: start + offset, length: length)
                    }
                } else {
                    let indentation = indentationWidth(of: pane.facade.lineText(line))
                    pane.facade.insert(text: token + " ", at: start + indentation)
                }
            }
        }
        pane.facade.endUndoAction()
        tab.markDirtyIfNeeded()
    }

    private func indentationWidth(of line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " { count += 1 } else if character == "\t" { count += 4 } else { break }
        }
        return count
    }

    private func toggleBlockComment(tab: DocumentTabController, start: String, end: String) {
        let pane = tab.activePane
        let selection = pane.facade.mainSelection
        guard !selection.isEmpty else {
            NSSound.beep()
            return
        }
        let maxPosition = pane.facade.length
        let startPosition = min(selection.lowerBound, maxPosition)
        let endPosition = min(selection.upperBound, maxPosition)
        let selected = pane.facade.text(inRange: NSRange(location: startPosition, length: endPosition - startPosition))
        pane.facade.beginUndoAction()
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(start), trimmed.hasSuffix(end), trimmed.count >= start.count + end.count {
            // Remove comment markers.
            var newText = selected
            if let startRange = newText.range(of: start) {
                newText.removeSubrange(startRange)
            }
            if let endRange = newText.range(of: end, options: .backwards) {
                newText.removeSubrange(endRange)
            }
            pane.facade.setSelection(anchor: startPosition, caret: endPosition)
            pane.facade.replaceTarget(with: newText, regex: false)
        } else {
            let replaced = start + selected + end
            pane.facade.setSelection(anchor: startPosition, caret: endPosition)
            pane.facade.replaceTarget(with: replaced, regex: false)
            pane.facade.setSelection(anchor: startPosition, caret: startPosition + replaced.utf8.count)
        }
        pane.facade.endUndoAction()
        tab.markDirtyIfNeeded()
    }

    // MARK: - Transforms UI

    func runTransform(context: CommandContext, name: String, transform: (String) throws -> String) {
        guard let pane = context.pane else { return }
        do {
            try TransformService.apply(to: pane, transform: transform)
            context.tab?.markDirtyIfNeeded()
            context.window?.updateTabStrip()
        } catch {
            presentTransformError(error, name: name, in: context.window)
        }
    }

    /// For hash commands: the result replaces the selection (or is inserted at
    /// the caret when nothing is selected).
    func runTransformReplacing(context: CommandContext, name: String, transform: (String) throws -> String) {
        guard let pane = context.pane else { return }
        let selection = pane.facade.mainSelection
        let source: String
        if selection.isEmpty {
            source = pane.facade.text
        } else {
            source = pane.facade.text(inRange: NSRange(location: selection.lowerBound, length: selection.length))
        }
        do {
            let digest = try transform(source)
            pane.facade.beginUndoAction()
            if selection.isEmpty {
                pane.facade.insert(text: digest, at: selection.caret)
            } else {
                pane.facade.setSelection(anchor: selection.lowerBound, caret: selection.upperBound)
                pane.facade.replaceTarget(with: digest, regex: false)
            }
            pane.facade.endUndoAction()
            context.tab?.markDirtyIfNeeded()
            context.window?.updateTabStrip()
        } catch {
            presentTransformError(error, name: name, in: context.window)
        }
    }

    func reportValidation(context: CommandContext, name: String, validate: (String) throws -> Void) {
        guard let pane = context.pane else { return }
        let selection = pane.facade.mainSelection
        let text = selection.isEmpty
            ? pane.facade.text
            : pane.facade.text(inRange: NSRange(location: selection.lowerBound, length: selection.length))
        let alert = NSAlert()
        do {
            try validate(text)
            alert.messageText = "\(name) is valid"
            alert.informativeText = selection.isEmpty ? "The document is well-formed." : "The selection is well-formed."
            alert.alertStyle = .informational
        } catch {
            alert.messageText = "\(name) problem found"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
        }
        alert.addButton(withTitle: "OK")
        if let window = context.window?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func presentTransformError(_ error: Error, name: String, in window: MainWindowController?) {
        let alert = NSAlert()
        alert.messageText = "\(name) failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = window?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Print

    func printDocument(tab: DocumentTabController?) {
        guard let tab else { return }
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.string = tab.activePane.facade.text
        let printInfo = NSPrintInfo.shared
        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = tab.controller.window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    // MARK: - Hashing open file

    func hashOpenFile(tab: DocumentTabController?) {
        guard let tab, let url = tab.document.url else { return }
        let alert = NSAlert()
        alert.messageText = "Hash of \(url.lastPathComponent)"
        alert.informativeText = "Computing SHA-256…"
        alert.addButton(withTitle: "OK")
        let window = tab.controller.window
        DispatchQueue.global(qos: .userInitiated).async {
            let digest = (try? TransformService.hash(fileAt: url, algorithm: .sha256)) ?? "error"
            DispatchQueue.main.async {
                alert.informativeText = digest
                if let window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(digest, forType: .string)
            }
        }
    }

    // MARK: - Termination

    /// Quit-time save flow. Uses modal panels so the quit decision is
    /// synchronous and reliable; called only from applicationShouldTerminate.
    func prepareForTermination(completion: @escaping (Bool) -> Void) {
        let dirtyTabs = windows.flatMap { window in
            window.tabs.compactMap { $0 as? DocumentTabController }.filter { $0.document.isDirty }
        }
        guard !dirtyTabs.isEmpty else {
            completion(true)
            return
        }
        let alert = NSAlert()
        alert.messageText = dirtyTabs.count == 1
            ? "You have one document with unsaved changes."
            : "You have \(dirtyTabs.count) documents with unsaved changes."
        alert.informativeText = "Save them before quitting?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for tab in dirtyTabs {
                let document = tab.document
                var url = document.url
                if url == nil {
                    let panel = NSSavePanel()
                    panel.canCreateDirectories = true
                    panel.nameFieldStringValue = document.displayName
                    guard panel.runModal() == .OK, let chosen = panel.url else {
                        completion(false)
                        return
                    }
                    document.rename(to: chosen)
                    url = chosen
                }
                guard let targetURL = url else {
                    completion(false)
                    return
                }
                var text = tab.activePane.facade.text
                if preferences.trimTrailingWhitespaceOnSave {
                    text = TransformService.trimTrailingWhitespace(in: text)
                }
                do {
                    let result = try FileSaver.save(text: text, to: targetURL, encoding: document.encoding,
                                                    lastKnownMetadata: document.lastKnownMetadata,
                                                    checkExternalModification: false, force: true)
                    document.lastKnownMetadata = result.metadata
                    tab.markClean()
                    addRecentFile(targetURL)
                } catch {
                    presentError(error, in: tab.controller)
                    completion(false)
                    return
                }
            }
            completion(true)
        case .alertSecondButtonReturn:
            completion(true)
        default:
            completion(false)
        }
    }

    // MARK: - Compare prompts

    func promptCompareWithFile(tab: DocumentTabController?) {
        guard let tab else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a file to compare with “\(tab.document.displayName)”"
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let other = try? FileLoader.load(url: url) else {
                self.presentError(FileLoaderError.unreadable(url, CocoaError(.fileReadUnknown)), in: tab.controller)
                return
            }
            self.presentDiff(leftTitle: tab.document.displayName,
                             leftText: tab.activePane.facade.text,
                             rightTitle: url.lastPathComponent,
                             rightText: other.text,
                             in: tab.controller)
        }
        if let window = tab.controller.window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    func promptCompareTwoFiles(in window: MainWindowController?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose exactly two files to compare"
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, panel.urls.count == 2 else { return }
            let first = panel.urls[0]
            let second = panel.urls[1]
            guard let left = try? FileLoader.load(url: first), let right = try? FileLoader.load(url: second) else {
                return
            }
            self.presentDiff(leftTitle: first.lastPathComponent, leftText: left.text,
                             rightTitle: second.lastPathComponent, rightText: right.text,
                             in: window)
        }
        if let window = window?.window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    // MARK: - Macros UI

    func startMacroRecording(window: MainWindowController?) {
        macroEngine.flushBuffer()
        macroEngine.startRecording()
        window?.showBanner(message: "Recording macro… every typed character and command is captured.",
                           actions: [
                            .init(title: "Stop Recording", handler: { [weak self] in
                                self?.stopMacroRecording(window: window)
                            }),
                            .init(title: "Cancel", handler: { [weak self] in
                                self?.macroEngine.cancelRecording()
                                window?.clearBanners()
                            }),
                           ],
                           style: .info)
    }

    func stopMacroRecording(window: MainWindowController?) {
        macroEngine.stopRecording(name: "Recording \(macroEngine.macros.count + 1)")
        window?.clearBanners()
        if let macro = macroEngine.lastMacro {
            TextPrompt.present(title: "Save Macro",
                               message: "Name this macro so you can replay it later.",
                               initialValue: macro.name,
                               in: window?.window) { [weak self] name in
                guard let self else { return }
                var named = macro
                named.name = name.isEmpty ? macro.name : name
                self.macroEngine.add(named)
                self.macroEngine.lastMacro = named
            }
        }
    }

    func playLastMacro(times: Int, window: MainWindowController?) {
        guard let macro = macroEngine.lastMacro, let tab = window?.activeEditorTab else { return }
        macroEngine.play(macro, times: times, tab: tab, coordinator: self)
        tab.markDirtyIfNeeded()
    }

    func promptPlayLastMacro(window: MainWindowController?) {
        guard macroEngine.lastMacro != nil, let window else { return }
        TextPrompt.present(title: "Play Macro",
                           message: "How many times should the macro play?",
                           initialValue: "1",
                           in: window.window) { [weak self] value in
            guard let self, let times = Int(value.trimmingCharacters(in: .whitespaces)), times > 0 else { return }
            self.playLastMacro(times: times, window: window)
        }
    }

    // MARK: - Diagnostics

    func copyDiagnostics() {
        var lines: [String] = []
        lines.append("PlainX Editor diagnostics")
        lines.append("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Architecture: \(Hardware.architectureString())")
        lines.append("Lexilla: \(PXSciBridge.lexillaVersion())")
        lines.append("Windows: \(windows.count)")
        lines.append("Open documents: \(windows.reduce(0) { $0 + $1.tabs.count })")
        lines.append("Session restore: \(preferences.sessionRestoreEnabled)")
        lines.append("Recovery: \(preferences.recoveryEnabled) every \(Int(preferences.recoveryInterval))s")
        lines.append("Large-file threshold: \(preferences.largeFileThresholdMB) MB")
        lines.append("Theme: \(preferences.themeChoice.rawValue)")
        lines.append("RAM: \(ProcessInfo.processInfo.physicalMemory / 1024 / 1024) MB")
        lines.append("No document contents, clipboard contents, or file paths are included in this report.")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)

        let alert = NSAlert()
        alert.messageText = "Diagnostics copied to clipboard"
        alert.informativeText = "The report contains version, platform, and preference flags only — no document content."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Windows

    func showPreferences() {
        PreferencesWindowController.shared.show(coordinator: self)
    }

    func showAbout() {
        AboutPanelController.show()
    }

    func showCommandPalette(in window: MainWindowController?) {
        CommandPaletteController.shared.show(coordinator: self, window: window ?? activeWindow)
    }

    func showShortcutsHelp() {
        SimpleTextWindowController.shared.show(
            title: "Keyboard Shortcuts",
            text: ShortcutReference.markdown()
        )
    }

    func showReleaseNotes() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        SimpleTextWindowController.shared.show(
            title: "Release Notes — PlainX Editor \(version)",
            text: ReleaseNotes.text(version: version)
        )
    }
}
