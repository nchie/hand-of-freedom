import AppKit
import SwiftUI

/// The settings window, owned by the app delegate so it can open from anywhere: the menu, and a reopen
/// of the app while the menu bar icon is hidden (for example under the notch).
final class SettingsWindow {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    var visibleWindow: NSWindow? { window?.isVisible == true ? window : nil }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            // No content-driven sizing: the forms take the height they are offered, so letting them size
            // the window loops until AppKit aborts. The window has a fixed starting size; the forms scroll.
            host.sizingOptions = []
            let w = NSWindow(contentViewController: host)
            w.title = "Hand of Freedom Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 480, height: 420)
            w.setContentSize(NSSize(width: 540, height: 640))
            w.center()
            w.setFrameAutosaveName("settings-window")   // not "settings": that name holds a size saved by a crashing build
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
