//
//  Preferences.swift
//  PlainX Editor
//
//  Typed, UserDefaults-backed preferences with registered defaults.
//  Schema changes must bump `schemaVersion` and add a migration.
//

import AppKit

enum ThemeChoice: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum LargeFileOpenMode: String, CaseIterable {
    case automatic
    case ask
    case alwaysRegular

    var displayName: String {
        switch self {
        case .automatic: return "Open in Large File Viewer"
        case .ask: return "Ask Me"
        case .alwaysRegular: return "Open Normally"
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    static let didChangeNotification = Notification.Name("PlainXPreferencesDidChange")

    static let currentSchemaVersion = 1

    private enum Key {
        static let schemaVersion = "preferences.schemaVersion"
        static let fontName = "editor.fontName"
        static let fontSize = "editor.fontSize"
        static let showLineNumbers = "editor.showLineNumbers"
        static let showWhitespace = "editor.showWhitespace"
        static let showEOL = "editor.showEOL"
        static let showIndentGuides = "editor.showIndentGuides"
        static let highlightCurrentLine = "editor.highlightCurrentLine"
        static let wordWrapDefault = "editor.wordWrapDefault"
        static let tabWidth = "editor.tabWidth"
        static let useTabs = "editor.useTabs"
        static let trimTrailingWhitespaceOnSave = "files.trimTrailingWhitespaceOnSave"
        static let ensureFinalNewlineOnSave = "files.ensureFinalNewlineOnSave"
        static let defaultEOL = "files.defaultEOL"
        static let defaultEncoding = "files.defaultEncoding"
        static let sessionRestoreEnabled = "session.restoreEnabled"
        static let recoveryEnabled = "recovery.enabled"
        static let recoveryIntervalSeconds = "recovery.intervalSeconds"
        static let recoverUnsavedOnLaunch = "recovery.promptOnLaunch"
        static let largeFileThresholdMB = "largeFiles.thresholdMB"
        static let largeFileOpenMode = "largeFiles.openMode"
        static let checkForUpdates = "updates.checkAutomatically"
        static let themeChoice = "appearance.theme"
        static let searchExcludedDirectories = "search.excludedDirectories"
        static let searchMaxResults = "search.maxResults"
        static let confirmCloseMultipleTabs = "app.confirmCloseMultipleTabs"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
        migrateIfNeeded()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.schemaVersion: Preferences.currentSchemaVersion,
            Key.fontName: Preferences.defaultFontName,
            Key.fontSize: 13.0,
            Key.showLineNumbers: true,
            Key.showWhitespace: false,
            Key.showEOL: false,
            Key.showIndentGuides: false,
            Key.highlightCurrentLine: true,
            Key.wordWrapDefault: false,
            Key.tabWidth: 4,
            Key.useTabs: false,
            Key.trimTrailingWhitespaceOnSave: false,
            Key.ensureFinalNewlineOnSave: false,
            Key.defaultEOL: EOLMode.lf.rawValue,
            Key.defaultEncoding: TextEncoding.utf8.identifier,
            Key.sessionRestoreEnabled: true,
            Key.recoveryEnabled: true,
            Key.recoveryIntervalSeconds: 5.0,
            Key.recoverUnsavedOnLaunch: true,
            Key.largeFileThresholdMB: 64,
            Key.largeFileOpenMode: LargeFileOpenMode.automatic.rawValue,
            Key.checkForUpdates: false,
            Key.themeChoice: ThemeChoice.system.rawValue,
            Key.searchExcludedDirectories: [".git", "node_modules", ".build", "DerivedData", ".venv", "venv", "__pycache__", "Pods", ".swiftpm"],
            Key.searchMaxResults: 8000,
            Key.confirmCloseMultipleTabs: true,
        ])
    }

    private func migrateIfNeeded() {
        let version = defaults.integer(forKey: Key.schemaVersion)
        if version < Preferences.currentSchemaVersion {
            // No migrations yet; record the new version.
            defaults.set(Preferences.currentSchemaVersion, forKey: Key.schemaVersion)
        }
    }

    static var defaultFontName: String {
        let candidates = ["SF Mono", "Menlo", "Monaco", "Courier New"]
        for name in candidates {
            if NSFont(name: name, size: 13) != nil { return name }
        }
        return "Menlo"
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Preferences.didChangeNotification, object: self)
    }

    // MARK: - Editor

    var fontName: String {
        get { defaults.string(forKey: Key.fontName) ?? Preferences.defaultFontName }
        set { defaults.set(newValue, forKey: Key.fontName); notifyChange() }
    }

    var fontSize: CGFloat {
        get {
            let value = defaults.double(forKey: Key.fontSize)
            return value > 4 ? CGFloat(value) : 13
        }
        set { defaults.set(Double(newValue), forKey: Key.fontSize); notifyChange() }
    }

    var showLineNumbers: Bool {
        get { defaults.bool(forKey: Key.showLineNumbers) }
        set { defaults.set(newValue, forKey: Key.showLineNumbers); notifyChange() }
    }

    var showWhitespace: Bool {
        get { defaults.bool(forKey: Key.showWhitespace) }
        set { defaults.set(newValue, forKey: Key.showWhitespace); notifyChange() }
    }

    var showEOL: Bool {
        get { defaults.bool(forKey: Key.showEOL) }
        set { defaults.set(newValue, forKey: Key.showEOL); notifyChange() }
    }

    var showIndentGuides: Bool {
        get { defaults.bool(forKey: Key.showIndentGuides) }
        set { defaults.set(newValue, forKey: Key.showIndentGuides); notifyChange() }
    }

    var highlightCurrentLine: Bool {
        get { defaults.bool(forKey: Key.highlightCurrentLine) }
        set { defaults.set(newValue, forKey: Key.highlightCurrentLine); notifyChange() }
    }

    var wordWrapDefault: Bool {
        get { defaults.bool(forKey: Key.wordWrapDefault) }
        set { defaults.set(newValue, forKey: Key.wordWrapDefault); notifyChange() }
    }

    var tabWidth: Int {
        get { min(32, max(1, defaults.integer(forKey: Key.tabWidth))) }
        set { defaults.set(newValue, forKey: Key.tabWidth); notifyChange() }
    }

    var useTabs: Bool {
        get { defaults.bool(forKey: Key.useTabs) }
        set { defaults.set(newValue, forKey: Key.useTabs); notifyChange() }
    }

    // MARK: - Files

    var trimTrailingWhitespaceOnSave: Bool {
        get { defaults.bool(forKey: Key.trimTrailingWhitespaceOnSave) }
        set { defaults.set(newValue, forKey: Key.trimTrailingWhitespaceOnSave); notifyChange() }
    }

    var ensureFinalNewlineOnSave: Bool {
        get { defaults.bool(forKey: Key.ensureFinalNewlineOnSave) }
        set { defaults.set(newValue, forKey: Key.ensureFinalNewlineOnSave); notifyChange() }
    }

    var defaultEOL: EOLMode {
        get { EOLMode(rawValue: defaults.string(forKey: Key.defaultEOL) ?? "lf") ?? .lf }
        set { defaults.set(newValue.rawValue, forKey: Key.defaultEOL); notifyChange() }
    }

    var defaultEncoding: TextEncoding {
        get {
            let id = defaults.string(forKey: Key.defaultEncoding) ?? "utf-8"
            return TextEncoding.selectable.first { $0.identifier == id && !$0.hasBOM } ?? .utf8
        }
        set { defaults.set(newValue.identifier, forKey: Key.defaultEncoding); notifyChange() }
    }

    // MARK: - Session / recovery

    var sessionRestoreEnabled: Bool {
        get { defaults.bool(forKey: Key.sessionRestoreEnabled) }
        set { defaults.set(newValue, forKey: Key.sessionRestoreEnabled); notifyChange() }
    }

    var recoveryEnabled: Bool {
        get { defaults.bool(forKey: Key.recoveryEnabled) }
        set { defaults.set(newValue, forKey: Key.recoveryEnabled); notifyChange() }
    }

    var recoveryInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.recoveryIntervalSeconds)
            return value >= 1 ? value : 5
        }
        set { defaults.set(newValue, forKey: Key.recoveryIntervalSeconds); notifyChange() }
    }

    var recoverUnsavedOnLaunch: Bool {
        get { defaults.bool(forKey: Key.recoverUnsavedOnLaunch) }
        set { defaults.set(newValue, forKey: Key.recoverUnsavedOnLaunch); notifyChange() }
    }

    // MARK: - Large files

    var largeFileThresholdMB: Int {
        get {
            let value = defaults.integer(forKey: Key.largeFileThresholdMB)
            return value > 0 ? value : 64
        }
        set { defaults.set(newValue, forKey: Key.largeFileThresholdMB); notifyChange() }
    }

    var largeFileThresholdBytes: UInt64 {
        UInt64(largeFileThresholdMB) * 1024 * 1024
    }

    var largeFileOpenMode: LargeFileOpenMode {
        get { LargeFileOpenMode(rawValue: defaults.string(forKey: Key.largeFileOpenMode) ?? "automatic") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: Key.largeFileOpenMode); notifyChange() }
    }

    // MARK: - Updates / appearance

    var checkForUpdates: Bool {
        get { defaults.bool(forKey: Key.checkForUpdates) }
        set { defaults.set(newValue, forKey: Key.checkForUpdates); notifyChange() }
    }

    var themeChoice: ThemeChoice {
        get { ThemeChoice(rawValue: defaults.string(forKey: Key.themeChoice) ?? "system") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.themeChoice); notifyChange() }
    }

    // MARK: - Search

    var searchExcludedDirectories: [String] {
        get { defaults.stringArray(forKey: Key.searchExcludedDirectories) ?? [] }
        set { defaults.set(newValue, forKey: Key.searchExcludedDirectories); notifyChange() }
    }

    var searchMaxResults: Int {
        get {
            let value = defaults.integer(forKey: Key.searchMaxResults)
            return value > 0 ? value : 8000
        }
        set { defaults.set(newValue, forKey: Key.searchMaxResults); notifyChange() }
    }

    var confirmCloseMultipleTabs: Bool {
        get { defaults.bool(forKey: Key.confirmCloseMultipleTabs) }
        set { defaults.set(newValue, forKey: Key.confirmCloseMultipleTabs); notifyChange() }
    }

    // MARK: - Theme resolution

    func resolvedTheme(appearance: NSAppearance?) -> EditorTheme {
        switch themeChoice {
        case .light: return .systemLight
        case .dark: return .systemDark
        case .system:
            let effective = appearance ?? NSApp.effectiveAppearance
            return EditorTheme.theme(for: effective)
        }
    }
}
