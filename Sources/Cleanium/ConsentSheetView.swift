import SwiftUI
import CleaniumCore

struct ConsentSheetView: View {
    @EnvironmentObject var state: AppState
    @State private var approved: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Save rules for next time?").font(.headline)
            Text("These AI classifications matched what you just deleted. Saved rules "
                 + "classify the same folders instantly on future scans. Nothing is saved "
                 + "without your approval — you will be asked every time.")
                .font(.caption).foregroundStyle(.secondary)
            List(state.pendingLearnable) { rule in
                HStack(alignment: .top) {
                    Toggle("", isOn: Binding(
                        get: { approved.contains(rule.id) },
                        set: { on in
                            if on { approved.insert(rule.id) }
                            else { approved.remove(rule.id) }
                        })).labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.rule.pattern).font(.system(.body, design: .monospaced))
                        Text("\(rule.rule.category.rawValue) · \(rule.rule.risk.rawValue)"
                             + " · from \(rule.sourceProvider)"
                             + (rule.verified ? "" : " · glob (unverified)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Skip") { state.saveLearned([]) }
                Button("Save Selected") {
                    state.saveLearned(state.pendingLearnable.filter { approved.contains($0.id) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(approved.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440, height: 320)
        .onAppear { approved = Set(state.pendingLearnable.map(\.id)) }
    }
}
