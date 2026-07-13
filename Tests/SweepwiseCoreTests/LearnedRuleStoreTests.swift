import XCTest
@testable import SweepwiseCore

final class LearnedRuleStoreTests: XCTestCase {
    var dir: URL!
    var store: LearnedRuleStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweepwise-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = LearnedRuleStore(fileURL: dir.appendingPathComponent("learned-rules.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func sample(_ id: String, pattern: String = "/x/y") -> LearnedRule {
        LearnedRule(id: id,
            rule: Rule(id: id, pattern: pattern, category: .appLeftover, risk: .redownload,
                       context: "c", restoreNote: "r"),
            kind: .exactPath, sourceProvider: "claude",
            learnedAt: Date(timeIntervalSince1970: 1000), originPath: pattern, verified: true)
    }

    func testEmptyLoad() {
        XCTAssertEqual(store.load(), [])
        XCTAssertNil(store.lastLoadError)
    }

    func testAddAndReload() throws {
        try store.add(sample("a"))
        try store.add(sample("b", pattern: "/x/z"))
        XCTAssertEqual(store.load().map(\.id), ["a", "b"])
    }

    func testAddDedupesByPattern() throws {
        try store.add(sample("a"))
        try store.add(sample("dup"))  // same pattern "/x/y"
        XCTAssertEqual(store.load().count, 1)
    }

    func testRemove() throws {
        try store.add(sample("a"))
        try store.remove(id: "a")
        XCTAssertEqual(store.load(), [])
    }

    func testCorruptFileRenamedAside() throws {
        let url = dir.appendingPathComponent("learned-rules.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.load(), [])
        XCTAssertNotNil(store.lastLoadError)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("learned-rules.json.corrupt").path))
    }
}
