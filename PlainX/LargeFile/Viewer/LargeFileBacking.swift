//
//  LargeFileBacking.swift
//  PlainX Editor
//
//  Combines the memory-mapped reader, sparse line index, encoding assumption,
//  line cache, and follow state for one large file.
//

import AppKit

final class LargeFileBacking {
    let url: URL
    let reader: ChunkReader
    let index: LineIndex
    let encoding: LargeFileTextEncoding

    private(set) var indexProgress: Double = 0
    private(set) var isIndexReady = false
    private var indexTask: Task<Void, Never>?

    /// Small LRU cache of decoded lines keyed by line number.
    private var lineCache: [Int: String] = [:]
    private var cacheOrder: [Int] = []
    private let cacheLimit = 4096

    /// Set when the file was truncated or rotated externally.
    private(set) var wasRotatedOrTruncated = false
    private var originalSize: UInt64

    var onIndexProgress: ((Double) -> Void)?
    var onIndexReady: (() -> Void)?

    init(url: URL) throws {
        self.url = url
        self.reader = try ChunkReader(url: url)
        self.index = LineIndex(reader: reader)
        self.originalSize = reader.fileSize
        guard let encoding = LargeFileTextEncoding.detect(reader: reader) else {
            throw LargeFileOpenError.unsupportedEncoding(url)
        }
        self.encoding = encoding
        index.onProgress = { [weak self] _, total in
            guard let self, total > 0 else { return }
            let progress = Double(min(self.index.reader.fileSize, total)) / Double(max(1, self.index.reader.fileSize))
            self.indexProgress = progress
        }
    }

    var lineCount: Int { index.lineCount }
    var fileSize: UInt64 { reader.fileSize }
    var isIndexComplete: Bool { index.isComplete }

    func startIndexing() {
        guard indexTask == nil else { return }
        indexTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var lastReport = Date.distantPast
            self.index.onProgress = { [weak self] scanned, total in
                guard let self else { return }
                let now = Date()
                guard now.timeIntervalSince(lastReport) > 0.05 else { return }
                lastReport = now
                let progress = total > 0 ? Double(scanned) / Double(total) : 1
                DispatchQueue.main.async {
                    self.indexProgress = progress
                    self.onIndexProgress?(progress)
                }
            }
            self.index.build()
            DispatchQueue.main.async {
                self.isIndexReady = true
                self.indexProgress = 1
                self.onIndexProgress?(1)
                self.onIndexReady?()
            }
            _ = lastReport
        }
    }

    func cancelIndexing() {
        indexTask?.cancel()
        indexTask = nil
    }

    // MARK: - Lines

    func lineText(at line: Int) -> String {
        if let cached = lineCache[line] {
            return cached
        }
        guard let range = index.lineRange(forLine: line) else { return "" }
        let data = index.lineBytes(range)
        var text = encoding.decode(data)
        if case .utf8(let hasBOM) = encoding, hasBOM, line == 0, text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        if text.hasSuffix("\r") {
            text.removeLast()
        }
        lineCache[line] = text
        cacheOrder.append(line)
        if cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            lineCache.removeValue(forKey: evicted)
        }
        return text
    }

    /// Byte range for a line, used by copy operations.
    func rawLineData(at line: Int) -> Data {
        guard let range = index.lineRange(forLine: line) else { return Data() }
        return index.lineBytes(range)
    }

    // MARK: - Follow / append

    /// Handles a filesystem append notification. Returns true when new
    /// content was indexed.
    @discardableResult
    func handleAppend() -> Bool {
        guard !wasRotatedOrTruncated else { return false }
        let newSize = reader.refreshFileSize()
        if newSize < originalSize {
            wasRotatedOrTruncated = true
            return false
        }
        guard newSize > originalSize else { return false }
        index.extend(to: newSize)
        originalSize = newSize
        invalidateCache()
        return true
    }

    func markRotated() {
        wasRotatedOrTruncated = true
    }

    func invalidateCache() {
        lineCache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
    }

    /// Reloads from disk, discarding index and cache.
    func reloadFromDisk() throws {
        // The reader holds the mmap; rebuild the whole backing in place by
        // re-indexing after a remap.
        reader.refreshMapping()
        index.invalidate()
        invalidateCache()
        wasRotatedOrTruncated = false
        originalSize = reader.fileSize
    }
}

enum LargeFileOpenError: LocalizedError {
    case unsupportedEncoding(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding(let url):
            return "“\(url.lastPathComponent)” appears to use UTF-16 or UTF-32, which Large File Mode does not support yet. Open it normally or convert it to UTF-8 first."
        }
    }
}
