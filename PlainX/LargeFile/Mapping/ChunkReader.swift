//
//  ChunkReader.swift
//  PlainX Editor
//
//  Memory-mapped read-only access to a large file. The file is mapped rather
//  than read: pages become resident only as they are touched, so working-set
//  memory for a 1 GB file stays far below the file size.
//

import Foundation

enum ChunkReaderError: LocalizedError {
    case cannotOpen(URL, Int32)
    case cannotMap(URL, Int32)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let url, let code):
            return "Could not open “\(url.lastPathComponent)” for reading (errno \(code))."
        case .cannotMap(let url, let code):
            return "Could not memory-map “\(url.lastPathComponent)” (errno \(code))."
        }
    }
}

final class ChunkReader {
    let url: URL
    private(set) var fileSize: UInt64
    private var fileDescriptor: Int32 = -1
    private var mappedPointer: UnsafeMutableRawPointer?
    private var mappedLength: Int = 0

    /// Text beyond this chunk size is decoded/copied explicitly.
    static let defaultChunkSize = 4 * 1024 * 1024

    static func looksLikeRegularReadableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    init(url: URL) throws {
        self.url = url
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw ChunkReaderError.cannotOpen(url, errno)
        }
        fileDescriptor = descriptor

        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            close(descriptor)
            fileDescriptor = -1
            throw ChunkReaderError.cannotOpen(url, errno)
        }
        fileSize = UInt64(max(0, status.st_size))

        if fileSize > 0 {
            let length = Int(min(fileSize, UInt64(Int.max)))
            let pointer = mmap(nil, length, PROT_READ, MAP_PRIVATE, descriptor, 0)
            if pointer == MAP_FAILED {
                close(descriptor)
                fileDescriptor = -1
                throw ChunkReaderError.cannotMap(url, errno)
            }
            mappedPointer = pointer
            mappedLength = length
        }
    }

    deinit {
        if let mappedPointer, mappedLength > 0 {
            munmap(mappedPointer, mappedLength)
        }
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }

    /// Re-reads the file size (used by follow mode after append events).
    @discardableResult
    func refreshFileSize() -> UInt64 {
        var status = stat()
        guard fileDescriptor >= 0, fstat(fileDescriptor, &status) == 0 else { return fileSize }
        fileSize = UInt64(max(0, status.st_size))
        return fileSize
    }

    /// Re-maps the file when it grew (follow mode). Returns true when the
    /// reader is usable after the call.
    @discardableResult
    func refreshMapping() -> Bool {
        let newSize = refreshFileSize()
        let newLength = Int(min(newSize, UInt64(Int.max)))
        if newLength == mappedLength { return true }

        if mappedLength > 0, let oldPointer = mappedPointer {
            munmap(oldPointer, mappedLength)
            mappedPointer = nil
            mappedLength = 0
        }
        guard newLength > 0 else { return true }
        let pointer = mmap(nil, newLength, PROT_READ, MAP_PRIVATE, fileDescriptor, 0)
        if pointer == MAP_FAILED {
            return false
        }
        mappedPointer = pointer
        mappedLength = newLength
        return true
    }

    /// True when the underlying file was replaced (rotation) or truncated.
    func detectRotation(originalSize: UInt64) -> Bool {
        var status = stat()
        guard fstat(fileDescriptor, &status) == 0 else { return true }
        let newSize = UInt64(max(0, status.st_size))
        if newSize < originalSize { return true }
        // Compare inode via path.
        var pathStatus = stat()
        if stat(url.path, &pathStatus) == 0 {
            if pathStatus.st_ino != status.st_ino { return true }
        }
        return false
    }

    var canMapWholeFile: Bool { mappedPointer != nil }

    /// Copies `length` bytes at `offset` (clamped to the mapped region).
    func read(offset: UInt64, length: Int) -> Data {
        guard let pointer = mappedPointer, length > 0 else { return Data() }
        let safeOffset = min(offset, UInt64(mappedLength))
        let remaining = mappedLength - Int(safeOffset)
        let safeLength = max(0, min(length, remaining))
        guard safeLength > 0 else { return Data() }
        return Data(bytes: pointer.advanced(by: Int(safeOffset)), count: safeLength)
    }

    /// Runs `body` with direct access to mapped bytes (no copy). The pointer is
    /// valid only for the duration of the call and must not be retained.
    func withUnsafeBytes<Result>(offset: UInt64, length: Int,
                                 _ body: (UnsafeRawPointer, Int) throws -> Result) rethrows -> Result? {
        guard let pointer = mappedPointer else { return nil }
        let safeOffset = min(offset, UInt64(mappedLength))
        let remaining = mappedLength - Int(safeOffset)
        let safeLength = max(0, min(length, remaining))
        guard safeLength > 0 else { return nil }
        return try body(pointer.advanced(by: Int(safeOffset)), safeLength)
    }

    func byte(at offset: UInt64) -> UInt8? {
        guard let pointer = mappedPointer, offset < UInt64(mappedLength) else { return nil }
        return pointer.advanced(by: Int(offset)).assumingMemoryBound(to: UInt8.self).pointee
    }

    /// Reads bytes at `offset` into a caller-provided reusable buffer using
    /// `pread`. Streaming passes (indexing, search) use this instead of
    /// touching the mapping so that scanning a multi-gigabyte file does not
    /// accumulate resident file-backed pages. Returns the number of bytes
    /// actually read (may be short at EOF).
    @discardableResult
    func readInto(_ buffer: inout Data, offset: UInt64, length: Int) -> Int {
        guard fileDescriptor >= 0, offset < fileSize else { return 0 }
        let remaining = Int(min(fileSize - offset, UInt64(Int.max)))
        let wanted = min(length, remaining)
        guard wanted > 0 else { return 0 }
        if buffer.count < wanted {
            buffer.count = wanted
        }
        let readCount = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return pread(fileDescriptor, base, wanted, off_t(offset))
        }
        return max(0, readCount)
    }

    /// Releases already-scanned mapped pages back to the system.
    func releasePages(offset: UInt64, length: Int) {
        guard let pointer = mappedPointer, length > 0 else { return }
        let safeOffset = min(offset, UInt64(mappedLength))
        let remaining = mappedLength - Int(safeOffset)
        let safeLength = max(0, min(length, remaining))
        guard safeLength > 0 else { return }
        _ = madvise(pointer.advanced(by: Int(safeOffset)), safeLength, MADV_DONTNEED)
    }

    /// Finds the first occurrence of `needle` in the byte range using a simple
    /// two-level scan on mapped memory. Returns an absolute byte offset.
    func findBytes(_ needle: [UInt8], from startOffset: UInt64, to endOffset: UInt64) -> UInt64? {
        guard !needle.isEmpty, let pointer = mappedPointer else { return nil }
        let start = Int(min(startOffset, UInt64(mappedLength)))
        let end = Int(min(endOffset, UInt64(mappedLength)))
        guard end > start else { return nil }
        let haystackCount = end - start
        let needleCount = needle.count
        guard needleCount <= haystackCount else { return nil }

        let base = pointer.advanced(by: start)
        var cursor = base
        let limit = base.advanced(by: haystackCount - needleCount)
        while cursor <= limit {
            guard let hit = memchr(cursor, Int32(needle[0]), limit.distance(to: cursor) + needleCount) else {
                return nil
            }
            if memcmp(hit, needle, needleCount) == 0 {
                return UInt64(start + base.distance(to: hit))
            }
            cursor = hit.advanced(by: 1)
        }
        return nil
    }
}
