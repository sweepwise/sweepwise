import Foundation

public enum Glob {
    /// Patterns containing "/" match the full path (after ~ expansion), with
    /// FNM_PATHNAME so `*` never crosses a `/` — `~/Library/Caches/*` means
    /// direct children only. Bare patterns match the last path component.
    public static func matches(pattern: String, path: String) -> Bool {
        if pattern.contains("/") {
            let expanded = (pattern as NSString).expandingTildeInPath
            return fnmatch(expanded, path, FNM_PATHNAME) == 0
        }
        let name = (path as NSString).lastPathComponent
        return fnmatch(pattern, name, 0) == 0
    }
}

public struct RuleEngine {
    public let bundled: [Rule]
    public let learned: [LearnedRule]
    /// When set, overrides the stalenessDays of download-category rules that define one.
    /// Wired from `settings.stalenessDays` so the Settings stepper actually takes effect.
    public let downloadStalenessOverrideDays: Int?

    public init(bundled: [Rule], learned: [LearnedRule],
                downloadStalenessOverrideDays: Int? = nil) {
        self.bundled = bundled
        self.learned = learned
        self.downloadStalenessOverrideDays = downloadStalenessOverrideDays
    }

    public static func loadBundledRules() throws -> [Rule] {
        // Packaged .app: rules.json is copied to Contents/Resources by scripts/bundle.sh,
        // which Bundle.main resolves directly. Only fall back to Bundle.module (SwiftPM's
        // resource bundle) for `swift test`/`swift run`, where Bundle.main is the test
        // runner / dev binary and has no rules.json of its own.
        let url = Bundle.main.url(forResource: "rules", withExtension: "json")
            ?? Bundle.module.url(forResource: "rules", withExtension: "json")
        guard let url else {
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
        for lr in learned where learnedApplies(lr, path: path, modifiedAt: modifiedAt, now: now) {
            return Classification(category: lr.rule.category, risk: lr.rule.risk,
                                  context: lr.rule.context, restoreNote: lr.rule.restoreNote,
                                  provenance: .learned(ruleID: lr.id))
        }
        return nil
    }

    /// exactPath learned rules match by string equality (tilde-expanded), never
    /// fnmatch — real paths can contain glob metacharacters ("Adobe [2024]").
    private func learnedApplies(_ lr: LearnedRule, path: String,
                                modifiedAt: Date, now: Date) -> Bool {
        if lr.kind == .exactPath {
            guard (lr.rule.pattern as NSString).expandingTildeInPath == path else { return false }
            return stalenessSatisfied(lr.rule, modifiedAt: modifiedAt, now: now)
        }
        return ruleApplies(lr.rule, path: path, modifiedAt: modifiedAt, now: now)
    }

    private func ruleApplies(_ rule: Rule, path: String, modifiedAt: Date, now: Date) -> Bool {
        guard Glob.matches(pattern: rule.pattern, path: path) else { return false }
        return stalenessSatisfied(rule, modifiedAt: modifiedAt, now: now)
    }

    private func stalenessSatisfied(_ rule: Rule, modifiedAt: Date, now: Date) -> Bool {
        if let ruleDays = rule.stalenessDays {
            // Only download rules with an explicit stalenessDays honor the user override.
            let days = (rule.category == .download ? downloadStalenessOverrideDays : nil) ?? ruleDays
            let age = now.timeIntervalSince(modifiedAt)
            guard age >= Double(days) * 86400 else { return false }
        }
        return true
    }
}
