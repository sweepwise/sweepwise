import Foundation
import SwiftUI
import Combine
import CleaniumCore

/// Thread-safe flag shared between the MainActor and the detached scan task
/// (used for both cancellation and pause). `MainActor.assumeIsolated` would trap
/// if called off the main actor, so this uses a lock instead of actor isolation.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    func clear() { lock.lock(); value = false; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// Lock-guarded throttle for scan progress. The Scanner fires its progress
/// callback per visited path (10⁵+ times) off the main actor; forwarding each
/// one would flood the MainActor. This decides whether a given progress event is
/// worth forwarding: yes when the candidate count changed, or ≥100ms elapsed.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSent = Date.distantPast
    private var lastCount = -1
    private let minInterval: TimeInterval = 0.1

    func shouldForward(candidatesFound: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if candidatesFound != lastCount || now.timeIntervalSince(lastSent) >= minInterval {
            lastSent = now
            lastCount = candidatesFound
            return true
        }
        return false
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var candidates: [Candidate] = []
    @Published var skipped: [String] = []
    @Published var selection: Set<String> = []
    @Published var isScanning = false
    @Published var isPaused = false
    @Published var isDeleting = false
    @Published var progressText = ""
    @Published var outcomes: [DeletionOutcome] = []
    @Published var pendingLearnable: [LearnedRule] = []
    @Published var showConsentSheet = false
    @Published var learnedLoadError: String?
    /// Built-in ruleset failed to load — scans would silently find almost nothing.
    @Published var ruleLoadError: String?
    /// A learned-rule save/delete the user asked for failed to persist.
    @Published var storeError: String?
    /// AI usage for the current/most recent scan.
    @Published var llmCalls = 0
    @Published var llmTokens = 0
    /// True when at least one AI call this scan didn't report usage (codex/gemini).
    @Published var llmTokensIncomplete = false

    let settings = SettingsStore()
    let learnedStore = LearnedRuleStore()

    private var cancelFlag = AtomicFlag()
    private var pauseFlag = AtomicFlag()
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
        // Also blocked while a deletion is in flight: its completion rewrites
        // outcomes/candidates and would race a fresh scan's state.
        guard !isScanning, !isDeleting else { return }
        isScanning = true
        isPaused = false
        let flag = AtomicFlag()
        cancelFlag = flag
        let pauseF = AtomicFlag()
        pauseFlag = pauseF
        candidates = []
        skipped = []
        selection = []
        outcomes = []
        llmClassified = [:]
        llmCalls = 0
        llmTokens = 0
        llmTokensIncomplete = false

        let learned = learnedStore.load()
        learnedLoadError = learnedStore.lastLoadError
        let bundled: [Rule]
        do {
            bundled = try RuleEngine.loadBundledRules()
            ruleLoadError = bundled.isEmpty
                ? "Built-in rules file is empty — scans will find almost nothing. Try reinstalling Cleanium."
                : nil
        } catch {
            bundled = []
            ruleLoadError = "Could not load built-in rules — scans will find almost nothing. Try reinstalling Cleanium."
        }
        let engine = RuleEngine(bundled: bundled, learned: learned,
                                downloadStalenessOverrideDays: settings.stalenessDays)
        let scanner = CleaniumCore.Scanner(
            engine: engine,
            minSizeBytes: Int64(settings.minSizeMB) * 1_000_000,
            llmMinSizeBytes: Int64(settings.llmMinSizeMB) * 1_000_000)
        let roots = settings.scanRoots
        let enabledCategories = settings.enabledCategories
        let llmEnabled = settings.llmEnabled
        let provider = settings.llmProvider
        let isCancelled: () -> Bool = { flag.isSet }
        let throttle = ProgressThrottle()

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = scanner.scan(roots: roots, progress: { progress in
                // Throttle: the callback fires per visited path off-main. Drop events
                // unless the candidate count changed or ≥100ms elapsed, and never
                // clobber the final text once this scan was cancelled.
                guard !flag.isSet, throttle.shouldForward(candidatesFound: progress.candidatesFound)
                else { return }
                Task { @MainActor [weak self] in
                    guard !flag.isSet else { return }
                    self?.progressText =
                        "\(progress.candidatesFound) found — \(progress.currentPath)"
                }
            }, onCandidate: { candidate in
                // Stream candidates into the UI as they are found, so the user can
                // pause the scan and act on what has been identified so far.
                guard !flag.isSet, enabledCategories.contains(candidate.classification.category)
                else { return }
                Task { @MainActor [weak self] in
                    guard !flag.isSet, let self else { return }
                    if !self.candidates.contains(where: { $0.path == candidate.path }) {
                        self.candidates.append(candidate)
                    }
                }
            }, isPaused: { pauseF.isSet }, isCancelled: isCancelled)

            var extra: [Candidate] = []
            var llmMap: [String: LLMExplanation] = [:]
            if llmEnabled,
               let (detected, binary) = LLMProvider.detectInstalled()
                   .first(where: { $0.0 == provider }) {
                let explainer = LLMExplainer(provider: detected, binaryPath: binary)
                for dir in result.unknownDirs {
                    while pauseF.isSet && !flag.isSet {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                    guard !isCancelled() else { break }
                    Task { @MainActor [weak self] in
                        guard !flag.isSet else { return }
                        self?.progressText = "Asking \(detected.rawValue) about \(dir.path)"
                    }
                    guard let reply = explainer.explain(path: dir.path, sizeBytes: dir.sizeBytes)
                    else { continue }
                    let e = reply.explanation
                    let usage = reply.usage
                    Task { @MainActor [weak self] in
                        guard !flag.isSet, let self else { return }
                        self.llmCalls += 1
                        if let usage {
                            self.llmTokens += usage.totalTokens
                        } else {
                            self.llmTokensIncomplete = true
                        }
                    }
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

            // Rule candidates were already streamed live (and some may have been
            // deleted mid-scan) — only append the LLM extras here, never reassign
            // the whole list, or deleted items would reappear.
            let extras = extra.filter { enabledCategories.contains($0.classification.category) }
            let skippedPaths = result.skipped
            let finalMap = llmMap
            await MainActor.run { [weak self] in
                guard let self else { return }
                // A cancelled scan must not overwrite newer state: a later scan may
                // already be running with a different flag. Return without applying.
                guard !flag.isSet else { return }
                for candidate in extras where !self.candidates.contains(where: { $0.path == candidate.path }) {
                    self.candidates.append(candidate)
                }
                self.skipped = skippedPaths
                self.llmClassified = finalMap
                self.progressText = "\(self.candidates.count) candidates"
                self.isScanning = false
                self.isPaused = false
            }
        }
    }

    func cancelScan() {
        cancelFlag.set()
        pauseFlag.clear()
        isScanning = false
        isPaused = false
        // Candidates streamed so far stay in the list — cancelling keeps partial results.
        progressText = "Cancelled — \(candidates.count) found"
    }

    func pauseScan() {
        guard isScanning else { return }
        pauseFlag.set()
        isPaused = true
        progressText = "Paused — \(candidates.count) found so far"
    }

    func resumeScan() {
        pauseFlag.clear()
        isPaused = false
    }

    func deleteSelected(permanentOverTwoGB: Bool) {
        guard !isDeleting else { return }
        isDeleting = true
        let items = candidates.filter { selection.contains($0.id) }
        let twoGB: Int64 = 2_000_000_000
        let bigPaths = items.filter { $0.sizeBytes > twoGB }.map(\.path)
        let normalPaths = items.filter { $0.sizeBytes <= twoGB }.map(\.path)
        let provider = settings.llmProvider.rawValue
        let classified = llmClassified

        // TrashService can walk huge trees; run it off the main actor so the menu
        // stays responsive, then apply results back on the main actor.
        Task.detached(priority: .userInitiated) { [weak self] in
            let service = TrashService()
            var results = service.trash(paths: normalPaths)
            results += permanentOverTwoGB
                ? service.permanentlyDelete(paths: bigPaths)
                : service.trash(paths: bigPaths)
            let finalResults = results

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.outcomes = finalResults

                let deletedPaths = Set(finalResults.filter(\.success).map(\.path))
                self.candidates.removeAll { deletedPaths.contains($0.path) }
                self.selection.subtract(deletedPaths)

                // Nominate learned rules for deleted LLM-classified items; the consent
                // sheet decides. Only nominate suggestions that actually relate to the
                // deleted path (Fix 7 — never trust a bare `*` or `~/Library/*`).
                self.pendingLearnable = deletedPaths.compactMap { path in
                    guard let e = classified[path], let suggested = e.suggestedRule,
                          suggested.isValid(forOriginPath: path) else { return nil }
                    let id = UUID().uuidString
                    let exact = suggested.kind == .exactPath
                    return LearnedRule(
                        id: id,
                        rule: Rule(id: id, pattern: suggested.pattern, category: e.category,
                                   risk: e.risk, context: e.context, restoreNote: e.restoreNote),
                        kind: suggested.kind, sourceProvider: provider,
                        learnedAt: Date(), originPath: path, verified: exact)
                }
                self.showConsentSheet = !self.pendingLearnable.isEmpty
                self.isDeleting = false
            }
        }
    }

    func saveLearned(_ approved: [LearnedRule]) {
        var failed = 0
        for rule in approved {
            do { try learnedStore.add(rule) } catch { failed += 1 }
        }
        storeError = failed > 0
            ? "Could not save \(failed) approved rule\(failed == 1 ? "" : "s") — disk write failed."
            : nil
        pendingLearnable = []
        showConsentSheet = false
    }
}
