//
//  FileLoader.swift
//  PlainX Editor
//

import Foundation

struct LoadedFile {
    let text: String
    let encoding: TextEncoding
    let eolMode: EOLMode
    let metadata: FileMetadata
    let diagnostic: String?
    let hadInvalidSequences: Bool
}

enum FileLoaderError: LocalizedError {
    case unreadable(URL, Error)
    case notARegularFile(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url, let error):
            return "Could not read “\(url.lastPathComponent)”: \(error.localizedDescription)"
        case .notARegularFile(let url):
            return "“\(url.lastPathComponent)” is not a regular file and cannot be opened in the text editor."
        }
    }
}

enum FileLoader {

    static func metadata(for url: URL) -> FileMetadata? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let modificationDate = (attributes[.modificationDate] as? Date) ?? Date.distantPast
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let identifier = (attributes[.systemFileNumber] as? NSNumber)?.stringValue
        return FileMetadata(modificationDate: modificationDate, fileSize: fileSize, fileIdentifier: identifier)
    }

    static func load(url: URL, preferredEncoding: TextEncoding? = nil) throws -> LoadedFile {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw FileLoaderError.unreadable(url, error)
        }

        let (text, detection) = decode(data: data, preferredEncoding: preferredEncoding)

        var decodedText = text
        var effectiveEncoding = detection.encoding
        if !effectiveEncoding.hasBOM, decodedText.hasPrefix("\u{FEFF}") {
            // Detection stopped at plain UTF-8 but a BOM character survived:
            // record it as BOM policy so saving round-trips.
            decodedText.removeFirst()
            if effectiveEncoding.identifier == "utf-8" {
                effectiveEncoding = .utf8BOM
            }
        }

        let eolMode = EOLMode.detect(in: decodedText)
        let metadata = metadata(for: url) ?? FileMetadata(modificationDate: Date(), fileSize: UInt64(data.count), fileIdentifier: nil)

        return LoadedFile(
            text: decodedText,
            encoding: effectiveEncoding,
            eolMode: eolMode,
            metadata: metadata,
            diagnostic: detection.diagnostic,
            hadInvalidSequences: detection.hadInvalidSequences
        )
    }

    /// Decodes data with conservative detection. BOM bytes are stripped before
    /// decoding; the returned encoding carries the BOM policy for saving.
    static func decode(data: Data, preferredEncoding: TextEncoding? = nil) -> (String, EncodingDetectionResult) {
        if let preferred = preferredEncoding {
            let stripped = stripBOM(data, matching: preferred)
            if let text = String(data: stripped, encoding: preferred.stringEncoding) {
                let result = EncodingDetectionResult(encoding: preferred, confidence: 1.0,
                                                     hadInvalidSequences: false, diagnostic: nil)
                return (text, result)
            }
            // Requested encoding failed; fall through to detection.
        }

        let detection = EncodingDetector.detect(data: data, preferredEncoding: preferredEncoding)
        let stripped = stripBOM(data, matching: detection.encoding)
        if let text = String(data: stripped, encoding: detection.encoding.stringEncoding) {
            return (text, detection)
        }

        // Last resort: lossy conversion, clearly flagged.
        let lossy = String(decoding: stripped, as: UTF8.self)
        let result = EncodingDetectionResult(
            encoding: .utf8, confidence: 0.2, hadInvalidSequences: true,
            diagnostic: "This file contains bytes that are not valid in the detected encoding. They were replaced while displaying; saving will write valid UTF-8."
        )
        return (lossy, result)
    }

    static func stripBOM(_ data: Data, matching encoding: TextEncoding) -> Data {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]), encoding.identifier == "utf-8" || encoding.identifier == "ascii" {
            return data.dropFirst(3)
        }
        if bytes.starts(with: [0xFF, 0xFE]) && !bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00])
            && encoding.identifier.hasPrefix("utf-16") {
            return data.dropFirst(2)
        }
        if bytes.starts(with: [0xFE, 0xFF]) && encoding.identifier.hasPrefix("utf-16") {
            return data.dropFirst(2)
        }
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) && encoding.identifier.hasPrefix("utf-32") {
            return data.dropFirst(4)
        }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) && encoding.identifier.hasPrefix("utf-32") {
            return data.dropFirst(4)
        }
        return data
    }

    static func bomBytes(for encoding: TextEncoding) -> Data? {
        guard encoding.hasBOM else { return nil }
        switch encoding.identifier {
        case "utf-8", "ascii":
            return Data([0xEF, 0xBB, 0xBF])
        case "utf-16le":
            return Data([0xFF, 0xFE])
        case "utf-16be":
            return Data([0xFE, 0xFF])
        case "utf-32le":
            return Data([0xFF, 0xFE, 0x00, 0x00])
        case "utf-32be":
            return Data([0x00, 0x00, 0xFE, 0xFF])
        default:
            return nil
        }
    }
}
