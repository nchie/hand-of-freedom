import AppKit
import SwiftUI

@main
struct HandOfFreedomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        let model = delegate.model
        MenuBarExtra {
            StatusMenu(model: model, showSettings: { [delegate] in delegate.settingsWindow.show() })
        } label: {
            StatusLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Welcome to Hand of Freedom", id: WelcomeView.windowID) {
            WelcomeView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.shouldShowWelcomeOnLaunch ? .presented : .suppressed)
    }
}

/// Owns the model so termination can stop the pipeline, turns SIGTERM into a normal quit, and opens
/// settings when the app is opened again while running: the way in when the menu bar icon is hidden.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    lazy var settingsWindow = SettingsWindow(model: model)
    private var signalSource: DispatchSourceSignal?

    /// Opening the app again shows exactly one window: whichever is already open, else the welcome window
    /// while setup is unfinished, else settings. `hasVisibleWindows` is not used: a menu bar app's own
    /// status item can count as a visible window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate()
        if let open = NSApp.windows.first(where: { $0.isVisible && Self.isWelcome($0) }) ?? settingsWindow.visibleWindow {
            open.makeKeyAndOrderFront(nil)
        } else if model.shouldShowWelcomeOnLaunch, let openWelcome = model.openWelcomeWindow {
            openWelcome()
        } else {
            settingsWindow.show()
        }
        return false
    }

    static func isWelcome(_ w: NSWindow) -> Bool {
        w.identifier?.rawValue.hasPrefix(WelcomeView.windowID) == true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        s.setEventHandler { NSApp.terminate(nil) }
        s.resume()
        signalSource = s
        model.syncHotKey()
        if AppModel.previewMode == "settings" { settingsWindow.show() }
        if ProcessInfo.processInfo.environment["HOF_PREVIEW_REOPEN"] != nil {
            // Layout testing: reopen twice, as a launch-time reopen followed by a user's would.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
                _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}
