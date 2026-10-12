//
//  RecoveryStore.swift
//  PlainX Editor
//
//  Crash-safe recovery snapshots for unsaved documents. Snapshots are written
//  atomically to Application Support on a debounced schedule, never uploaded
//  anywhere, and are pruned by age/count.
//

import AppKit

struct RecoverySnapshot: Codable {
    var version: Int
    var documentID: String
    var originalPath: String?
    var displayName: String
    var encodingID: String
    var encodingHasBOM: Bool
    var eol: String
    var languageOverrideID: String?
    var savedAt: Date
    var text: String
}

final class RecoveryStore {
    static let currentVersion = 1
    private static let maxSnapshots = 40
    private static let maxAgeDays = 7

    private let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("PlainX/Recovery", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(for documentID: UUID) -> URL {
        directory.appendingPathComponent("\(documentID.uuidString).json")
    }

    func snapshot(document: PlainXDocument, text: String) {
        guard Preferences.shared.recoveryEnabled else { return }
        let snapshot = RecoverySnapshot(
            version: RecoveryStore.currentVersion,
            documentID: document.recoveryKey.uuidString,
            originalPath: document.url?.path,
            displayName: document.displayName,
            encodingID: document.encoding.identifier,
            encodingHasBOM: document.encoding.hasBOM,
            eol: document.eolMode.rawValue,
            languageOverrideID: document.languageOverrideID,
            savedAt: Date(),
            text: text
        )
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(snapshot)
            try data.write(to: url(for: document.recoveryKey), options: [.atomic])
        } catch {
            Log.recovery.error("Recovery snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func discardSnapshot(for document: PlainXDocument) {
        try? fileManager.removeItem(at: url(for: document.recoveryKey))
    }

    func recoveryText(for document: PlainXDocument) -> String? {
        loadSnapshot(for: document.recoveryKey)?.text
    }

    func loadSnapshot(for documentID: UUID) -> RecoverySnapshot? {
        guard let data = try? Data(contentsOf: url(for: documentID)) else { return nil }
        return try? JSONDecoder().decode(RecoverySnapshot.self, from: data)
    }

    func allSnapshots() -> [RecoverySnapshot] {
        guard let entries = try? fileManager.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        var snapshots: [RecoverySnapshot] = []
        for entry in entries where entry.pathExtension == "json" {
            guard let data = try? Data(contentsOf: entry),
                  let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: data) else {
                continue
            }
            snapshots.append(snapshot)
        }
        return snapshots.sorted { $0.savedAt > $1.savedAt }
    }

    /// Removes old snapshots beyond the retention caps.
    func prune() {
        let snapshots = allSnapshots()
        let cutoff = Date().addingTimeInterval(-Double(RecoveryStore.maxAgeDays) * 86400)
        for (index, snapshot) in snapshots.enumerated() {
            if snapshot.savedAt < cutoff || index >= RecoveryStore.maxSnapshots {
                if let id = UUID(uuidString: snapshot.documentID) {
                    try? fileManager.removeItem(at: url(for: id))
                }
            }
        }
    }

    /// On launch, offer to restore snapshots that do not belong to a document
    /// that the session already restored.
    func restoreUnclaimedSnapshots(into coordinator: AppCoordinator) {
        guard Preferences.shared.recoveryEnabled,
              Preferences.shared.recoverUnsavedOnLaunch else { return }
        prune()
        let openIDs = Set(coordinator.allOpenDocumentIDs().map(\.uuidString))
        let unclaimed = allSnapshots().filter { !openIDs.contains($0.documentID) }
        guard !unclaimed.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = unclaimed.count == 1
            ? "One unsaved document was recovered from a previous session."
            : "\(unclaimed.count) unsaved documents were recovered from a previous session."
        alert.informativeText = "Recovered documents are opened as unsaved tabs; nothing is written to disk unless you save."
        alert.addButton(withTitle: "Recover")
        alert.addButton(withTitle: "Discard")
        DispatchQueue.main.async {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let window = coordinator.activeWindow ?? coordinator.newWindow()
                for snapshot in unclaimed {
                    coordinator.recoverDocument(from: snapshot, in: window)
                }
            } else {
                for snapshot in unclaimed {
                    if let id = UUID(uuidString: snapshot.documentID) {
                        try? self.fileManager.removeItem(at: self.url(for: id))
                    }
                }
            }
        }
    }
}
