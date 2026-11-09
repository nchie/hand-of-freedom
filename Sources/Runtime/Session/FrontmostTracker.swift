import AppKit

/// Follows the frontmost application. Notifications plus a slow poll, because a command-line process
/// does not always receive workspace notifications.
@MainActor
public final class FrontmostTracker {
    public private(set) var bundleID: String?
    public var onChange: ((String?) -> Void)?
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    public init() {
        bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.update(id) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            MainActor.assumeIsolated { self?.update(id) }
        }
    }

    private func update(_ id: String?) {
        guard id != bundleID else { return }
        bundleID = id
        onChange?(id)
    }
}
