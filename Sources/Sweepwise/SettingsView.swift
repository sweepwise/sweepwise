import SwiftUI
import SweepwiseCore

// The container observes nothing: if it watched AppState, every scan-progress
// publish (~10/sec) would rebuild the TabView and make the tab icons flicker.
// Each tab observes AppState itself, so re-renders stay inside the tab content.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            RulesTab().tabItem { Label("Rules", systemImage: "list.bullet") }
            AITab().tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 520, height: 420)
        .padding()
        .background(VisualEffectBackground().ignoresSafeArea())
    }
}

private struct GeneralTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
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
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                }
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden)
    }
}

private struct RulesTab: View {
    @EnvironmentObject var state: AppState

    @State private var bundled: [Rule] = []

    var body: some View {
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
            Section("Built-in rules") {
                Text("These ship with Sweepwise. Switch one off to stop it matching "
                     + "during scans — nothing is deleted, and you can switch it back on.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(bundled) { rule in
                    BuiltInRuleRow(rule: rule)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // Loaded once here, not in each row's body — the rules file never changes at runtime.
        .onAppear { bundled = (try? RuleEngine.loadBundledRules()) ?? [] }
    }
}

private struct BuiltInRuleRow: View {
    @EnvironmentObject var state: AppState
    let rule: Rule

    var body: some View {
        let enabled = !state.settings.disabledRuleIDs.contains(rule.id)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.pattern).font(.system(.caption, design: .monospaced)).bold()
                    Text(rule.category.rawValue)
                        .font(.caption2).padding(.horizontal, 4)
                        .background(.quaternary, in: Capsule())
                }
                Text(rule.context).font(.caption).foregroundStyle(.secondary)
                Text(rule.risk.label).font(.caption2).foregroundStyle(rule.risk.color)
                Text("If you need it back: \(rule.restoreNote)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !state.settings.disabledRuleIDs.contains(rule.id) },
                set: { on in
                    if on { state.settings.disabledRuleIDs.remove(rule.id) }
                    else { state.settings.disabledRuleIDs.insert(rule.id) }
                }))
                .labelsHidden().toggleStyle(SwitchToggleStyle(tint: .green))
        }
        .opacity(enabled ? 1 : 0.45)
    }
}

private struct AITab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let detected = Dictionary(uniqueKeysWithValues: LLMProvider.detectInstalled())
        let selected = state.settings.llmProvider
        let selectedMissing = detected[selected] == nil
        return Form {
            Section {
                Toggle("Explain unknown folders with AI",
                       isOn: Binding(get: { state.settings.llmEnabled },
                                     set: { state.settings.llmEnabled = $0 }))
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .disabled(detected.isEmpty)
                Picker("Provider", selection: Binding(get: { state.settings.llmProvider },
                                                       set: { state.settings.llmProvider = $0 })) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName
                             + (detected[provider] != nil ? " — installed" : " — not installed"))
                            .tag(provider)
                    }
                }
                if selectedMissing {
                    calloutMissing(selected)
                }
                Stepper("Ask about folders over: \(state.settings.llmMinSizeMB) MB",
                        value: Binding(get: { state.settings.llmMinSizeMB },
                                       set: { state.settings.llmMinSizeMB = $0 }),
                        in: 100...5000, step: 100)
            }

            Section("Setting up a provider") {
                Text("Sweepwise runs your own installed CLI — no API keys, and it uses the "
                     + "subscription you already pay for. Install one, sign in once by running "
                     + "it in Terminal, then pick it above.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    providerSetupRow(provider, installed: detected[provider] != nil)
                }
                Text("Sweepwise looks for the CLI in /opt/homebrew/bin, /usr/local/bin, "
                     + "~/.local/bin, ~/bin, and ~/.bun/bin. If yours lives elsewhere, symlink "
                     + "it into one of those folders.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden)
    }

    /// High-contrast warning: filled amber card, not thin orange text on frost.
    private func calloutMissing(_ provider: LLMProvider) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("The \(provider.rawValue) CLI isn't installed")
                    .font(.callout).fontWeight(.semibold)
                Text("AI explanations will be skipped. Install it below, or pick a provider "
                     + "that's already installed.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Set up \(provider.rawValue) →", destination: provider.setupURL)
                    .font(.caption).fontWeight(.medium)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.35)))
    }

    private func providerSetupRow(_ provider: LLMProvider, installed: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: installed ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(installed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName).font(.callout)
                if installed {
                    Text("Installed and ready").font(.caption2).foregroundStyle(.green)
                } else {
                    Text(provider.installHint)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer()
            Link("Guide", destination: provider.setupURL).font(.caption)
        }
    }
}
