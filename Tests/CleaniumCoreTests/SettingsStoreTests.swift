import XCTest
@testable import CleaniumCore

final class SettingsStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var suiteName: String!

    override func setUp() {
        suiteName = "cleanium-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        // Don't leave persisted test suites behind on the machine.
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaults() {
        let s = SettingsStore(defaults: defaults)
        XCTAssertEqual(s.scanRoots, SettingsStore.defaultRoots)
        XCTAssertEqual(s.stalenessDays, 60)
        XCTAssertEqual(s.minSizeMB, 50)
        XCTAssertFalse(s.llmEnabled)
        XCTAssertEqual(s.llmProvider, .claude)
        XCTAssertEqual(s.llmMinSizeMB, 500)
        XCTAssertEqual(s.enabledCategories, Set(Category.allCases))
    }

    func testPersistenceRoundTrip() {
        let s1 = SettingsStore(defaults: defaults)
        s1.scanRoots = ["/tmp/only"]
        s1.stalenessDays = 10
        s1.llmEnabled = true
        s1.llmProvider = .codex
        s1.enabledCategories = [.cache]
        let s2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s2.scanRoots, ["/tmp/only"])
        XCTAssertEqual(s2.stalenessDays, 10)
        XCTAssertTrue(s2.llmEnabled)
        XCTAssertEqual(s2.llmProvider, .codex)
        XCTAssertEqual(s2.enabledCategories, [.cache])
    }

    func testDefaultRootsAreUnderHome() {
        for root in SettingsStore.defaultRoots {
            XCTAssertTrue(root.hasPrefix(NSHomeDirectory()), root)
        }
    }
}
