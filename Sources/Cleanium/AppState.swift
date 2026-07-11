import Foundation
import SwiftUI
import Combine
import CleaniumCore

/// Thread-safe cancellation flag. `startScan()` creates one per scan and reads it
/// from a detached background task; `MainActor.assumeIsolated` would trap if called
/// off the main actor, so this uses a lock instead of actor isolation.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
final class AppState: ObservableObject {
    @Published var candidates: [Candidate] = []
    @Published var skipped: [String] = []
    @Published var selection: Set<String> = []
    @Published var isScanning = false
    @Published var progressText = ""
    @Published var outcomes: [DeletionOutcome] = []
    @Published var pendingLearnable: [LearnedRule] = []
    @Published var showConsentSheet = false
    @Published var learnedLoadError: String?

    let settings = SettingsStore()
    let learnedStore = LearnedRuleStore()

    private var cancelFlag = CancelFlag()
    /// LLM classifications made this session, keyed by path — used to nominate
    /// learned rules when the user deletes those items.
    private var llmClassified: [String: LLMExplanation] = [:]
    private var cancellables: Set<AnyCancellable> = []

    static let riskOrder: [Risk] = [.safe, .rebuildable, .redownload, .userData, .unknown]

    init() {
        // SettingsStore is a nested ObservableObject; forward its changes so views
        // observing AppState via @EnvironmentObject re-render on settings mutations.
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var groupedCandidates: [(Risk, [Candidate])] {
        Self.riskOrder.compactMap { risk in
            let items = candidates
                .filter { $0.classification.risk == risk }
                .sorted { $0.sizeBytes > $1.sizeBytes }
            return items.isEmpty ? nil : (risk, items)
        }
    }

    var selectedBytes: Int64 {
        candidates.filter { selection.contains($0.id) }.map(\.sizeBytes).reduce(0, +)
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        let flag = CancelFlag()
        cancelFlag = flag
        candidates = []
        skipped = []
        selection = []
        outcomes = []
        llmClassified = [:]

        let learned = learnedStore.load()
        learnedLoadError = learnedStore.lastLoadError
        let bundled = (try? RuleEngine.loadBundledRules()) ?? []
        let engine = RuleEngine(bundled: bundled, learned: learned)
        let scanner = CleaniumCore.Scanner(
            engine: engine,
            minSizeBytes: Int64(settings.minSizeMB) * 1_000_000,
            llmMinSizeBytes: Int64(settings.llmMinSizeMB) * 1_000_000)
        let roots = settings.scanRoots
        let enabledCategories = settings.enabledCategories
        let llmEnabled = settings.llmEnabled
        let provider = settings.llmProvider
        let isCancelled: () -> Bool = { flag.isSet }

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = scanner.scan(roots: roots, progress: { progress in
                Task { @MainActor [weak self] in
                    self?.progressText =
                        "\(progress.candidatesFound) found — \(progress.currentPath)"
                }
            }, isCancelled: isCancelled)

            var extra: [Candidate] = []
            var llmMap: [String: LLMExplanation] = [:]
            if llmEnabled,
               let (detected, binary) = LLMProvider.detectInstalled()
                   .first(where: { $0.0 == provider }) {
                let explainer = LLMExplainer(provider: detected, binaryPath: binary)
                for dir in result.unknownDirs {
                    guard !isCancelled() else { break }
                    Task { @MainActor [weak self] in
                        self?.progressText = "Asking \(detected.rawValue) about \(dir.path)"
                    }
                    guard let e = explainer.explain(path: dir.path, sizeBytes: dir.sizeBytes)
                    else { continue }
                    llmMap[dir.path] = e
                    extra.append(Candidate(
                        path: dir.path, sizeBytes: dir.sizeBytes, modifiedAt: dir.modifiedAt,
                        classification: Classification(
                            category: e.category, risk: e.risk, context: e.context,
                            restoreNote: e.restoreNote,
                            provenance: .llm(provider: detected.rawValue),
                            suggestedRule: e.suggestedRule)))
                }
            }

            let all = (result.candidates + extra)
                .filter { enabledCategories.contains($0.classification.category) }
            let skippedPaths = result.skipped
            let finalMap = llmMap
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.candidates = all
                self.skipped = skippedPaths
                self.llmClassified = finalMap
                self.progressText = "\(all.count) candidates"
                self.isScanning = false
            }
        }
    }

    func cancelScan() {
        cancelFlag.set()
        isScanning = false
        progressText = "Cancelled"
    }

    func deleteSelected(permanentOverTwoGB: Bool) {
        let items = candidates.filter { selection.contains($0.id) }
        let service = TrashService()
        let twoGB: Int64 = 2_000_000_000
        let (bigItems, normalItems) = (items.filter { $0.sizeBytes > twoGB },
                                       items.filter { $0.sizeBytes <= twoGB })
        var results = service.trash(paths: normalItems.map(\.path))
        results += permanentOverTwoGB
            ? service.permanentlyDelete(paths: bigItems.map(\.path))
            : service.trash(paths: bigItems.map(\.path))
        outcomes = results

        let deletedPaths = Set(results.filter(\.success).map(\.path))
        candidates.removeAll { deletedPaths.contains($0.path) }
        selection.subtract(deletedPaths)

        // Nominate learned rules for deleted LLM-classified items; consent sheet decides.
        pendingLearnable = deletedPaths.compactMap { path in
            guard let e = llmClassified[path], let suggested = e.suggestedRule else { return nil }
            let id = UUID().uuidString
            let exact = suggested.kind == .exactPath
            return LearnedRule(
                id: id,
                rule: Rule(id: id, pattern: suggested.pattern, category: e.category,
                           risk: e.risk, context: e.context, restoreNote: e.restoreNote),
                kind: suggested.kind, sourceProvider: settings.llmProvider.rawValue,
                learnedAt: Date(), originPath: path, verified: exact)
        }
        showConsentSheet = !pendingLearnable.isEmpty
    }

    func saveLearned(_ approved: [LearnedRule]) {
        for rule in approved {
            try? learnedStore.add(rule)
        }
        pendingLearnable = []
        showConsentSheet = false
    }
}
