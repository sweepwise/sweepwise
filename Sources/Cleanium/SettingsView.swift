import SwiftUI
import CleaniumCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            rulesTab.tabItem { Label("Rules", systemImage: "list.bullet") }
            aiTab.tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 520, height: 420)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section("Scan roots") {
                ForEach(state.settings.scanRoots, id: \.self) { root in
                    HStack {
                        Text(root).font(.caption)
                        Spacer()
                        Button("Remove") {
                            state.settings.scanRoots.removeAll { $0 == root }
                        }.font(.caption)
                    }
                }
                Button("Add Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url {
                        state.settings.scanRoots.append(url.path)
                    }
                }
            }
            Section("Thresholds") {
                Stepper("Minimum size to list: \(state.settings.minSizeMB) MB",
                        value: Binding(get: { state.settings.minSizeMB },
                                       set: { state.settings.minSizeMB = $0 }),
                        in: 1...5000, step: 50)
                Stepper("Downloads stale after: \(state.settings.stalenessDays) days",
                        value: Binding(get: { state.settings.stalenessDays },
                                       set: { state.settings.stalenessDays = $0 }),
                        in: 7...365, step: 7)
            }
            Section("Categories") {
                ForEach(Category.allCases, id: \.self) { cat in
                    Toggle(cat.rawValue, isOn: Binding(
                        get: { state.settings.enabledCategories.contains(cat) },
                        set: { on in
                            if on { state.settings.enabledCategories.insert(cat) }
                            else { state.settings.enabledCategories.remove(cat) }
                        }))
                    .toggleStyle(.switch)
                    .tint(.green)
                }
            }
        }.formStyle(.grouped)
    }

    private var rulesTab: some View {
        Form {
            if let err = state.learnedLoadError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
            if let err = state.storeError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
            Section("Learned rules") {
                let learned = state.learnedStore.load()
                if learned.isEmpty {
                    Text("None yet. Delete an AI-classified item and approve the rule.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(learned) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.rule.pattern).font(.system(.caption, design: .monospaced))
                            Text("\(rule.sourceProvider) · "
                                 + rule.learnedAt.formatted(date: .abbreviated, time: .omitted)
                                 + " · from \(rule.originPath)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Delete") {
                            do {
                                try state.learnedStore.remove(id: rule.id)
                                state.storeError = nil
                            } catch {
                                state.storeError = "Could not delete the rule — "
                                    + error.localizedDescription
                            }
                            state.objectWillChange.send()
                        }.font(.caption)
                    }
                }
            }
            Section("Built-in rules (read-only)") {
                let bundled = (try? RuleEngine.loadBundledRules()) ?? []
                Text("\(bundled.count) rules covering caches, dev artifacts, LLM models, "
                     + "app leftovers, downloads.").font(.caption)
            }
        }.formStyle(.grouped)
    }

    private var aiTab: some View {
        Form {
            let detected = Dictionary(uniqueKeysWithValues: LLMProvider.detectInstalled())
            Toggle("Explain unknown folders with AI",
                   isOn: Binding(get: { state.settings.llmEnabled },
                                 set: { state.settings.llmEnabled = $0 }))
                .toggleStyle(.switch)
                .tint(.green)
                .disabled(detected.isEmpty)
            if detected.isEmpty {
                Text("No supported CLI found. Install claude, codex, or gemini.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Provider", selection: Binding(get: { state.settings.llmProvider },
                                                   set: { state.settings.llmProvider = $0 })) {
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName
                         + (detected[provider].map { " — \($0)" } ?? " — not installed"))
                        .tag(provider)
                }
            }
            if state.settings.llmEnabled && detected[state.settings.llmProvider] == nil {
                Text("The \(state.settings.llmProvider.rawValue) CLI was not found — "
                     + "AI explanations will be skipped. Install it or pick another provider.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Stepper("Ask about folders over: \(state.settings.llmMinSizeMB) MB",
                    value: Binding(get: { state.settings.llmMinSizeMB },
                                   set: { state.settings.llmMinSizeMB = $0 }),
                    in: 100...5000, step: 100)
            Text("Uses your existing subscription via the local CLI. "
                 + "No API keys, no data sent by Cleanium itself.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}
