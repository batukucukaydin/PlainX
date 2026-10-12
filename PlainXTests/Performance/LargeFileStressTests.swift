//
//  LargeFileStressTests.swift
//  PlainXTests
//
//  Developer stress benchmarks for Large File Mode. These run only when a
//  stress configuration file exists (Scripts/benchmark.sh writes it), so they
//  never execute during normal test runs. The default fixture is a generated
//  1 GB log.
//
//  Config: ~/Library/Developer/PlainXBuild/stress-config.json
//          { "file": "/path/to/large-fixture.log" }
//

import XCTest
@testable import PlainX

final class LargeFileStressTests: XCTestCase {

    private struct StressConfig: Decodable {
        let file: String
    }

    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/PlainXBuild/stress-config.json")
    }

    private var stressFile: URL? {
        guard let data = try? Data(contentsOf: Self.configURL),
              let config = try? JSONDecoder().decode(StressConfig.self, from: data),
              FileManager.default.fileExists(atPath: config.file) else {
            return nil
        }
        return URL(fileURLWithPath: config.file)
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(stressFile != nil,
                          "No stress config found (run Scripts/benchmark.sh to create it).")
    }

    func testIndexAndMemoryOnGeneratedLargeFile() throws {
        guard let file = stressFile else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        print("[stress] fixture_bytes=\(size)")

        let start = CFAbsoluteTimeGetCurrent()
        let backing = try LargeFileBacking(url: file)
        let openMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "[stress] mmap_open_ms=%.1f", openMS))
        print("[stress] rss_after_open=\(MemoryProbe.currentRSSBytes())")

        let indexStart = CFAbsoluteTimeGetCurrent()
        let expectation = expectation(description: "indexed")
        backing.onIndexReady = { expectation.fulfill() }
        backing.startIndexing()
        wait(for: [expectation], timeout: 600)
        let indexMS = (CFAbsoluteTimeGetCurrent() - indexStart) * 1000
        print(String(format: "[stress] index_ms=%.1f", indexMS))
        print("[stress] index_lines=\(backing.lineCount)")
        print("[stress] rss_after_index=\(MemoryProbe.currentRSSBytes())")

        XCTAssertGreaterThan(backing.lineCount, 1_000_000)
    }

    func testStreamingSearchThroughput() async throws {
        guard let file = stressFile else { return }
        let reader = try ChunkReader(url: file)
        let service = StreamingSearch(reader: reader, encoding: .utf8(hasBOM: false))
        var matches = 0
        let start = CFAbsoluteTimeGetCurrent()
        var query = LargeFileSearchQuery(pattern: "ERROR")
        query.maxResults = 100_000
        for await event in service.search(query) {
            if case .match = event { matches += 1 }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let mb = Double(reader.fileSize) / (1024 * 1024)
        print(String(format: "[stress] search_matches=%d", matches))
        print(String(format: "[stress] search_seconds=%.2f", elapsed))
        print(String(format: "[stress] search_mb_per_second=%.1f", mb / max(0.001, elapsed)))
        print("[stress] rss_after_search=\(MemoryProbe.currentRSSBytes())")
        XCTAssertGreaterThan(matches, 0)
    }

    /// Full-file scan throughput using a rare pattern (few matches, so the
    /// whole file is scanned rather than stopping at the result cap).
    func testFullScanThroughput() async throws {
        guard let file = stressFile else { return }
        let reader = try ChunkReader(url: file)
        let service = StreamingSearch(reader: reader, encoding: .utf8(hasBOM: false))
        var matches = 0
        let start = CFAbsoluteTimeGetCurrent()
        var query = LargeFileSearchQuery(pattern: "request_id=9999999 ERROR")
        query.maxResults = 1_000
        for await event in service.search(query) {
            if case .match = event { matches += 1 }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let mb = Double(reader.fileSize) / (1024 * 1024)
        print(String(format: "[stress] full_scan_matches=%d", matches))
        print(String(format: "[stress] full_scan_seconds=%.2f", elapsed))
        print(String(format: "[stress] full_scan_mb_per_second=%.1f", mb / max(0.001, elapsed)))
        print("[stress] rss_after_full_scan=\(MemoryProbe.currentRSSBytes())")
    }
}
