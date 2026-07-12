import SwiftUI
import CleaniumCore

struct MenuContentView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmDelete = false

    // The consent view renders inline instead of via .sheet: window-based
    // presentations from a MenuBarExtra popover shift key focus, which breaks
    // their hit-testing and can dismiss the popover (same issue as the old
    // delete confirmationDialog).
    var body: some View {
        Group {
            if state.showConsentSheet {
                ConsentSheetView()
            } else {
                mainContent
            }
        }
        .frame(width: 460, height: 560, alignment: .top)
        // Same translucency mechanism as the Settings window: our own effect
        // view in a cleared borderless panel.
        .background(VisualEffectBackground().ignoresSafeArea())
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if state.candidates.isEmpty && !state.isScanning {
                Text("No results yet. Run a scan.")
                    .foregroundStyle(.secondary).padding(.vertical, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsList
            }
            failureBanner
            Divider()
            footer
        }
        .padding(12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Cleanium").font(.headline)
                Spacer()
                diskGauge
                SettingsLink { Image(systemName: "gearshape") }
                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .help("Quit Cleanium")
                .keyboardShortcut("q")
            }
            HStack {
                Button(state.isScanning ? "Scanning…" : "Scan") { state.startScan() }
                    .disabled(state.isScanning || state.isDeleting)
                if state.isScanning {
                    Button(state.isPaused ? "Resume" : "Pause") {
                        state.isPaused ? state.resumeScan() : state.pauseScan()
                    }
                    Button("Cancel") { state.cancelScan() }
                }
                Spacer()
                if !state.skipped.isEmpty {
                    Text("\(state.skipped.count) skipped")
                        .font(.caption).foregroundStyle(.orange)
                        .help("Some paths were unreadable. Grant Full Disk Access in "
                              + "System Settings → Privacy & Security if needed.")
                }
            }
            if !state.progressText.isEmpty {
                Text(state.progressText).font(.caption2)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if state.llmCalls > 0 {
                Text(aiUsageText)
                    .font(.caption2).foregroundStyle(.secondary)
                    .help("Cached input tokens are served from the provider's prompt cache "
                          + "at ~10% of the price of fresh input. Folders are classified in "
                          + "batches to pay the CLI's fixed prompt overhead once per batch.")
            }
            if let err = state.ruleLoadError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if let err = state.storeError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var aiUsageText: String {
        let calls = "AI this scan: \(state.llmCalls) call" + (state.llmCalls == 1 ? "" : "s")
        var text = calls
        text += " · in " + state.llmInputTokens.formatted()
        text += " (+" + state.llmCachedTokens.formatted() + " cached)"
        text += " · out " + state.llmOutputTokens.formatted()
        if state.llmTokensIncomplete {
            text += " · some calls did not report usage"
        }
        return text
    }

    private var diskGauge: some View {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                      .volumeTotalCapacityKey])
        let free = Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = Int64(values?.volumeTotalCapacity ?? 1)
        return Text("\(Fmt.bytes(free)) free of \(Fmt.bytes(total))")
            .font(.caption).foregroundStyle(free < total / 10 ? .red : .secondary)
    }

    private var resultsList: some View {
        List {
            ForEach(state.groupedCandidates, id: \.0) { risk, items in
                Section {
                    ForEach(items) { CandidateRow(candidate: $0) }
                } header: {
                    HStack {
                        Text(risk.badge)
                            .font(.caption).bold().foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(risk.color, in: Capsule())
                        Text(risk.label).foregroundStyle(risk.color)
                        Spacer()
                        Button("All") {
                            state.selection.formUnion(items.map(\.id))
                        }.font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    /// Surfaces per-item trash failures after a deletion (Fix 3). Cleared when the
    /// next scan resets `outcomes`, or a delete that fully succeeds.
    @ViewBuilder private var failureBanner: some View {
        let failures = state.outcomes.filter { !$0.success }
        if !failures.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(failures.count) item\(failures.count == 1 ? "" : "s") could not be moved to Trash")
                    .font(.caption).bold().foregroundStyle(.red)
                ForEach(failures.prefix(3), id: \.path) { outcome in
                    Text("• \((outcome.path as NSString).lastPathComponent): "
                         + (outcome.error ?? "unknown error"))
                        .font(.caption2).foregroundStyle(.red)
                        .lineLimit(1).truncationMode(.middle)
                }
                if failures.count > 3 {
                    Text("…and \(failures.count - 3) more")
                        .font(.caption2).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // Confirmation is rendered inline: presenting a dialog/alert from a MenuBarExtra
    // window shifts key focus, which auto-dismisses the transient popover and the
    // dialog along with it.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if confirmDelete && !state.selection.isEmpty {
                confirmStrip
            }
            HStack {
                Text("\(state.selection.count) selected — \(Fmt.bytes(state.selectedBytes))")
                    .font(.callout)
                Spacer()
                Button(state.isDeleting ? "Deleting…" : "Move to Trash") { confirmDelete = true }
                    .disabled(state.selection.isEmpty || state.isDeleting)
                    .keyboardShortcut(.delete)
            }
        }
    }

    private var confirmStrip: some View {
        let hasBig = state.candidates.contains {
            state.selection.contains($0.id) && $0.sizeBytes > 2_000_000_000
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Move \(state.selection.count) items (\(Fmt.bytes(state.selectedBytes))) to Trash?")
                .font(.callout).bold()
            if hasBig {
                Text("Items over 2 GB can fill the Trash; permanent delete frees space "
                     + "immediately but cannot be undone.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { confirmDelete = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if hasBig {
                    Button("Trash small + delete >2 GB", role: .destructive) {
                        confirmDelete = false
                        state.deleteSelected(permanentOverTwoGB: true)
                    }
                }
                Button("Move to Trash", role: .destructive) {
                    confirmDelete = false
                    state.deleteSelected(permanentOverTwoGB: false)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Behind-window vibrancy for the popover — the translucent "skin" a plain
/// MenuBarExtra window doesn't get by default. The hosting window is opaque,
/// which leaves a behind-window blur nothing to sample, so this view also
/// clears the window's backing whenever it lands in one.
private final class TransparentWindowEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        // Run the blur under the titlebar too — otherwise the top strip stays
        // an opaque white band above translucent content.
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = TransparentWindowEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct CandidateRow: View {
    @EnvironmentObject var state: AppState
    let candidate: Candidate
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { state.selection.contains(candidate.id) },
                    set: { on in
                        if on { state.selection.insert(candidate.id) }
                        else { state.selection.remove(candidate.id) }
                    })).labelsHidden()
                Text((candidate.path as NSString).lastPathComponent).bold()
                Text(candidate.classification.category.rawValue)
                    .font(.caption2).padding(.horizontal, 4)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(Fmt.bytes(candidate.sizeBytes)).monospacedDigit()
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }.buttonStyle(.plain)
            }
            // Always-visible path — the fastest way to scan the list.
            Text((candidate.path as NSString).abbreviatingWithTildeInPath)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
                .padding(.leading, 24)
            // Always-visible one-line plain-English explanation.
            Text(candidate.classification.context)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 1)
                .padding(.leading, 24)
            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    Label {
                        Text(candidate.classification.risk.label)
                            .foregroundStyle(candidate.classification.risk.color)
                    } icon: {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundStyle(candidate.classification.risk.color)
                    }
                    Label {
                        Text("If you need it back: \(candidate.classification.restoreNote)")
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    Label {
                        Text("Identified by \(candidate.classification.provenance.label)")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "magnifyingglass.circle")
                            .foregroundStyle(.secondary)
                    }
                    Text(candidate.path)
                        .font(.caption2).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .padding(.leading, 24)
            }
        }
    }
}
