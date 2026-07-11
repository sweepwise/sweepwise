import Foundation

public final class LearnedRuleStore {
    public let fileURL: URL
    public private(set) var lastLoadError: String?

    public convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("Cleanium")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.init(fileURL: base.appendingPathComponent("learned-rules.json"))
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> [LearnedRule] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([LearnedRule].self, from: data)
        } catch {
            // Corrupt file: move aside so the app keeps working; surface in Settings.
            let aside = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            lastLoadError = "learned-rules.json was corrupt; moved to \(aside.lastPathComponent)"
            return []
        }
    }

    public func add(_ rule: LearnedRule) throws {
        var rules = load()
        guard !rules.contains(where: { $0.rule.pattern == rule.rule.pattern }) else { return }
        rules.append(rule)
        try save(rules)
    }

    public func remove(id: String) throws {
        try save(load().filter { $0.id != id })
    }

    public func update(_ rule: LearnedRule) throws {
        var rules = load()
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i] = rule
        try save(rules)
    }

    private func save(_ rules: [LearnedRule]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rules).write(to: fileURL, options: .atomic)
    }
}
