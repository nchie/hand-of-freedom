import Runtime
import SwiftUI

struct StatusMenu: View {
    let model: AppModel
    let showSettings: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let p = model.presentation
        Text(p.headline)
        if let error = model.startError { Text(error) }
        if p.needsAttention {
            Button("Fix…") { showWelcome() }
        }
        Divider()
        Toggle("Enabled", isOn: model.binding(\.enabled))
        Toggle("Act in All Apps", isOn: model.binding(\.actInAllApps))
        Toggle("Launch at Login", isOn: Binding(get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                                                set: { model.setLaunchAtLogin($0) }))
        if model.settings.diagnostics.recordForBugReports {
            Divider()
            Button("Save Last \(model.settings.diagnostics.rollingSeconds) Seconds   \(HotKey.saveClip.label)") { model.saveClip() }
            Button(model.isRecordingSession ? "Stop Recording Session" : "Record Session") { model.toggleSession() }
            Button("Show Clips in Finder") { model.showClipsInFinder() }
            if let message = model.lastClipMessage { Text(message) }
        }
        Divider()
        Button("Welcome and Permissions…") { showWelcome() }
        Button("Settings…") { showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Hand of Freedom") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showWelcome() {
        openWindow(id: WelcomeView.windowID)
        NSApp.activate()
    }
}

/// The menu bar icon. Also captures the window-opening action at launch, so the app delegate can open
/// the welcome window when the app is reopened.
struct StatusLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let p = model.presentation
        Image(systemName: p.symbol.rawValue)
            .opacity(p.dimmed ? 0.5 : 1)
            .accessibilityLabel("Hand of Freedom: \(p.headline)")
            .onAppear { capture() }
    }

    private func capture() {
        let open = openWindow
        model.openWelcomeWindow = { open(id: WelcomeView.windowID); NSApp.activate() }
    }
}
