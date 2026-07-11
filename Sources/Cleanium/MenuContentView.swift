import SwiftUI
import CleaniumCore

struct MenuContentView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if state.candidates.isEmpty && !state.isScanning {
                Text("No results yet. Run a scan.")
                    .foregroundStyle(.secondary).padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                resultsList
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 460, height: 560)
        .sheet(isPresented: $state.showConsentSheet) {
            ConsentSheetView().environmentObject(state)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Cleanium").font(.headline)
                Spacer()
                diskGauge
                SettingsLink { Image(systemName: "gearshape") }
            }
            HStack {
                Button(state.isScanning ? "Scanning…" : "Scan") { state.startScan() }
                    .disabled(state.isScanning)
                if state.isScanning {
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
        }
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
                        Text("\(risk.badge) — \(risk.label)")
                        Spacer()
                        Button("All") {
                            state.selection.formUnion(items.map(\.id))
                        }.font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            Text("\(state.selection.count) selected — \(Fmt.bytes(state.selectedBytes))")
                .font(.callout)
            Spacer()
            Button("Move to Trash") { confirmDelete = true }
                .disabled(state.selection.isEmpty)
                .keyboardShortcut(.delete)
        }
        .confirmationDialog(
            "Move \(state.selection.count) items (\(Fmt.bytes(state.selectedBytes))) to Trash?",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                state.deleteSelected(permanentOverTwoGB: false)
            }
            if state.candidates.contains(where: {
                state.selection.contains($0.id) && $0.sizeBytes > 2_000_000_000 }) {
                Button("Trash small + permanently delete items over 2 GB",
                       role: .destructive) {
                    state.deleteSelected(permanentOverTwoGB: true)
                }
            }
        } message: {
            Text("Items over 2 GB can fill the Trash; permanent delete frees space "
                 + "immediately but cannot be undone.")
        }
    }
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
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.path).font(.caption).textSelection(.enabled)
                    Text(candidate.classification.context).font(.caption)
                    Text("Restore: \(candidate.classification.restoreNote)").font(.caption)
                    Text("Source: \(candidate.classification.provenance.label)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
            }
        }
    }
}
