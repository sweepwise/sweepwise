import SwiftUI

@main
struct CleaniumApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Cleanium", systemImage: "internaldrive") {
            MenuContentView().environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(state)
        }
    }
}
