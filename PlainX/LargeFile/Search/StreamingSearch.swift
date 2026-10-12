//
//  StreamingSearch.swift
//  PlainX Editor
//
//  Streaming search over a memory-mapped large file. Scans line-aligned
//  chunks with overlap so matches at chunk boundaries are never missed, and
//  reports progress so the UI can stay responsive and cancellable.
//

import Foundation

struct LargeFileSearchQuery: Equatable {
    var pattern: String
    var isRegex: Bool = false
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var maxResults: Int = 10_000
    var previewLimit: Int = 400
}

struct LargeFileSearchMatch: Equatable {
    var lineNumber: Int
    var byteOffset: UInt64
    var lineText: String
    /// UTF-16 range of the match inside `lineText` when determinable.
    var previewRange: NSRange?
}

enum LargeFileSearchEvent {
    case progress(Double)
    case match(LargeFileSearchMatch)
    case finished(total: Int, cancelled: Bool, reachedCap: Bool)
    case failed(String)
}

final class StreamingSearch {
    private let reader: ChunkReader
    private let encoding: LargeFileTextEncoding
    private let chunkSize: Int
    private var task: Task<Void, Never>?

    init(reader: ChunkReader, encoding: LargeFileTextEncoding, chunkSize: Int = 4 * 1024 * 1024) {
        self.reader = reader
        self.encoding = encoding
        self.chunkSize = max(256 * 1024, chunkSize)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    var isRunning: Bool { task != nil }

    func search(_ query: LargeFileSearchQuery) -> AsyncStream<LargeFileSearchEvent> {
        cancel()
        return AsyncStream { continuation in
            guard !query.pattern.isEmpty else {
                continuation.yield(.finished(total: 0, cancelled: false, reachedCap: false))
                continuation.finish()
                return
            }
            let regex: NSRegularExpression?
            if query.isRegex || query.wholeWord {
                var pattern = query.isRegex ? query.pattern : NSRegularExpression.escapedPattern(for: query.pattern)
                if query.wholeWord {
                    pattern = "\\b(?:\(pattern))\\b"
                }
                var options: NSRegularExpression.Options = []
                if !query.caseSensitive {
                    options.insert(.caseInsensitive)
                }
                regex = try? NSRegularExpression(pattern: pattern, options: options)
                if regex == nil {
                    continuation.yield(.failed("Invalid regular expression."))
                    continuation.finish()
                    return
                }
            } else {
                regex = nil
            }

            let work = Task.detached(priority: .userInitiated) { [reader, encoding, chunkSize] in
                let total = max(1, reader.fileSize)
                var offset: UInt64 = 0
                var lineNumber = 0
                var matches = 0
                var reachedCap = false
                var lastProgressReport = Date.distantPast

                // Fast path: byte-level matching for literal patterns avoids
                // allocating a String for every line. Whole-word boundaries and
                // regex stay on the String path.
                let literalBytes: [UInt8]? = (!query.isRegex && !query.wholeWord)
                    ? Array(query.pattern.utf8)
                    : nil
                let literalIsASCII = literalBytes?.allSatisfy { $0 < 0x80 } ?? false

                var carry = Data()
                var lineStartOffset: UInt64 = 0
                var scanBuffer = Data(count: chunkSize)

                func emit(line: String, at lineStart: UInt64) {
                    guard let result = Self.matchLine(line: line, query: query, regex: regex,
                                                      lineNumber: lineNumber,
                                                      lineOffset: lineStart) else { return }
                    matches += 1
                    continuation.yield(.match(result))
                    if matches >= query.maxResults {
                        reachedCap = true
                    }
                }

                while offset < reader.fileSize {
                    if Task.isCancelled {
                        continuation.yield(.finished(total: matches, cancelled: true, reachedCap: reachedCap))
                        continuation.finish()
                        return
                    }
                    let length = Int(min(UInt64(chunkSize), reader.fileSize - offset))
                    let scanned = reader.readInto(&scanBuffer, offset: offset, length: length)
                    guard scanned > 0 else { break }
                    let chunkStart = offset
                    offset += UInt64(scanned)

                    scanBuffer.withUnsafeBytes { raw in
                        guard let base = raw.baseAddress else { return }
                        let bytes = base.assumingMemoryBound(to: UInt8.self)
                        var index = 0
                        while index < scanned {
                            var newlineIndex = index
                            while newlineIndex < scanned, bytes[newlineIndex] != 0x0A {
                                newlineIndex += 1
                            }
                            let isCompleteLine = newlineIndex < scanned
                            let segmentLength = newlineIndex - index

                            guard isCompleteLine else {
                                // Carry the partial line into the next chunk.
                                if segmentLength > 0 {
                                    carry.append(bytes + index, count: segmentLength)
                                }
                                // Pathological single very long line: process a
                                // bounded window as a line instead of growing
                                // the carry without limit.
                                if carry.count > chunkSize * 2 {
                                    let line = encoding.decode(carry)
                                    emit(line: line, at: lineStartOffset)
                                    lineNumber += 1
                                    lineStartOffset += UInt64(carry.count)
                                    carry.removeAll(keepingCapacity: true)
                                }
                                return
                            }

                            if carry.isEmpty {
                                let absoluteLineStart = chunkStart + UInt64(index)
                                var handled = false
                                if let needle = literalBytes, literalIsASCII || query.caseSensitive {
                                    switch Self.byteMatch(in: bytes + index, count: segmentLength,
                                                          needle: needle,
                                                          caseSensitive: query.caseSensitive) {
                                    case .noMatch:
                                        handled = true
                                    case .match:
                                        let line = encoding.decode(bytes: bytes + index, count: segmentLength)
                                        emit(line: line, at: absoluteLineStart)
                                        handled = true
                                    case .needsStringPath:
                                        handled = false
                                    }
                                }
                                if !handled {
                                    let line = encoding.decode(bytes: bytes + index, count: segmentLength)
                                    emit(line: line, at: absoluteLineStart)
                                }
                            } else {
                                if segmentLength > 0 {
                                    carry.append(bytes + index, count: segmentLength)
                                }
                                let line = encoding.decode(carry)
                                emit(line: line, at: lineStartOffset)
                                carry.removeAll(keepingCapacity: true)
                            }
                            lineNumber += 1
                            index = newlineIndex + 1
                            if reachedCap { return }
                        }
                    }
                    if reachedCap { break }

                    let now = Date()
                    if now.timeIntervalSince(lastProgressReport) > 0.1 {
                        lastProgressReport = now
                        continuation.yield(.progress(Double(min(offset, total)) / Double(total)))
                    }
                }

                // Trailing line without terminator.
                if !carry.isEmpty, !reachedCap, !Task.isCancelled {
                    let line = encoding.decode(carry)
                    emit(line: line, at: lineStartOffset)
                }

                continuation.yield(.finished(total: matches,
                                             cancelled: Task.isCancelled,
                                             reachedCap: reachedCap))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                work.cancel()
            }
            self.task = work
        }
    }

    nonisolated private enum ByteMatchResult {
        case match
        case noMatch
        case needsStringPath
    }

    /// ASCII-aware literal byte matcher. Returns `.needsStringPath` when a
    /// case-insensitive comparison involves non-ASCII bytes, where Unicode
    /// case folding in the String path is more correct.
    nonisolated private static func byteMatch(in pointer: UnsafePointer<UInt8>,
                                              count: Int,
                                              needle: [UInt8],
                                              caseSensitive: Bool) -> ByteMatchResult {
        guard !needle.isEmpty, count >= needle.count else { return .noMatch }
        let first = needle[0]
        let limit = count - needle.count
        var index = 0
        while index <= limit {
            let byte = pointer[index]
            let firstMatches: Bool
            if caseSensitive {
                firstMatches = byte == first
            } else if byte >= 0x80 || first >= 0x80 {
                return .needsStringPath
            } else {
                firstMatches = asciiLower(byte) == asciiLower(first)
            }
            if firstMatches {
                var offset = 1
                var matched = true
                while offset < needle.count {
                    let candidate = pointer[index + offset]
                    if caseSensitive {
                        if candidate != needle[offset] {
                            matched = false
                            break
                        }
                    } else if candidate >= 0x80 || needle[offset] >= 0x80 {
                        return .needsStringPath
                    } else if asciiLower(candidate) != asciiLower(needle[offset]) {
                        matched = false
                        break
                    }
                    offset += 1
                }
                if matched { return .match }
            }
            index += 1
        }
        return .noMatch
    }

    nonisolated private static func asciiLower(_ byte: UInt8) -> UInt8 {
        (byte >= 0x41 && byte <= 0x5A) ? byte + 0x20 : byte
    }

    nonisolated private static func matchLine(line: String,
                                              query: LargeFileSearchQuery,
                                              regex: NSRegularExpression?,
                                              lineNumber: Int,
                                              lineOffset: UInt64) -> LargeFileSearchMatch? {
        if let regex {
            let range = NSRange(location: 0, length: line.utf16.count)
            guard let found = regex.firstMatch(in: line, options: [], range: range) else { return nil }
            let preview = Self.preview(of: line, query: query)
            let byteOffset = Self.utf8Offset(in: line, utf16Offset: found.range.location)
            return LargeFileSearchMatch(lineNumber: lineNumber,
                                        byteOffset: lineOffset + UInt64(byteOffset),
                                        lineText: preview.text,
                                        previewRange: nil)
        }
        let options: String.CompareOptions = query.caseSensitive ? [] : [.caseInsensitive]
        guard let found = line.range(of: query.pattern, options: options) else { return nil }
        let byteOffset = lineOffset + UInt64(line.utf8.distance(from: line.utf8.startIndex, to: found.lowerBound))
        let column = line.utf16.distance(from: line.utf16.startIndex, to: found.lowerBound)
        let preview = Self.preview(of: line, query: query, highlightColumn: column)
        return LargeFileSearchMatch(lineNumber: lineNumber,
                                    byteOffset: byteOffset,
                                    lineText: preview.text,
                                    previewRange: preview.range)
    }

    nonisolated private static func utf8Offset(in line: String, utf16Offset: Int) -> Int {
        guard utf16Offset > 0 else { return 0 }
        let stringIndex = String.Index(utf16Offset: utf16Offset, in: line)
        return line.utf8.distance(from: line.utf8.startIndex, to: stringIndex)
    }

    nonisolated private static func preview(of line: String,
                                           query: LargeFileSearchQuery,
                                           highlightColumn: Int? = nil) -> (text: String, range: NSRange?) {
        if line.utf16.count <= query.previewLimit {
            if let highlightColumn {
                let remaining = max(0, line.utf16.count - highlightColumn)
                let length = min(query.pattern.utf16.count, remaining)
                return (line, NSRange(location: highlightColumn, length: max(1, length)))
            }
            return (line, nil)
        }
        let limit = query.previewLimit
        let start = max(0, (highlightColumn ?? 0) - limit / 4)
        let nsLine = line as NSString
        let slice = nsLine.substring(with: NSRange(location: start, length: min(limit, nsLine.length - start)))
        var range: NSRange? = nil
        if let highlightColumn, highlightColumn >= start, highlightColumn - start < limit {
            range = NSRange(location: highlightColumn - start, length: min(query.pattern.utf16.count, limit))
        }
        return (slice, range)
    }
}

/// Text encodings safe for byte-oriented large-file processing.
enum LargeFileTextEncoding: Equatable {
    case utf8(hasBOM: Bool)
    case windows1252

    var displayName: String {
        switch self {
        case .utf8(let hasBOM): return hasBOM ? "UTF-8 (BOM)" : "UTF-8"
        case .windows1252: return "Windows-1252 (assumed)"
        }
    }

    func decode(_ data: Data) -> String {
        switch self {
        case .utf8:
            return String(decoding: data, as: UTF8.self)
        case .windows1252:
            return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
        }
    }

    /// Decode for scanning paths that hold raw buffer pointers. For UTF-8
    /// this is zero-copy; the Windows-1252 path copies the line bytes.
    func decode(bytes: UnsafePointer<UInt8>, count: Int) -> String {
        switch self {
        case .utf8:
            return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
        case .windows1252:
            let data = Data(bytes: bytes, count: count)
            return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
        }
    }

    /// Detects an encoding safe for large-file processing. Returns nil for
    /// UTF-16 (not supported in Large File Mode; caller should open normally
    /// or convert).
    static func detect(reader: ChunkReader) -> LargeFileTextEncoding? {
        let sampleLength = Int(min(UInt64(64 * 1024), reader.fileSize))
        let sample = reader.read(offset: 0, length: sampleLength)
        let bytes = [UInt8](sample)
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF])
            || bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return nil
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .utf8(hasBOM: true)
        }
        // Validate UTF-8 over the sample (allowing a truncated final sequence).
        if EncodingDetector.validateUTF8(sample) != nil {
            return .utf8(hasBOM: false)
        }
        // Trim up to 3 trailing bytes which may be a torn multi-byte sequence.
        if sample.count > 4 {
            let trimmed = sample.dropLast(min(3, sample.count - 1))
            if EncodingDetector.validateUTF8(trimmed) != nil {
                return .utf8(hasBOM: false)
            }
        }
        return .windows1252
    }
}
