import Foundation
import Combine

public final class SettingsStore: ObservableObject {
    public static var defaultRoots: [String] {
        let home = NSHomeDirectory()
        return [
            home + "/Library/Caches",
            home + "/Library/Application Support",
            home + "/Library/Developer",
            home + "/Documents/Dev",
            home + "/Downloads",
            home + "/.cache",
        ]
    }

    @Published public var scanRoots: [String] { didSet { save() } }
    @Published public var enabledCategories: Set<Category> { didSet { save() } }
    @Published public var stalenessDays: Int { didSet { save() } }
    @Published public var minSizeMB: Int { didSet { save() } }
    @Published public var llmEnabled: Bool { didSet { save() } }
    @Published public var llmProvider: LLMProvider { didSet { save() } }
    @Published public var llmMinSizeMB: Int { didSet { save() } }
    /// Built-in rule ids the user has switched off; they are skipped during scans.
    @Published public var disabledRuleIDs: Set<String> { didSet { save() } }

    private let defaults: UserDefaults
    private var loading = true

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scanRoots = defaults.stringArray(forKey: "sweepwise.scanRoots") ?? Self.defaultRoots
        if let raw = defaults.stringArray(forKey: "sweepwise.enabledCategories") {
            enabledCategories = Set(raw.compactMap(Category.init(rawValue:)))
        } else {
            enabledCategories = Set(Category.allCases)
        }
        stalenessDays = defaults.object(forKey: "sweepwise.stalenessDays") as? Int ?? 60
        minSizeMB = defaults.object(forKey: "sweepwise.minSizeMB") as? Int ?? 50
        llmEnabled = defaults.bool(forKey: "sweepwise.llmEnabled")
        llmProvider = LLMProvider(rawValue:
            defaults.string(forKey: "sweepwise.llmProvider") ?? "") ?? .claude
        llmMinSizeMB = defaults.object(forKey: "sweepwise.llmMinSizeMB") as? Int ?? 500
        disabledRuleIDs = Set(defaults.stringArray(forKey: "sweepwise.disabledRuleIDs") ?? [])
        loading = false
    }

    private func save() {
        guard !loading else { return }
        defaults.set(scanRoots, forKey: "sweepwise.scanRoots")
        defaults.set(enabledCategories.map(\.rawValue).sorted(),
                     forKey: "sweepwise.enabledCategories")
        defaults.set(stalenessDays, forKey: "sweepwise.stalenessDays")
        defaults.set(minSizeMB, forKey: "sweepwise.minSizeMB")
        defaults.set(llmEnabled, forKey: "sweepwise.llmEnabled")
        defaults.set(llmProvider.rawValue, forKey: "sweepwise.llmProvider")
        defaults.set(llmMinSizeMB, forKey: "sweepwise.llmMinSizeMB")
        defaults.set(disabledRuleIDs.sorted(), forKey: "sweepwise.disabledRuleIDs")
    }
}
