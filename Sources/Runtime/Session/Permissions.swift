import ApplicationServices
import CoreGraphics
import Foundation

public enum PermissionState: String, Sendable, Equatable {
    case granted, denied
}

/// The privacy grants the tool can use. Measured on macOS 26:
/// Accessibility is the only one the tool needs.
public enum Permission: String, Sendable, CaseIterable {
    /// Accessibility: AXIsProcessTrusted. Without it IOHIDPostEvent output is silently dropped (return
    /// code 0) and the scroll-swallowing HID tap cannot be created.
    case accessibility
    /// Input Monitoring: CGPreflightListenEventAccess. Only listen-only taps need it, so only the
    /// injector probe's echo. Optional.
    case inputMonitoring
    /// Posting events: CGPreflightPostEventAccess. Tracks Accessibility exactly.
    case postEvents
}

public struct PermissionSnapshot: Sendable, Equatable {
    public var accessibility: PermissionState
    public var inputMonitoring: PermissionState
    public var postEvents: PermissionState

    public init(accessibility: PermissionState, inputMonitoring: PermissionState, postEvents: PermissionState) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.postEvents = postEvents
    }

    public static let allGranted = PermissionSnapshot(accessibility: .granted, inputMonitoring: .granted, postEvents: .granted)

    public subscript(_ p: Permission) -> PermissionState {
        switch p {
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        case .postEvents: postEvents
        }
    }

    public var missing: [Permission] { Permission.allCases.filter { self[$0] != .granted } }
}

/// The system calls behind a snapshot, behind a seam so the controller can be tested.
public protocol PermissionChecks: Sendable {
    func snapshot() -> PermissionSnapshot
    /// Shows the system prompts for whatever is missing and adds the app to the lists in System Settings.
    func request(_ permissions: [Permission])
    /// Screen Recording: CGPreflightScreenCaptureAccess. Only automatic scrolling over game windows
    /// needs it, so it is not part of the snapshot that gates acting.
    func screenRecording() -> PermissionState
    /// Shows the system prompt the first time; after that the user allows it in System Settings.
    func requestScreenRecording()
}

public struct SystemPermissionChecks: PermissionChecks {
    public init() {}

    public func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(accessibility: AXIsProcessTrusted() ? .granted : .denied,
                           inputMonitoring: CGPreflightListenEventAccess() ? .granted : .denied,
                           postEvents: CGPreflightPostEventAccess() ? .granted : .denied)
    }

    public func screenRecording() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    public func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    public func request(_ permissions: [Permission]) {
        for p in permissions {
            switch p {
            case .accessibility:
                let key = "AXTrustedCheckOptionPrompt" as CFString   // kAXTrustedCheckOptionPrompt
                _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            case .inputMonitoring:
                _ = CGRequestListenEventAccess()
            case .postEvents:
                _ = CGRequestPostEventAccess()
            }
        }
    }
}

/// The ground truth for permissions. Each preflight is an XPC round trip to tccd, so it polls only
/// while something is missing, and otherwise relies on `refresh()` calls from fault signals and on
/// the system's accessibility-change notification.
@MainActor
public final class PermissionsMonitor {
    public private(set) var snapshot: PermissionSnapshot
    public var onChange: ((PermissionSnapshot) -> Void)?
    private let checks: any PermissionChecks
    private let pollInterval: TimeInterval
    private let watching: [Permission]
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    /// Polls while any of `watching` is missing; the optional grants never keep it polling.
    public init(checks: any PermissionChecks = SystemPermissionChecks(), pollInterval: TimeInterval = 2,
                watching: [Permission] = [.accessibility]) {
        self.checks = checks
        self.pollInterval = pollInterval
        self.watching = watching
        snapshot = checks.snapshot()
    }

    public func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The notification can arrive before tccd has the new value.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { self?.refresh() } }
        }
        refresh()
    }

    public func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        let new = checks.snapshot()
        let changed = new != snapshot
        snapshot = new
        updatePolling()
        if changed { onChange?(new) }
    }

    public func request(_ permissions: [Permission]) {
        checks.request(permissions)
        refresh()
    }

    private func updatePolling() {
        let wanted = watching.contains { snapshot[$0] != .granted }
        if wanted, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        } else if !wanted, let t = timer {
            t.invalidate()
            timer = nil
        }
    }
}
