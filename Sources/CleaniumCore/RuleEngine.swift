import Foundation

public enum Glob {
    /// Patterns containing "/" match the full path (after ~ expansion).
    /// Bare patterns match the last path component.
    public static func matches(pattern: String, path: String) -> Bool {
        if pattern.contains("/") {
            let expanded = (pattern as NSString).expandingTildeInPath
            return fnmatch(expanded, path, 0) == 0
        }
        let name = (path as NSString).lastPathComponent
        return fnmatch(pattern, name, 0) == 0
    }
}

public struct RuleEngine {
    public let bundled: [Rule]
    public let learned: [LearnedRule]

    public init(bundled: [Rule], learned: [LearnedRule]) {
        self.bundled = bundled
        self.learned = learned
    }

    public static func loadBundledRules() throws -> [Rule] {
        guard let url = Bundle.module.url(forResource: "rules", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Rule].self, from: Data(contentsOf: url))
    }

    public func classify(path: String, modifiedAt: Date, now: Date = Date()) -> Classification? {
        for rule in bundled where ruleApplies(rule, path: path, modifiedAt: modifiedAt, now: now) {
            return Classification(category: rule.category, risk: rule.risk,
                                  context: rule.context, restoreNote: rule.restoreNote,
                                  provenance: .bundled(ruleID: rule.id))
        }
        for lr in learned where ruleApplies(lr.rule, path: path, modifiedAt: modifiedAt, now: now) {
            return Classification(category: lr.rule.category, risk: lr.rule.risk,
                                  context: lr.rule.context, restoreNote: lr.rule.restoreNote,
                                  provenance: .learned(ruleID: lr.id))
        }
        return nil
    }

    private func ruleApplies(_ rule: Rule, path: String, modifiedAt: Date, now: Date) -> Bool {
        guard Glob.matches(pattern: rule.pattern, path: path) else { return false }
        if let days = rule.stalenessDays {
            let age = now.timeIntervalSince(modifiedAt)
            guard age >= Double(days) * 86400 else { return false }
        }
        return true
    }
}
