import SwiftUI
import AppKit

/// Menu bar presence via NSStatusItem + a borderless translucent panel.
/// NSPopover's frame material is private and can't be thinned reliably, so the
/// dropdown uses the same VisualEffectBackground mechanism as the Settings
/// window — one look, one knob.
@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "internaldrive",
                                     accessibilityDescription: "Cleanium")
        item.button?.action = #selector(toggleDropdown)
        item.button?.target = self
        statusItem = item
    }

    @objc private func toggleDropdown() {
        if let panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    private func open() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionUnderStatusItem(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Transient behavior: any click outside the panel closes it.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        }
    }

    private func close() {
        panel?.orderOut(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: MenuContentView().environmentObject(state))
        return panel
    }

    private func positionUnderStatusItem(_ panel: NSPanel) {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let x = buttonFrame.midX - panel.frame.width / 2
        let y = buttonFrame.minY - 6
        // Keep the panel on-screen when the icon sits near the right edge.
        let screen = buttonWindow.screen?.visibleFrame ?? .zero
        let clampedX = min(max(x, screen.minX + 8), screen.maxX - panel.frame.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: clampedX, y: y))
    }
}

/// Borderless panels refuse key status by default; the dropdown needs it for
/// text fields, buttons, and Esc handling.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@main
struct CleaniumApp: App {
    @NSApplicationDelegateAdaptor(StatusBarController.self) private var statusBar

    var body: some Scene {
        Settings {
            SettingsView().environmentObject(statusBar.state)
        }
    }
}
