//
//  FileSaver.swift
//  PlainX Editor
//
//  Safe, atomic save path. The original file must never be destroyed by a
//  failed save: content is written to a sibling temporary file and only then
//  swapped in with an atomic replace.
//

import Foundation

enum FileSaverError: LocalizedError {
    case externalModification(URL)
    case encodingFailure(TextEncoding, String)
    case writeFailure(URL, Error)
    case verificationFailure(URL, Error)

    var errorDescription: String? {
        switch self {
        case .externalModification(let url):
            return "“\(url.lastPathComponent)” changed on disk after you opened it."
        case .encodingFailure(let encoding, let detail):
            return "This document contains characters that cannot be represented in \(encoding.displayName). \(detail)"
        case .writeFailure(let url, let error):
            return "Could not save “\(url.lastPathComponent)”: \(error.localizedDescription)"
        case .verificationFailure(let url, let error):
            return "Saved “\(url.lastPathComponent)” but could not verify the result: \(error.localizedDescription)"
        }
    }
}

enum FileSaver {

    struct SaveResult {
        let metadata: FileMetadata
    }

    /// Encodes and saves `text` to `url` atomically.
    ///
    /// - Parameters:
    ///   - checkExternalModification: when true (normal Save), the file on disk
    ///     must still match `lastKnownMetadata`, otherwise the save is refused
    ///     so the user can decide.
    ///   - force: bypasses the external-modification check (Save Anyway).
    static func save(text: String,
                     to url: URL,
                     encoding: TextEncoding,
                     lastKnownMetadata: FileMetadata?,
                     checkExternalModification: Bool = true,
                     force: Bool = false) throws -> SaveResult {
        if checkExternalModification && !force, let known = lastKnownMetadata,
           FileManager.default.fileExists(atPath: url.path) {
            if let current = FileLoader.metadata(for: url), !isSameFileContentState(known, current) {
                throw FileSaverError.externalModification(url)
            }
        }

        guard let encoded = encode(text: text, encoding: encoding) else {
            throw FileSaverError.encodingFailure(
                encoding,
                "Choose UTF-8 or another encoding for the file, or remove the unmappable characters."
            )
        }

        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".plainx-save-\(UUID().uuidString)")

        let fm = FileManager.default
        let existedBefore = fm.fileExists(atPath: url.path)

        do {
            try encoded.write(to: temporaryURL, options: [.atomic])
            try applyPOSIXPermissions(from: existedBefore ? url : nil, to: temporaryURL)
        } catch {
            try? fm.removeItem(at: temporaryURL)
            throw FileSaverError.writeFailure(url, error)
        }

        do {
            if existedBefore {
                _ = try fm.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fm.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fm.removeItem(at: temporaryURL)
            throw FileSaverError.writeFailure(url, error)
        }

        guard let metadata = FileLoader.metadata(for: url) else {
            throw FileSaverError.verificationFailure(url, CocoaError(.fileReadUnknown))
        }
        return SaveResult(metadata: metadata)
    }

    static func encode(text: String, encoding: TextEncoding) -> Data? {
        guard let content = text.data(using: encoding.stringEncoding, allowLossyConversion: false) else {
            return nil
        }
        if let bom = FileLoader.bomBytes(for: encoding) {
            var data = Data()
            data.append(bom)
            data.append(content)
            return data
        }
        return content
    }

    private static func applyPOSIXPermissions(from original: URL?, to target: URL) throws {
        let fm = FileManager.default
        guard let original else {
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
            return
        }
        let attributes = try fm.attributesOfItem(atPath: original.path)
        var toApply: [FileAttributeKey: Any] = [:]
        if let permissions = attributes[.posixPermissions] {
            toApply[.posixPermissions] = permissions
        }
        if let owner = attributes[.ownerAccountID] {
            toApply[.ownerAccountID] = owner
        }
        if !toApply.isEmpty {
            try? fm.setAttributes(toApply, ofItemAtPath: target.path)
        }
    }

    /// Compares the two file states for "content changed" purposes: size or
    /// modification date, tolerating sub-second timestamp noise from some
    /// filesystems.
    static func isSameFileContentState(_ lhs: FileMetadata, _ rhs: FileMetadata) -> Bool {
        if lhs.fileSize != rhs.fileSize { return false }
        if let lhsID = lhs.fileIdentifier, let rhsID = rhs.fileIdentifier, lhsID != rhsID { return false }
        return abs(lhs.modificationDate.timeIntervalSince(rhs.modificationDate)) < 0.5
    }
}
