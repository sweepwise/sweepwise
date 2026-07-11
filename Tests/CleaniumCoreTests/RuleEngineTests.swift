import XCTest
@testable import CleaniumCore

final class RuleEngineTests: XCTestCase {
    let old = Date(timeIntervalSinceNow: -90 * 86400)
    let fresh = Date()

    func makeEngine(_ rules: [Rule], learned: [LearnedRule] = []) -> RuleEngine {
        RuleEngine(bundled: rules, learned: learned)
    }

    func testBasenameGlobMatches() {
        let r = Rule(id: "nm", pattern: "node_modules", category: .devArtifact,
                     risk: .rebuildable, context: "c", restoreNote: "r")
        let c = makeEngine([r]).classify(path: "/a/b/node_modules", modifiedAt: fresh, now: fresh)
        XCTAssertEqual(c?.provenance, .bundled(ruleID: "nm"))
    }

    func testPathGlobMatches() {
        let home = NSHomeDirectory()
        let r = Rule(id: "lc", pattern: "~/Library/Caches/*", category: .cache,
                     risk: .safe, context: "c", restoreNote: "r")
        let engine = makeEngine([r])
        XCTAssertNotNil(engine.classify(path: home + "/Library/Caches/com.foo",
                                        modifiedAt: fresh, now: fresh))
        XCTAssertNil(engine.classify(path: home + "/Library/Other/com.foo",
                                     modifiedAt: fresh, now: fresh))
    }

    func testStalenessGate() {
        let r = Rule(id: "dl", pattern: "~/Downloads/*", category: .download,
                     risk: .userData, context: "c", restoreNote: "r", stalenessDays: 60)
        let engine = makeEngine([r])
        let p = NSHomeDirectory() + "/Downloads/big.dmg"
        XCTAssertNil(engine.classify(path: p, modifiedAt: fresh, now: fresh))
        XCTAssertNotNil(engine.classify(path: p, modifiedAt: old, now: fresh))
    }

    func testBundledBeatsLearned() {
        let b = Rule(id: "b", pattern: "node_modules", category: .devArtifact,
                     risk: .rebuildable, context: "bundled", restoreNote: "r")
        let lr = LearnedRule(id: "l", rule: Rule(id: "l", pattern: "node_modules",
                     category: .unknown, risk: .unknown, context: "learned", restoreNote: "r"),
                     kind: .glob, sourceProvider: "claude", learnedAt: Date(),
                     originPath: "/x", verified: false)
        let c = makeEngine([b], learned: [lr])
            .classify(path: "/x/node_modules", modifiedAt: fresh, now: fresh)
        XCTAssertEqual(c?.provenance, .bundled(ruleID: "b"))
    }

    func testLearnedRuleMatches() {
        let lr = LearnedRule(id: "l1", rule: Rule(id: "l1", pattern: "/private/x/voice",
                     category: .appLeftover, risk: .userData, context: "c", restoreNote: "r"),
                     kind: .exactPath, sourceProvider: "codex", learnedAt: Date(),
                     originPath: "/private/x/voice", verified: true)
        let c = makeEngine([], learned: [lr])
            .classify(path: "/private/x/voice", modifiedAt: fresh, now: fresh)
        XCTAssertEqual(c?.provenance, .learned(ruleID: "l1"))
    }

    func testBundledRulesLoadAndAreWellFormed() throws {
        let rules = try RuleEngine.loadBundledRules()
        XCTAssertGreaterThanOrEqual(rules.count, 25)
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count, "duplicate rule ids")
        for r in rules {
            XCTAssertFalse(r.context.isEmpty, "\(r.id) missing context")
            XCTAssertFalse(r.restoreNote.isEmpty, "\(r.id) missing restoreNote")
        }
    }
}
