import AppKit
import GestureCore
import Observation
import PlatformBackends
import Runtime
import SwiftUI

/// Runtime's settings value; SwiftUI has its own `Settings` scene.
typealias AppSettings = Runtime.Settings

/// The app's one model: owns the settings store and the pipeline controller, and funnels every
/// settings change through `update` so the controller always sees the saved value.
@Observable
final class AppModel {
    /// `HOF_UI_PREVIEW=welcome|settings`: windows only, for layout testing. Nothing is tracked or posted,
    /// and settings live in a temporary file.
    static let previewMode = ProcessInfo.processInfo.environment["HOF_UI_PREVIEW"]

    let store: SettingsStore
    private(set) var status = PipelineStatus()
    private(set) var phase: EngineState.Phase = .idle
    private(set) var startError: String?
    private(set) var loginStatus: LoginItem.Status = .notRegistered
    private(set) var loginError: String?
    /// The last clip save, for the menu and settings to show.
    private(set) var lastClipMessage: String?
    private(set) var isRecordingSession = false
    /// Set when the save shortcut could not be registered (another app holds it).
    private(set) var hotKeyProblem: String?
    /// The clip shortcut, registered only while recording for bug reports is on.
    @ObservationIgnored private var saveClipHotKey: HotKey?
    /// Whether the marker addon is in the game's AddOns folder. Refreshed when settings show and after installing.
    private(set) var addonState: AddonInstaller.State = .notInstalled
    private(set) var addonError: String?
    @ObservationIgnored private var controller: PipelineController?
    /// Opens the SwiftUI welcome window. Captured from a view, since only views can open scenes.
    @ObservationIgnored var openWelcomeWindow: (() -> Void)?

    init() {
        if Self.previewMode != nil {
            store = SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("hof-preview-settings.json"))
            loginStatus = .notRegistered
            // The first-run layout: nothing granted yet, so every row and button shows.
            status.permissions = PermissionSnapshot(accessibility: .denied, inputMonitoring: .denied, postEvents: .denied)
            status.blockers = [.missingPermission(.accessibility), .gateNotInstalled, .targetNotFrontmost]
            return
        }
        store = SettingsStore()
        do {
            let injector = IOHIDInjector()
            let core = try PipelineCore(config: store.settings.primaryProfile.engine, injector: injector)
            let tap = EventTap(flags: core.flags.activation) { [injector] identity in injector.isOwnEvent(identity) }
            let c = PipelineController(core: core, gate: tap, settings: store.settings)
            c.onStatusChange = { [weak self] in self?.status = $0 }
            c.onPhase = { [weak self] in self?.phase = $0 }
            try c.start()
            status = c.status
            controller = c
        } catch {
            startError = "The trackpad could not be opened: \(error)"
        }
        loginStatus = LoginItem.status
    }

    var settings: AppSettings { store.settings }

    func update(_ mutate: (inout AppSettings) -> Void) {
        guard store.update(mutate) else { return }
        controller?.settings = store.settings
        if !store.settings.diagnostics.recordForBugReports { isRecordingSession = false }
        syncHotKey()
    }

    /// Registers ⌃⌥⌘S while recording for bug reports is on, and frees it otherwise.
    func syncHotKey() {
        guard settings.diagnostics.recordForBugReports else {
            saveClipHotKey = nil
            hotKeyProblem = nil
            return
        }
        guard saveClipHotKey == nil else { return }
        let key = HotKey.saveClip
        saveClipHotKey = HotKey(keyCode: key.keyCode, modifiers: key.modifiers) { [weak self] in self?.saveClip() }
        hotKeyProblem = saveClipHotKey == nil ? "\(key.label) is taken by another app. Save clips from the menu instead." : nil
    }

    /// A binding into the settings that saves and applies on every change.
    func binding<T>(_ path: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.store.settings[keyPath: path] },
                set: { value in self.update { $0[keyPath: path] = value } })
    }

    /// A Double view of a Float setting, for sliders.
    func doubleBinding(_ path: WritableKeyPath<AppSettings, Float>) -> Binding<Double> {
        Binding(get: { Double(self.store.settings[keyPath: path]) },
                set: { value in self.update { $0[keyPath: path] = Float(value) } })
    }

    var presentation: StatusPresentation {
        if startError != nil { return .init(symbol: .attention, dimmed: false, headline: "Trackpad unavailable") }
        return .make(status, phase: phase, targetName: settings.primaryProfile.name)
    }

    /// The welcome window opens by itself on first run and whenever the required grant is missing.
    var shouldShowWelcomeOnLaunch: Bool {
        if let mode = Self.previewMode { return mode == "welcome" }
        return !settings.completedOnboarding || status.permissions.accessibility != .granted
    }

    var trackpadConflicts: [TrackpadConflict] {
        let profile = settings.primaryProfile
        return TrackpadPreferences.conflicts(in: TrackpadPreferences.current(),
                                             threeFingersMapped: profile.engine.mapping.threeFingers != .off,
                                             swallowGestures: profile.gate.swallowGestureEvents)
    }

    // MARK: Scrolling over game windows

    func refreshAddonState() {
        addonState = AddonInstaller.forApp().state
    }

    func installAddon() {
        do {
            try AddonInstaller.forApp().install()
            addonError = nil
        } catch {
            addonError = "Could not install the addon: \(error.localizedDescription)"
        }
        refreshAddonState()
    }

    /// Shows the system prompt the first time, and the Screen Recording list in System Settings.
    func requestScreenRecording() {
        controller?.requestScreenRecording()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Actions

    /// Shows the Accessibility prompt and its list in System Settings.
    func requestAccessibility() {
        controller?.permissions.request([.accessibility])
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        switch LoginItem.set(on) {
        case .success(let s):
            loginStatus = s
            loginError = nil
            update { $0.launchAtLogin = on }
        case .failure(let e):
            loginStatus = LoginItem.status
            loginError = e.message
        }
    }

    /// Starts a fresh copy and quits this one. A new event tap often only works in a process started after the grant.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Clips

    var clipsDirectory: URL {
        controller?.clipsDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("hof-preview-clips")
    }

    /// Saves the last seconds of trackpad data. A sound says whether it worked, so it can be used mid-game.
    func saveClip() {
        guard let controller else { lastClipMessage = "Not running."; return }
        Task {
            switch await controller.saveClip() {
            case .success(let url):
                lastClipMessage = "Saved \(url.lastPathComponent)"
                NSSound(named: "Tink")?.play()
            case .failure(.nothingRecorded):
                lastClipMessage = "Nothing to save: no touch in the last \(settings.diagnostics.rollingSeconds) seconds."
                NSSound(named: "Basso")?.play()
            case .failure(.notRecording):
                lastClipMessage = "Turn on recording for bug reports in Settings › Diagnostics first."
                NSSound(named: "Basso")?.play()
            case .failure(let e):
                lastClipMessage = "Could not save: \(e)"
                NSSound(named: "Basso")?.play()
            }
        }
    }

    func toggleSession() {
        guard let controller else { return }
        if isRecordingSession {
            controller.stopSession()
            isRecordingSession = false
            lastClipMessage = "Session recording stopped."
        } else {
            switch controller.startSession() {
            case .success(let url):
                isRecordingSession = true
                lastClipMessage = "Recording to \(url.lastPathComponent)"
            case .failure(let e):
                lastClipMessage = "Could not start recording: \(e)"
            }
        }
    }

    func showClipsInFinder() {
        try? FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(clipsDirectory)
    }

    /// Clips and sessions, newest first.
    func recentClips(limit: Int = 10) -> [URL] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: clipsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasSuffix(".hoftrace.jsonl") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(limit).map { $0 }
    }

    /// A plain-text note next to a clip: what felt wrong, what was expected.
    static func noteURL(for clip: URL) -> URL {
        clip.deletingLastPathComponent()
            .appendingPathComponent(clip.lastPathComponent.replacingOccurrences(of: ".hoftrace.jsonl", with: ".txt"))
    }

    func note(for clip: URL) -> String {
        (try? String(contentsOf: Self.noteURL(for: clip), encoding: .utf8)) ?? ""
    }

    func setNote(_ text: String, for clip: URL) {
        let url = Self.noteURL(for: clip)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func shutdown() {
        if isRecordingSession { controller?.stopSession() }
        controller?.stop()
        store.flush()
    }

    // MARK: Live readouts, polled only while a view showing them is visible

    var liveState: EngineState {
        EngineState(packed: controller?.core.flags.packedState.load(ordering: .acquiring) ?? 0)
    }

    struct Diagnostics {
        var frames: UInt64 = 0
        var worstFrameMicros: UInt64 = 0
        var swallowed: Int64 = 0
        var reenables: Int32 = 0
        var ringDrops: Int = 0
        var callbackThread = "unknown until the first touch"
        var rejectedContacts: Int32 = 0
    }

    var diagnostics: Diagnostics {
        guard let c = controller else { return Diagnostics() }
        var d = Diagnostics()
        d.frames = c.core.flags.frameCount.load(ordering: .relaxed)
        d.worstFrameMicros = c.core.flags.frameCostMaxNanos.load(ordering: .relaxed) / 1000
        d.swallowed = c.gate?.swallowed ?? 0
        d.reenables = c.gate?.reenables ?? 0
        d.ringDrops = Int(c.core.ring.dropped.load(ordering: .relaxed))
        if let t = c.core.threadReport {
            d.callbackThread = "QoS \(t.qos), precedence \(t.precedence)\(t.timeConstraint ? ", real-time" : "")"
        }
        d.rejectedContacts = c.core.source.rejectedContacts
        return d
    }
}
