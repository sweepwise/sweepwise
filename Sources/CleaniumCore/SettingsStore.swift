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
            home + "/.Trash",
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

    private let defaults: UserDefaults
    private var loading = true

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scanRoots = defaults.stringArray(forKey: "cleanium.scanRoots") ?? Self.defaultRoots
        if let raw = defaults.stringArray(forKey: "cleanium.enabledCategories") {
            enabledCategories = Set(raw.compactMap(Category.init(rawValue:)))
        } else {
            enabledCategories = Set(Category.allCases)
        }
        stalenessDays = defaults.object(forKey: "cleanium.stalenessDays") as? Int ?? 60
        minSizeMB = defaults.object(forKey: "cleanium.minSizeMB") as? Int ?? 50
        llmEnabled = defaults.bool(forKey: "cleanium.llmEnabled")
        llmProvider = LLMProvider(rawValue:
            defaults.string(forKey: "cleanium.llmProvider") ?? "") ?? .claude
        llmMinSizeMB = defaults.object(forKey: "cleanium.llmMinSizeMB") as? Int ?? 500
        loading = false
    }

    private func save() {
        guard !loading else { return }
        defaults.set(scanRoots, forKey: "cleanium.scanRoots")
        defaults.set(enabledCategories.map(\.rawValue).sorted(),
                     forKey: "cleanium.enabledCategories")
        defaults.set(stalenessDays, forKey: "cleanium.stalenessDays")
        defaults.set(minSizeMB, forKey: "cleanium.minSizeMB")
        defaults.set(llmEnabled, forKey: "cleanium.llmEnabled")
        defaults.set(llmProvider.rawValue, forKey: "cleanium.llmProvider")
        defaults.set(llmMinSizeMB, forKey: "cleanium.llmMinSizeMB")
    }
}
