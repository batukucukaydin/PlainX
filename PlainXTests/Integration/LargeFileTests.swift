//
//  LargeFileTests.swift
//  PlainXTests
//
//  Large File Mode: memory-mapped reading, sparse line index, streaming
//  search across chunk boundaries, follow/tail behavior, and the
//  pathological long-line case.
//

import XCTest
@testable import PlainX

final class ChunkReaderTests: XCTestCase {

    func testReadAcrossBoundaries() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("data.bin")
        var data = Data()
        for index in 0..<10_000 {
            data.append(contentsOf: "line \(index)\n".utf8)
        }
        try data.write(to: url)
        let reader = try ChunkReader(url: url)
        XCTAssertEqual(reader.fileSize, UInt64(data.count))
        let chunk = reader.read(offset: 0, length: 10)
        XCTAssertEqual(String(decoding: chunk, as: UTF8.self), "line 0\nlin")
        let tail = reader.read(offset: UInt64(data.count - 5), length: 100)
        XCTAssertEqual(tail.count, 5, "reads must clamp at EOF")
        try TestHelpers.remove(directory)
    }

    func testFindBytes() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("needle.txt")
        let content = "aaaaNEEDLEbbbb"
        try Data(content.utf8).write(to: url)
        let reader = try ChunkReader(url: url)
        let needle = Array("NEEDLE".utf8)
        XCTAssertEqual(reader.findBytes(needle, from: 0, to: reader.fileSize), 4)
        XCTAssertNil(reader.findBytes(Array("MISSING".utf8), from: 0, to: reader.fileSize))
        try TestHelpers.remove(directory)
    }

    func testEmptyFile() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("empty.txt")
        try Data().write(to: url)
        let reader = try ChunkReader(url: url)
        XCTAssertEqual(reader.fileSize, 0)
        XCTAssertTrue(reader.read(offset: 0, length: 10).isEmpty)
        try TestHelpers.remove(directory)
    }
}

final class LineIndexTests: XCTestCase {

    private func makeIndexedFile(lines: [String], trailingNewline: Bool = true) throws -> (LineIndex, ChunkReader, URL) {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("indexed.txt")
        let content = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try Data(content.utf8).write(to: url)
        let reader = try ChunkReader(url: url)
        let index = LineIndex(reader: reader, checkpointStride: 1024, buildChunkSize: 4096)
        index.build()
        return (index, reader, url)
    }

    func testLineCountMatchesReference() throws {
        let lines = (0..<50_000).map { "line \($0) content" }
        let (index, _, url) = try makeIndexedFile(lines: lines)
        XCTAssertEqual(index.lineCount, lines.count + 1, "trailing newline produces a final empty line")
        try TestHelpers.remove(url.deletingLastPathComponent())
    }

    func testLineRangesMatchReference() throws {
        let lines = (0..<20_000).map { "row \($0)" }
        let (index, _, url) = try makeIndexedFile(lines: lines)
        // Verify a spread of lines (start, middle, end) against a reference split.
        let reference = lines.joined(separator: "\n") + "\n"
        for lineNumber in [0, 1, 500, 9_999, 19_998, 20_000] {
            guard let range = index.lineRange(forLine: lineNumber) else {
                XCTFail("missing range for line \(lineNumber)")
                continue
            }
            let bytes = index.lineBytes(range)
            let expected = lineNumber < lines.count ? lines[lineNumber] : ""
            XCTAssertEqual(String(decoding: bytes, as: UTF8.self), expected, "line \(lineNumber)")
        }
        _ = reference
        try TestHelpers.remove(url.deletingLastPathComponent())
    }

    func testLineForOffset() throws {
        let (index, _, url) = try makeIndexedFile(lines: ["alpha", "beta", "gamma"])
        XCTAssertEqual(index.line(forOffset: 0), 0)
        XCTAssertEqual(index.line(forOffset: 7), 1)
        XCTAssertEqual(index.line(forOffset: 12), 2)
        try TestHelpers.remove(url.deletingLastPathComponent())
    }

    func testExtendAfterAppend() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("growing.log")
        try Data("first\nsecond\n".utf8).write(to: url)
        let reader = try ChunkReader(url: url)
        let index = LineIndex(reader: reader, checkpointStride: 4096, buildChunkSize: 4096)
        index.build()
        let initialCount = index.lineCount
        XCTAssertEqual(initialCount, 3)

        // Append more lines through a file handle so the mmap must refresh.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("third\nfourth\n".utf8))
        try handle.close()

        index.extend(to: reader.refreshFileSize())
        XCTAssertEqual(index.lineCount, 5)
        let fourth = try XCTUnwrap(index.lineRange(forLine: 3))
        XCTAssertEqual(String(decoding: index.lineBytes(fourth), as: UTF8.self), "fourth")
        try TestHelpers.remove(directory)
    }

    func testNoTrailingNewline() throws {
        let (index, _, url) = try makeIndexedFile(lines: ["a", "b"], trailingNewline: false)
        XCTAssertEqual(index.lineCount, 2)
        XCTAssertEqual(String(decoding: index.lineBytes(index.lineRange(forLine: 1)!), as: UTF8.self), "b")
        try TestHelpers.remove(url.deletingLastPathComponent())
    }
}

final class StreamingSearchTests: XCTestCase {

    private func collect(_ stream: AsyncStream<LargeFileSearchEvent>) async -> (matches: [LargeFileSearchMatch], finished: Bool, cancelled: Bool, cap: Bool) {
        var matches: [LargeFileSearchMatch] = []
        var finished = false
        var cancelled = false
        var cap = false
        for await event in stream {
            switch event {
            case .match(let match): matches.append(match)
            case .finished(_, let wasCancelled, let reachedCap):
                finished = true
                cancelled = wasCancelled
                cap = reachedCap
            default: break
            }
        }
        return (matches, finished, cancelled, cap)
    }

    func testLiteralSearchAcrossSmallChunks() async throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("search.txt")
        var lines: [String] = []
        for index in 0..<30_000 {
            lines.append(index % 3000 == 0 ? "MATCH at \(index)" : "ordinary line \(index)")
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
        let reader = try ChunkReader(url: url)
        let service = StreamingSearch(reader: reader, encoding: .utf8(hasBOM: false), chunkSize: 256 * 1024)
        var query = LargeFileSearchQuery(pattern: "MATCH")
        query.maxResults = 100
        let result = await collect(service.search(query))
        XCTAssertTrue(result.finished)
        XCTAssertEqual(result.matches.count, 10)
        XCTAssertEqual(result.matches.first?.lineNumber, 0)
        try TestHelpers.remove(directory)
    }

    func testMatchExactlyOnChunkBoundary() async throws {
        // Build content where the needle straddles a 256 KiB boundary by
        // padding a prefix line with an exact byte count.
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("boundary.txt")
        let chunkSize = 256 * 1024
        var text = String(repeating: "x", count: chunkSize - 3)
        text += "MATCH-tail\n"
        text += "another MATCH\n"
        try Data(text.utf8).write(to: url)
        let reader = try ChunkReader(url: url)
        let service = StreamingSearch(reader: reader, encoding: .utf8(hasBOM: false), chunkSize: chunkSize)
        let result = await collect(service.search(LargeFileSearchQuery(pattern: "MATCH")))
        XCTAssertEqual(result.matches.count, 2, "boundary match must not be lost")
        try TestHelpers.remove(directory)
    }

    func testCaseInsensitiveAndRegex() async throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("mixed.log")
        try Data("Error: bad\nERROR: worse\nerror: worst\n".utf8).write(to: url)
        let reader = try ChunkReader(url: url)
        let service = StreamingSearch(reader: reader, encoding: .utf8(hasBOM: false))

        let insensitive = await collect(service.search(LargeFileSearchQuery(pattern: "error")))
        XCTAssertEqual(insensitive.matches.count, 3)

        var regexQuery = LargeFileSearchQuery(pattern: "error: \\w+")
        regexQuery.isRegex = true
        regexQuery.caseSensitive = false
        let regex = await collect(service.search(regexQuery))
        XCTAssertEqual(regex.matches.count, 3)
        try TestHelpers.remove(directory)
    }

    func testCancellationStopsStreaming() async throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("big.txt")
        var data = Data()
        for index in 0..<400_000 {
            data.append(contentsOf: "MATCH line \(index)\n".utf8)
        }
        try data.write(to: url)
        let reader = try ChunkReader(url: url)
        let service = StreamingSearch(reader: reader, encoding: .utf8(hasBOM: false), chunkSize: 128 * 1024)
        var query = LargeFileSearchQuery(pattern: "MATCH")
        query.maxResults = 1_000_000
        let stream = service.search(query)
        var seen = 0
        for await event in stream {
            if case .match = event {
                seen += 1
                if seen == 100 { service.cancel() }
            }
        }
        XCTAssertLessThan(seen, 400_000)
        try TestHelpers.remove(directory)
    }

    func testResultCapIsReported() async throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("capped.txt")
        var data = Data()
        for index in 0..<5_000 {
            data.append(contentsOf: "hit \(index)\n".utf8)
        }
        try data.write(to: url)
        let reader = try ChunkReader(url: url)
        let service = StreamingSearch(reader: reader, encoding: .utf8(hasBOM: false))
        var query = LargeFileSearchQuery(pattern: "hit")
        query.maxResults = 50
        let result = await collect(service.search(query))
        XCTAssertEqual(result.matches.count, 50)
        XCTAssertTrue(result.cap)
        try TestHelpers.remove(directory)
    }
}

final class LargeFileModeIntegrationTests: XCTestCase {

    /// Generates a moderately large fixture (about 24 MB) rather than
    /// committing binaries. The 1 GB scenario is exercised by
    /// Scripts/benchmark-largefile.sh.
    func testLargeFileBackingDetectsEncodingAndIndexes() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("big.log")
        let handle = FileHandle(forWritingAtPath: url.path) ?? {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            return FileHandle(forWritingAtPath: url.path)!
        }()
        defer { try? handle.close() }
        for index in 0..<300_000 {
            let line = "2026-01-01T00:00:00Z INFO line \(index) payload payload payload\n"
            try handle.write(contentsOf: Data(line.utf8))
        }
        try handle.close()

        let backing = try LargeFileBacking(url: url)
        XCTAssertEqual(backing.encoding, .utf8(hasBOM: false))
        backing.startIndexing()
        let expectation = expectation(description: "indexing finished")
        backing.onIndexReady = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 30)
        // The final newline produces one trailing empty line.
        XCTAssertEqual(backing.lineCount, 300_001)
        XCTAssertTrue(backing.lineText(at: 299_999).hasSuffix("payload payload payload"))
        try TestHelpers.remove(directory)
    }

    /// A single 12 MB line must not hang or exhaust memory in the search path.
    func testExtremelyLongSingleLine() async throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("longline.txt")
        var data = Data(repeating: 0x61, count: 12 * 1024 * 1024) // 12 MB of 'a'
        data.append(contentsOf: Data("NEEDLE".utf8))
        data.append(contentsOf: Data(repeating: 0x62, count: 1024))
        try data.write(to: url)

        let reader = try ChunkReader(url: url)
        let index = LineIndex(reader: reader, checkpointStride: 1024 * 1024, buildChunkSize: 1024 * 1024)
        index.build()
        XCTAssertEqual(index.lineCount, 1, "one line without terminator")

        let service = StreamingSearch(reader: reader, encoding: .utf8(hasBOM: false), chunkSize: 256 * 1024)
        var found: [LargeFileSearchMatch] = []
        for await event in service.search(LargeFileSearchQuery(pattern: "NEEDLE")) {
            if case .match(let match) = event { found.append(match) }
        }
        XCTAssertEqual(found.count, 1)
        try TestHelpers.remove(directory)
    }

    func testTailAppendAppearsAfterExtend() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("tail.log")
        try Data((0..<1_000).map { "line \($0)" }.joined(separator: "\n").appending("\n").utf8).write(to: url)

        let backing = try LargeFileBacking(url: url)
        backing.startIndexing()
        let expectation = expectation(description: "indexed")
        backing.onIndexReady = { expectation.fulfill() }
        wait(for: [expectation], timeout: 20)
        // 1,000 terminated lines plus the trailing empty line.
        XCTAssertEqual(backing.lineCount, 1_001)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("appended line\n".utf8))
        try handle.close()

        XCTAssertTrue(backing.handleAppend())
        XCTAssertEqual(backing.lineCount, 1_002)
        XCTAssertEqual(backing.lineText(at: 1_000), "appended line")
        try TestHelpers.remove(directory)
    }

    func testTruncationDetected() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("truncate.log")
        try Data("some content here\n".utf8).write(to: url)
        let backing = try LargeFileBacking(url: url)
        try Data("short\n".utf8).write(to: url)
        XCTAssertFalse(backing.handleAppend(), "truncation must not be treated as an append")
        XCTAssertTrue(backing.wasRotatedOrTruncated)
        try TestHelpers.remove(directory)
    }

    func testMainWindowCreatesLargeFileTab() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("window.log")
        try Data((0..<2_000).map { "log line \($0)" }.joined(separator: "\n").utf8).write(to: url)

        let coordinator = AppCoordinator()
        let window = coordinator.newWindow()
        let document = try coordinator.openDocument(at: url)
        // Force the large-file path regardless of the configured threshold.
        if coordinator.consumePendingLargeFileBacking(for: document) == nil {
            let backing = try LargeFileBacking(url: url)
            coordinator.setPendingLargeFileBacking(backing, for: document)
            document.isLargeFileMode = true
        }
        window.addTab(for: document, select: true)
        XCTAssertEqual(window.tabs.count, 1)
        XCTAssertTrue(window.tabs[0].isLargeFileViewer)
        XCTAssertFalse(window.tabs[0].document.isDirty)
        window.forceCloseWindow()
        try TestHelpers.remove(directory)
    }
}
