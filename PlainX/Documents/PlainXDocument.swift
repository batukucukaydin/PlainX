//
//  PlainXDocument.swift
//  PlainX Editor
//
//  A regular (editable) document. The authoritative live text buffer for a
//  regular document lives inside Scintilla; this model stores metadata and
//  per-view state only.
//

import AppKit

struct FileMetadata: Equatable {
    var modificationDate: Date
    var fileSize: UInt64
    var fileIdentifier: String?

    var summary: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }
}

struct EditorViewState: Codable, Equatable {
    var caretPosition: Int
    var anchorPosition: Int
    var firstVisibleLine: Int
    var xOffset: Int
    var selections: [CodableSelection]

    struct CodableSelection: Codable, Equatable {
        var anchor: Int
        var caret: Int
    }
}

final class PlainXDocument: NSObject {
    let id: UUID
    private(set) var url: URL?
    var untitledName: String

    var encoding: TextEncoding
    var eolMode: EOLMode
    var languageOverrideID: String?
    var isDirty: Bool = false
    var isPinned: Bool = false
    var bookmarks: Set<Int> = []
    /// nil = follow the global preference; otherwise a per-document override.
    var wordWrapOverride: Bool?
    var lastKnownMetadata: FileMetadata?
    var loadDiagnostic: String?
    var isLargeFileMode: Bool = false
    /// Set when the file on disk changed while the document was open.
    var hasExternalChange: Bool = false
    /// Overrides the recovery snapshot identity (used when restoring).
    var recoveryID: UUID?
    /// Caret/scroll state per editor pane (supports split/cloned views).
    var viewStates: [UUID: EditorViewState] = [:]

    var recoveryKey: UUID { recoveryID ?? id }

    var isUntitled: Bool { url == nil }

    var displayName: String {
        url?.lastPathComponent ?? untitledName
    }

    var pathDisplayName: String {
        url?.path ?? "Untitled"
    }

    var language: LanguageDefinition {
        if let overrideID = languageOverrideID {
            return LanguageRegistry.language(withID: overrideID)
        }
        return LanguageRegistry.language(for: url)
    }

    var isLanguageDetected: Bool { languageOverrideID == nil }

    init(url: URL?, untitledName: String = "Untitled") {
        self.id = UUID()
        self.url = url
        self.untitledName = untitledName
        self.encoding = .utf8
        self.eolMode = .lf
        super.init()
    }

    func rename(to newURL: URL) {
        url = newURL
        untitledName = newURL.lastPathComponent
    }

    /// Line numbers (0-based) currently carrying the bookmark marker.
    func bookmarkedLines() -> [Int] {
        bookmarks.sorted()
    }
}
