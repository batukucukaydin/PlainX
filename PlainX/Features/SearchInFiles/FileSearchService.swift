//
//  FileSearchService.swift
//  PlainX Editor
//
//  Streaming, cancellable folder search built on Foundation concurrency.
//  No external search binary is used.
//

import Foundation

struct FileSearchQuery: Equatable {
    var root: URL
    var pattern: String
    var isRegex: Bool = false
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var includeGlobs: [String] = []
    var excludeGlobs: [String] = []
    var excludedDirectories: [String] = []
    var maxResults: Int = 8000
    var maxFileSizeBytes: UInt64 = 20 * 1024 * 1024
    var followSymlinks: Bool = false
}

struct FileSearchMatch: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let lineNumber: Int          // 0-based
    let column: Int              // 0-based character column
    let lineText: String
    let matchLength: Int

    static func == (lhs: FileSearchMatch, rhs: FileSearchMatch) -> Bool {
        lhs.url == rhs.url && lhs.lineNumber == rhs.lineNumber && lhs.column == rhs.column
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(lineNumber)
        hasher.combine(column)
    }
}

enum FileSearchEvent {
    case fileStarted(URL)
    case match(FileSearchMatch)
    case fileFinished(URL, matchCount: Int)
    case warning(String)
    case finished(filesScanned: Int, matchesFound: Int, wasCancelled: Bool)
}

final class FileSearchService {
    private var task: Task<Void, Never>?

    var isSearching: Bool { task != nil }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Streams results. The returned stream finishes when the search completes
    /// or is cancelled.
    func search(_ query: FileSearchQuery) -> AsyncStream<FileSearchEvent> {
        cancel()
        return AsyncStream { continuation in
            let work = Task.detached(priority: .userInitiated) { [weak self] in
                var filesScanned = 0
                var matchesFound = 0
                var wasCancelled = false

                let matcher = LineMatcher(query: query)
                let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isDirectoryKey]

                guard let enumerator = FileManager.default.enumerator(
                    at: query.root,
                    includingPropertiesForKeys: keys,
                    options: query.followSymlinks ? [] : [.skipsPackageDescendants],
                    errorHandler: { url, error in
                        continuation.yield(.warning("Could not read \(url.lastPathComponent): \(error.localizedDescription)"))
                        return true
                    }
                ) else {
                    continuation.yield(.finished(filesScanned: 0, matchesFound: 0, wasCancelled: false))
                    continuation.finish()
                    return
                }

                for case let fileURL as URL in enumerator {
                    if Task.isCancelled {
                        wasCancelled = true
                        break
                    }
                    if matchesFound >= query.maxResults {
                        break
                    }

                    let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys))
                    if resourceValues?.isDirectory == true {
                        let name = fileURL.lastPathComponent
                        if query.excludedDirectories.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                            enumerator.skipDescendants()
                            continue
                        }
                        if fileURL.lastPathComponent.hasPrefix(".") && fileURL.lastPathComponent != "." {
                            enumerator.skipDescendants()
                            continue
                        }
                        continue
                    }

                    // Skip hidden files and symlinks that could loop.
                    if fileURL.lastPathComponent.hasPrefix(".") { continue }
                    if resourceValues?.isSymbolicLink == true && !query.followSymlinks { continue }
                    guard resourceValues?.isRegularFile == true else { continue }

                    let name = fileURL.lastPathComponent
                    if !query.includeGlobs.isEmpty,
                       !GlobMatcher.matchesAny(of: query.includeGlobs, name: name, caseSensitive: false) {
                        continue
                    }
                    if !query.excludeGlobs.isEmpty,
                       GlobMatcher.matchesAny(of: query.excludeGlobs, name: name, caseSensitive: false) {
                        continue
                    }
                    if let size = resourceValues?.fileSize, UInt64(size) > query.maxFileSizeBytes {
                        continuation.yield(.warning("Skipped \(name): larger than the search limit."))
                        continue
                    }

                    if Task.isCancelled {
                        wasCancelled = true
                        break
                    }

                    filesScanned += 1
                    var fileMatchCount = 0

                    autoreleasepool {
                        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
                            return
                        }
                        if BinaryHeuristic.looksBinary(data: data) {
                            return
                        }
                        guard let text = FileSearchService.decode(data) else { return }

                        var lineNumber = 0
                        var lineStart = text.startIndex
                        while lineStart < text.endIndex, matchesFound < query.maxResults {
                            if Task.isCancelled {
                                wasCancelled = true
                                return
                            }
                            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
                            let line = String(text[lineStart..<lineEnd])
                            let lineMatches = matcher.matches(in: line)
                            if !lineMatches.isEmpty {
                                continuation.yield(.fileStarted(fileURL))
                                for match in lineMatches {
                                    matchesFound += 1
                                    fileMatchCount += 1
                                    continuation.yield(.match(FileSearchMatch(
                                        url: fileURL,
                                        lineNumber: lineNumber,
                                        column: match.location,
                                        lineText: line,
                                        matchLength: match.length
                                    )))
                                    if matchesFound >= query.maxResults { break }
                                }
                            }
                            lineNumber += 1
                            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
                        }
                        if fileMatchCount > 0 {
                            continuation.yield(.fileFinished(fileURL, matchCount: fileMatchCount))
                        }
                    }
                }

                continuation.yield(.finished(filesScanned: filesScanned,
                                             matchesFound: matchesFound,
                                             wasCancelled: wasCancelled || Task.isCancelled))
                continuation.finish()
                _ = self
            }
            continuation.onTermination = { _ in
                work.cancel()
            }
            self.task = work
        }
    }

    private static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .windowsCP1252) {
            return text
        }
        return String(data: data, encoding: .isoLatin1)
    }
}

/// Matches one line according to the query (literal or regex).
struct LineMatcher {
    let query: FileSearchQuery
    private let regex: NSRegularExpression?

    init(query: FileSearchQuery) {
        self.query = query
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
        } else {
            regex = nil
        }
    }

    /// Returns UTF-16 based ranges of matches in the line.
    func matches(in line: String) -> [NSRange] {
        if let regex {
            let range = NSRange(location: 0, length: line.utf16.count)
            return regex.matches(in: line, options: [], range: range).map { $0.range }.filter { $0.length >= 0 }
        }
        let options: String.CompareOptions = query.caseSensitive ? [] : [.caseInsensitive]
        var results: [NSRange] = []
        var searchStart = line.startIndex
        while searchStart < line.endIndex,
              let found = line.range(of: query.pattern, options: options, range: searchStart..<line.endIndex) {
            let location = line.utf16.distance(from: line.utf16.startIndex, to: found.lowerBound.samePosition(in: line.utf16)!)
            let length = line.utf16.distance(from: found.lowerBound.samePosition(in: line.utf16)!,
                                             to: found.upperBound.samePosition(in: line.utf16)!)
            results.append(NSRange(location: location, length: length))
            searchStart = found.upperBound > found.lowerBound ? found.upperBound : line.index(after: found.lowerBound)
        }
        return results
    }
}

/// Cheap binary detection: a NUL byte in the first 8 KiB (like git).
enum BinaryHeuristic {
    static func looksBinary(data: Data) -> Bool {
        let sampleLength = min(data.count, 8192)
        guard sampleLength > 0 else { return false }
        var index = data.startIndex
        for _ in 0..<sampleLength {
            if data[index] == 0 { return true }
            index = data.index(after: index)
        }
        return false
    }
}
