import XCTest
@testable import SweepwiseCore

final class ScannerTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweepwise-scan-\(UUID().uuidString)")
        // Fixture tree:
        // root/projA/node_modules/dep/big.bin   (2 KB)   -> candidate (rule nm)
        // root/projA/src/main.js                (10 B)   -> plain file
        // root/unknownBig/blob.bin              (4 KB)   -> unknown dir
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("projA/node_modules/dep"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("projA/src"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("unknownBig"),
                               withIntermediateDirectories: true)
        try Data(count: 2048).write(to: root.appendingPathComponent("projA/node_modules/dep/big.bin"))
        try Data(count: 10).write(to: root.appendingPathComponent("projA/src/main.js"))
        try Data(count: 4096).write(to: root.appendingPathComponent("unknownBig/blob.bin"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func makeScanner(minSize: Int64 = 0, llmMin: Int64 = 1024) -> SweepwiseCore.Scanner {
        let nm = Rule(id: "nm", pattern: "node_modules", category: .devArtifact,
                      risk: .rebuildable, context: "c", restoreNote: "r")
        return SweepwiseCore.Scanner(engine: RuleEngine(bundled: [nm], learned: []),
                                    minSizeBytes: minSize, llmMinSizeBytes: llmMin)
    }

    func testFindsCandidateAndDoesNotDescendIntoIt() {
        let result = makeScanner().scan(roots: [root.path], progress: nil, isCancelled: { false })
        XCTAssertEqual(result.candidates.count, 1)
        let c = result.candidates[0]
        XCTAssertTrue(c.path.hasSuffix("node_modules"))
        XCTAssertGreaterThanOrEqual(c.sizeBytes, 2048)
    }

    func testMinSizeFloorFiltersCandidates() {
        let result = makeScanner(minSize: 10_000).scan(roots: [root.path],
                                                       progress: nil, isCancelled: { false })
        XCTAssertEqual(result.candidates.count, 0)
    }

    func testUnknownBigDirSurfaced() {
        let result = makeScanner().scan(roots: [root.path], progress: nil, isCancelled: { false })
        XCTAssertEqual(result.unknownDirs.map { ($0.path as NSString).lastPathComponent },
                       ["unknownBig"])
        XCTAssertGreaterThanOrEqual(result.unknownDirs[0].sizeBytes, 4096)
    }

    func testProjWithCandidateNotInUnknownDirs() {
        let result = makeScanner().scan(roots: [root.path], progress: nil, isCancelled: { false })
        XCTAssertFalse(result.unknownDirs.contains { $0.path.hasSuffix("projA") })
    }

    func testCancellationStopsEarly() {
        let result = makeScanner().scan(roots: [root.path], progress: nil, isCancelled: { true })
        XCTAssertEqual(result.candidates.count, 0)
    }

    func testMissingRootGoesToSkipped() {
        let result = makeScanner().scan(roots: ["/nonexistent-sweepwise-root"],
                                        progress: nil, isCancelled: { false })
        XCTAssertEqual(result.skipped, ["/nonexistent-sweepwise-root"])
    }

    func testCandidatesStreamedViaCallback() {
        var streamed: [String] = []
        let result = makeScanner().scan(roots: [root.path],
                                        onCandidate: { streamed.append($0.path) },
                                        isCancelled: { false })
        XCTAssertEqual(streamed, result.candidates.map(\.path))
        XCTAssertEqual(streamed.count, 1)
    }

    func testPauseBlocksScanUntilResumed() {
        let lock = NSLock()
        var paused = true
        var finished = false
        let done = expectation(description: "scan finished after resume")
        DispatchQueue.global().async {
            _ = self.makeScanner().scan(
                roots: [self.root.path],
                isPaused: { lock.lock(); defer { lock.unlock() }; return paused },
                isCancelled: { false })
            lock.lock(); finished = true; lock.unlock()
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.3)
        lock.lock(); let blockedWhilePaused = !finished; lock.unlock()
        XCTAssertTrue(blockedWhilePaused, "scan should block while paused")
        lock.lock(); paused = false; lock.unlock()
        wait(for: [done], timeout: 5)
    }

    func testCancelWhilePausedStopsScan() {
        let lock = NSLock()
        var cancelled = false
        let done = expectation(description: "scan exits when cancelled during pause")
        DispatchQueue.global().async {
            _ = self.makeScanner().scan(
                roots: [self.root.path],
                isPaused: { true },
                isCancelled: { lock.lock(); defer { lock.unlock() }; return cancelled })
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.2)
        lock.lock(); cancelled = true; lock.unlock()
        wait(for: [done], timeout: 5)
    }
}
