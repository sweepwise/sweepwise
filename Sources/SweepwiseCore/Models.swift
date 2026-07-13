import Foundation

public enum Category: String, Codable, CaseIterable, Sendable {
    case cache, devArtifact, llmModel, appLeftover, trash, download, unknown
}

public enum Risk: String, Codable, CaseIterable, Sendable {
    case safe          // pure cache, regenerated automatically
    case rebuildable   // rebuilt by a command (pnpm install, cargo build)
    case redownload    // re-downloadable artifact (models, installers)
    case userData      // user-created data; deletion loses information
    case unknown
}

public enum PatternKind: String, Codable, Sendable { case exactPath, glob }

public struct Rule: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    /// Glob. Contains "/" -> matched against the full expanded path via fnmatch.
    /// No "/" -> matched against the last path component.
    public var pattern: String
    public var category: Category
    public var risk: Risk
    public var context: String
    public var restoreNote: String
    /// Only match when the item is older than this many days.
    public var stalenessDays: Int?

    public init(id: String, pattern: String, category: Category, risk: Risk,
                context: String, restoreNote: String, stalenessDays: Int? = nil) {
        self.id = id
        self.pattern = pattern
        self.category = category
        self.risk = risk
        self.context = context
        self.restoreNote = restoreNote
        self.stalenessDays = stalenessDays
    }
}

public struct SuggestedRule: Codable, Equatable, Sendable {
    public var pattern: String
    public var kind: PatternKind

    public init(pattern: String, kind: PatternKind) {
        self.pattern = pattern
        self.kind = kind
    }

    /// Guards against blindly trusting LLM-suggested rules before nominating them.
    /// A valid suggestion must actually relate to the path the user just deleted and
    /// must not be trivially broad (a bare `*`/`**`/`?` or a pattern whose expanded
    /// form has fewer than 2 path components of specificity, e.g. `~/Library/*`).
    /// For `.exactPath` the tilde-expanded pattern must equal the origin path exactly.
    public func isValid(forOriginPath originPath: String) -> Bool {
        let expanded = (pattern as NSString).expandingTildeInPath
        if kind == .exactPath {
            return expanded == originPath
        }
        // Reject patterns that are purely wildcard characters.
        let stripped = pattern.filter { !"*?/~".contains($0) }
        guard !stripped.isEmpty else { return false }
        // Count literal components of the raw pattern (a leading `~` carries no
        // specificity of its own). Require ≥2 so a broad `~/Library/*` — one literal
        // component, "Library" — can't be learned, while `~/Library/Caches/foo*` can.
        let literalComponents = pattern
            .split(separator: "/")
            .filter { comp in comp != "~" && !comp.contains(where: { "*?".contains($0) }) }
        guard literalComponents.count >= 2 else { return false }
        // The suggested glob must match the path it was derived from.
        return Glob.matches(pattern: pattern, path: originPath)
    }
}

public struct LearnedRule: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var rule: Rule
    public var kind: PatternKind
    public var sourceProvider: String
    public var learnedAt: Date
    public var originPath: String
    /// exactPath rules are verified; LLM-suggested globs are not.
    public var verified: Bool

    public init(id: String, rule: Rule, kind: PatternKind, sourceProvider: String,
                learnedAt: Date, originPath: String, verified: Bool) {
        self.id = id
        self.rule = rule
        self.kind = kind
        self.sourceProvider = sourceProvider
        self.learnedAt = learnedAt
        self.originPath = originPath
        self.verified = verified
    }
}

public enum Provenance: Equatable, Sendable {
    case bundled(ruleID: String)
    case learned(ruleID: String)
    case llm(provider: String)
}

public struct Classification: Equatable, Sendable {
    public var category: Category
    public var risk: Risk
    public var context: String
    public var restoreNote: String
    public var provenance: Provenance
    /// Present only when provenance is .llm — feeds the learning consent sheet.
    public var suggestedRule: SuggestedRule?

    public init(category: Category, risk: Risk, context: String, restoreNote: String,
                provenance: Provenance, suggestedRule: SuggestedRule? = nil) {
        self.category = category
        self.risk = risk
        self.context = context
        self.restoreNote = restoreNote
        self.provenance = provenance
        self.suggestedRule = suggestedRule
    }
}

public struct Candidate: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var sizeBytes: Int64
    public var modifiedAt: Date
    public var classification: Classification

    public init(path: String, sizeBytes: Int64, modifiedAt: Date,
                classification: Classification) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.classification = classification
    }
}
