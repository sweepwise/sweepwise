import XCTest
@testable import SweepwiseCore

final class ModelsTests: XCTestCase {
    func testRuleDecodesFromJSON() throws {
        let json = """
        {"id": "node-modules", "pattern": "node_modules",
         "category": "devArtifact", "risk": "rebuildable",
         "context": "npm/pnpm install output", "restoreNote": "run pnpm install",
         "stalenessDays": 30}
        """.data(using: .utf8)!
        let rule = try JSONDecoder().decode(Rule.self, from: json)
        XCTAssertEqual(rule.id, "node-modules")
        XCTAssertEqual(rule.category, .devArtifact)
        XCTAssertEqual(rule.risk, .rebuildable)
        XCTAssertEqual(rule.stalenessDays, 30)
    }

    func testRuleStalenessOptional() throws {
        let json = """
        {"id": "x", "pattern": "y", "category": "cache", "risk": "safe",
         "context": "c", "restoreNote": "r"}
        """.data(using: .utf8)!
        let rule = try JSONDecoder().decode(Rule.self, from: json)
        XCTAssertNil(rule.stalenessDays)
    }

    func testLearnedRuleRoundTrip() throws {
        let learned = LearnedRule(
            id: "L1",
            rule: Rule(id: "L1", pattern: "/tmp/x", category: .appLeftover,
                       risk: .redownload, context: "c", restoreNote: "r"),
            kind: .exactPath, sourceProvider: "claude",
            learnedAt: Date(timeIntervalSince1970: 0), originPath: "/tmp/x",
            verified: true)
        let data = try JSONEncoder().encode(learned)
        let back = try JSONDecoder().decode(LearnedRule.self, from: data)
        XCTAssertEqual(back, learned)
    }
}
