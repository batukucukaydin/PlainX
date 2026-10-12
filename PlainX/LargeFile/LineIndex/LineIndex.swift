//
//  LineIndex.swift
//  PlainX Editor
//
//  Sparse line index for very large files. Instead of one entry per line,
//  checkpoints are stored every `checkpointStride` bytes and the exact line is
//  resolved by scanning a bounded window from the nearest checkpoint. This
//  keeps memory proportional to file size / stride rather than line count.
//

import Foundation

struct LineRange {
    /// Byte offset of the first character of the line.
    let start: UInt64
    /// Byte offset one past the line terminator (or EOF).
    let end: UInt64
    /// True when the line is followed by a terminator.
    let hasTerminator: Bool

    var byteLength: UInt64 { end - start }
}

final class LineIndex {
    private struct Checkpoint {
        let byteOffset: UInt64
        let lineNumber: Int
    }

    private(set) var reader: ChunkReader
    private(set) var isComplete = false
    private(set) var lineCount: Int = 0
    /// Total lines minus one (valid only when complete) or the estimate while
    /// building; used for scroll sizing.
    private(set) var estimatedLineCount: Int = 0

    private var checkpoints: [Checkpoint] = []
    private let checkpointStride: UInt64
    private let buildChunkSize: Int
    /// Byte size of the region covered by the index so far.
    private(set) var indexedSize: UInt64 = 0

    /// Progress callback: (bytes indexed, total bytes).
    var onProgress: ((UInt64, UInt64) -> Void)?

    init(reader: ChunkReader, checkpointStride: UInt64 = 1024 * 1024, buildChunkSize: Int = 8 * 1024 * 1024) {
        self.reader = reader
        self.checkpointStride = max(64 * 1024, checkpointStride)
        self.buildChunkSize = max(256 * 1024, buildChunkSize)
        checkpoints.append(Checkpoint(byteOffset: 0, lineNumber: 0))
    }

    /// Discards all progress (used after a reload).
    func invalidate() {
        checkpoints = [Checkpoint(byteOffset: 0, lineNumber: 0)]
        isComplete = false
        lineCount = 0
        estimatedLineCount = 0
        indexedSize = 0
    }

    /// Builds the index synchronously. Safe to call on a background thread.
    func build() {
        var offset: UInt64 = 0
        var lineNumber = 0
        var nextCheckpoint = checkpointStride
        let total = reader.fileSize
        var buffer = Data(count: buildChunkSize)

        while offset < total {
            let length = Int(min(UInt64(buildChunkSize), total - offset))
            let scanned = reader.readInto(&buffer, offset: offset, length: length)
            guard scanned > 0 else { break }
            var newCheckpoints: [Checkpoint] = []
            let newlines = buffer.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                var count0 = 0
                var index = 0
                while index < scanned {
                    if bytes[index] == 0x0A {
                        count0 += 1
                        let absolute = offset + UInt64(index) + 1
                        if absolute >= nextCheckpoint {
                            newCheckpoints.append(Checkpoint(byteOffset: absolute, lineNumber: lineNumber + count0))
                            nextCheckpoint = absolute + checkpointStride
                        }
                    }
                    index += 1
                }
                return count0
            }
            lineNumber += newlines
            checkpoints.append(contentsOf: newCheckpoints)
            offset += UInt64(scanned)
            onProgress?(offset, total)
        }

        lineCount = lineNumber + 1
        estimatedLineCount = lineCount
        indexedSize = reader.fileSize
        isComplete = true
    }

    /// Extends the index after an append (follow mode). Only new bytes are
    /// scanned.
    func extend(to newSize: UInt64) {
        guard isComplete else { return }
        let oldSize = indexedSize
        guard newSize > oldSize else { return }
        guard reader.refreshMapping() else { return }
        var offset = oldSize
        // A line may have been partially written before the previous EOF; start
        // re-scanning from the beginning of that line if it had no terminator.
        if let lastLine = lineRange(forLine: max(0, lineCount - 1)), !lastLine.hasTerminator {
            offset = lastLine.start
            lineCount = max(1, lineCount - 1)
        }
        // lineCount is (newlines + 1); track the newline count directly.
        var newlineCount = max(0, lineCount - 1)
        let total = newSize
        var buffer = Data(count: buildChunkSize)
        while offset < total {
            let length = Int(min(UInt64(buildChunkSize), total - offset))
            let scanned = reader.readInto(&buffer, offset: offset, length: length)
            guard scanned > 0 else { break }
            let newlines = buffer.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                var count0 = 0
                var index = 0
                while index < scanned {
                    if bytes[index] == 0x0A {
                        count0 += 1
                    }
                    index += 1
                }
                return count0
            }
            newlineCount += newlines
            offset += UInt64(scanned)
        }
        lineCount = newlineCount + 1
        estimatedLineCount = lineCount
        indexedSize = newSize
    }

    /// Resolves the byte range of a line. Valid only when the index is
    /// complete (or the requested line is below the built range).
    func lineRange(forLine lineNumber: Int) -> LineRange? {
        guard lineNumber >= 0, lineNumber < lineCount else { return nil }
        let checkpoint = checkpoint(forLine: lineNumber)
        var currentLine = checkpoint.lineNumber
        var position = checkpoint.byteOffset
        let total = reader.fileSize

        while currentLine < lineNumber, position < total {
            guard let newline = reader.findBytes([0x0A], from: position, to: total) else {
                break
            }
            currentLine += 1
            position = newline + 1
        }
        guard currentLine == lineNumber else { return nil }

        let start = position
        if let newline = reader.findBytes([0x0A], from: start, to: total) {
            return LineRange(start: start, end: newline + 1, hasTerminator: true)
        }
        return LineRange(start: start, end: total, hasTerminator: false)
    }

    /// Resolves the line containing the given byte offset.
    func line(forOffset offset: UInt64) -> Int? {
        guard isComplete, offset <= reader.fileSize else { return nil }
        let checkpoint = checkpoint(forOffset: offset)
        var line = checkpoint.lineNumber
        var position = checkpoint.byteOffset
        while position < offset {
            guard let newline = reader.findBytes([0x0A], from: position, to: min(offset + 1, reader.fileSize)) else {
                break
            }
            line += 1
            position = newline + 1
        }
        return line
    }

    /// Reads the raw bytes of a line (without the terminator).
    func lineBytes(_ line: LineRange) -> Data {
        let end = line.hasTerminator ? line.end - 1 : line.end
        return reader.read(offset: line.start, length: Int(end - line.start))
    }

    // MARK: - Checkpoint lookup

    private func checkpoint(forLine lineNumber: Int) -> Checkpoint {
        var lower = 0
        var upper = checkpoints.count - 1
        while lower < upper {
            let mid = (lower + upper + 1) / 2
            if checkpoints[mid].lineNumber <= lineNumber {
                lower = mid
            } else {
                upper = mid - 1
            }
        }
        return checkpoints[lower]
    }

    private func checkpoint(forOffset offset: UInt64) -> Checkpoint {
        var lower = 0
        var upper = checkpoints.count - 1
        while lower < upper {
            let mid = (lower + upper + 1) / 2
            if checkpoints[mid].byteOffset <= offset {
                lower = mid
            } else {
                upper = mid - 1
            }
        }
        return checkpoints[lower]
    }

    /// Approximate average line length; used for scroll sizing before the
    /// index completes.
    var averageLineLength: Double {
        guard lineCount > 1 else { return 64 }
        return Double(reader.fileSize) / Double(lineCount)
    }

    var checkpointCount: Int { checkpoints.count }
}
