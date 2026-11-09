import AppKit
import GestureCore
import PlatformBackends
import Synchronization

/// How the controller is wired. What it does lives in `Settings`, which can change at any time.
public struct PipelineOptions: Sendable {
    /// Without the gate the trackpad's own scrolls also reach the game. Off only for diagnosis.
    public var useTap = true
    /// The grants posting needs: Accessibility, which the event gate needs too.
    public var postingRequires: [Permission] = [.accessibility]
    /// Follow the frontmost app and sleep/wake through NSWorkspace. Off in tests, which call the handlers.
    public var observeWorkspace = true
    /// After posts start failing, how long to wait before letting the engine try posting again.
    public var postRetryNanos: UInt64 = 5_000_000_000
    /// Where saved clips and recorded sessions go.
    public var clipsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Hand of Freedom/Clips", isDirectory: true)

    public init() {}
}

/// What the status line shows. Rebuilt on every change and handed to `onStatusChange`.
public struct PipelineStatus: Sendable, Equatable {
    public var active = false
    public var blockers: [ActivationBlocker] = []
    public var permissions = PermissionSnapshot.allGranted
    public var injector = InjectorHealth()
    public var tapInstalled = false
    public var tapUnstable = false
    public var touchStalled = false
    public var asleep = false
    public var frontmost: String?
    /// The profile for the frontmost app, if any.
    public var profileName: String?
    /// The trackpad sent contacts that failed the sanity checks: the private data layout may have changed.
    public var trackpadDataSuspicious = false
    /// Automatic scrolling over game windows.
    public var marker = MarkerStatus.off

    public init() {}
}

/// The main-actor owner of a running pipeline: lifecycle, faults, and the only writer of the activation
/// flags (`recomputeActivation`). Front ends (`hof live`, the app) build one and watch its status.
@MainActor
public final class PipelineController {
    public let core: PipelineCore
    public let gate: (any EventGate)?
    public let tapThread = TapThread()
    public let permissions: PermissionsMonitor
    public private(set) var status = PipelineStatus()
    public var onStatusChange: ((PipelineStatus) -> Void)?
    /// Called on the writer queue for every hot-thread event, after the controller has looked at it.
    public var onEvent: (@Sendable (TraceEvent) -> Void)?
    /// Engine phase changes (drag start and end), on the main actor, at most one hop behind the hot thread.
    public var onPhase: ((EngineState.Phase) -> Void)?

    /// What to do. Set by the front end whenever the user changes something; takes effect at once.
    public var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            recomputeActivation()
            updateRecording()
        }
    }

    private let options: PipelineOptions
    /// Counts failed posts on the writer queue; reset here when posting is retried.
    private let postFailures = PostFailureBox()
    private var postsFailingSince: UInt64?
    /// The bug-report recorder, present only while `diagnostics.recordForBugReports` is on.
    private let recorderSlot = RecorderSlot()
    private var recording = false
    private let makeMarkerSource: @Sendable () -> any MarkerSource
    private let checks: any PermissionChecks
    private var inputs = ActivationInputs()
    private var publishedConfig: EngineConfig
    private var injectorHealth = InjectorHealth()
    private var tapHealth = TapHealth()
    private var wasActive = false
    private var asleep = false
    private var touchStalled = false
    public private(set) var sessionURL: URL?
    private var trackpadSuspicious = false
    private var watchdog: Watchdog?
    private var frontmost: FrontmostTracker?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var healthTimer: Timer?
    // Automatic scrolling over game windows.
    private var marker: (any MarkerSource)?
    private var markerBundleID: String?
    private var markerStarting = false
    private var markerError: String?
    private var markerRetryAfter: UInt64 = 0
    private var markerLastRestart: UInt64 = 0
    private var markerMissingSince: UInt64?
    private var screenRecording: PermissionState

    /// `gate` nil means no gate at all (as `useTap == false`). `makeMarkerSource` builds the reader of the
    /// game's marker.
    public init(core: PipelineCore, gate: (any EventGate)?, settings: Settings = .firstRun(),
                options: PipelineOptions = PipelineOptions(),
                permissionChecks: any PermissionChecks = SystemPermissionChecks(),
                makeMarkerSource: @escaping @Sendable () -> any MarkerSource = { MarkerCapture() }) {
        self.core = core
        self.settings = settings
        publishedConfig = settings.primaryProfile.engine
        core.mailbox.publish(publishedConfig)
        self.gate = options.useTap ? gate : nil
        self.options = options
        self.makeMarkerSource = makeMarkerSource
        checks = permissionChecks
        screenRecording = permissionChecks.screenRecording()
        permissions = PermissionsMonitor(checks: permissionChecks, watching: options.postingRequires)
        inputs.tapRequired = options.useTap
        inputs.postingRequires = options.postingRequires
    }

    /// Opens the injector, starts touch, the gate and the watchdog.
    /// Touch starts even without permissions: the engine tracks regardless, it just does not act.
    public func start() throws(TouchSourceError) {
        do { try core.injector.open() } catch { injectorHealth.openFailed = true }

        let gate = self.gate
        tapThread.start { gate?.checkEnabled() }
        installGate()

        permissions.onChange = { [weak self] _ in self?.permissionsChanged() }
        permissions.start()
        screenRecording = checks.screenRecording()

        let flags = core.flags
        let dog = Watchdog(flags: flags, hotLoop: core.hotLoop,
                           onStall: { Task { @MainActor [weak self] in self?.setStalled(true) } },
                           onResume: { Task { @MainActor [weak self] in self?.setStalled(false) } })
        dog.start()
        watchdog = dog

        if options.observeWorkspace { observeWorkspace() }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleGateHealth()
                self?.sampleMarker()
            }
        }

        let forward = onEvent
        let slot = recorderSlot, failures = postFailures
        try core.start { [weak self] event in
            slot.recorder?.record(event)
            switch event {
            case .inject(_, _, _, let rc, _, _):
                if let failing = failures.counter.withLock({ $0.record(rc: rc) }) {
                    Task { @MainActor [weak self] in self?.setPostsFailing(failing) }
                }
            case .state(let transition, _, _):
                Task { @MainActor [weak self] in self?.onPhase?(transition.to) }
            default:
                break
            }
            forward?(event)
        }
        recomputeActivation()
        updateRecording()
    }

    /// The engine config the hot thread uses, or will from its next frame.
    public var activeConfig: EngineConfig { publishedConfig }

    /// Releases everything and stops every thread. Safe to call once at exit.
    public func stop() {
        core.flags.activation.targetActive.store(false, ordering: .releasing)
        core.hotLoop.abortActiveDrag()
        healthTimer?.invalidate()
        healthTimer = nil
        stopMarker()
        for o in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        workspaceObservers = []
        watchdog?.stop()
        core.stop()
        let slot = recorderSlot
        core.writerQueue?.sync { slot.recorder?.stopSession(); slot.recorder = nil }
        recording = false
        sessionURL = nil
        core.injector.releaseAll()
        gate?.uninstall()
        tapThread.stop()
        permissions.stop()
        core.injector.close()
    }

    // MARK: Inputs

    public func frontmostChanged(_ bundleID: String?) {
        status.frontmost = bundleID
        recomputeActivation()
    }

    public func handleSleep() {
        asleep = true
        recomputeActivation()                  // releases a held button now
        core.source.stop()
    }

    public func handleWake() {
        core.hotLoop.abortAndForget()
        try? core.source.restart()
        core.injector.close()
        do { try core.injector.open(); injectorHealth.openFailed = false } catch { injectorHealth.openFailed = true }
        retryPosting()
        asleep = false
        permissions.refresh()
        recomputeActivation()
    }

    // MARK: Clips and sessions

    public var clipsDirectory: URL { options.clipsDirectory }

    public enum ClipError: Error, Sendable, Equatable {
        /// The window holds no touch that began inside it.
        case nothingRecorded
        /// Recording for bug reports is off, or the pipeline is not running.
        case notRecording
        case failed(String)
    }

    /// Whether the bug-report recorder is running.
    public var isRecording: Bool { recording }

    /// Saves the last `rollingSeconds` to the clips directory. `note` goes into the clip.
    public func saveClip(note: String? = nil) async -> Result<URL, ClipError> {
        guard recording, let queue = core.writerQueue else { return .failure(.notRecording) }
        let url = clipsDirectory.appendingPathComponent("clip-\(Self.stamp()).hoftrace.jsonl")
        let dir = clipsDirectory, slot = recorderSlot
        return await withCheckedContinuation { cont in
            queue.async {
                guard let recorder = slot.recorder else { return cont.resume(returning: .failure(.notRecording)) }
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    cont.resume(returning: try recorder.saveClip(to: url, note: note) ? .success(url) : .failure(.nothingRecorded))
                } catch {
                    cont.resume(returning: .failure(.failed("\(error)")))
                }
            }
        }
    }

    /// Starts writing every event to a new session file; `stopSession` ends it.
    public func startSession() -> Result<URL, ClipError> {
        guard recording, let queue = core.writerQueue else { return .failure(.notRecording) }
        let url = clipsDirectory.appendingPathComponent("session-\(Self.stamp()).hoftrace.jsonl")
        let dir = clipsDirectory, config = publishedConfig, active = wasActive, slot = recorderSlot
        let error: String? = queue.sync {
            guard let recorder = slot.recorder else { return "recording is off" }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try recorder.startSession(to: url, config: config, active: active)
                return nil
            } catch { return "\(error)" }
        }
        if let error { return .failure(.failed(error)) }
        sessionURL = url
        return .success(url)
    }

    public func stopSession() {
        guard let queue = core.writerQueue else { return }
        let slot = recorderSlot
        queue.sync { slot.recorder?.stopSession() }
        sessionURL = nil
    }

    /// A note in the rolling window and the session, at this moment.
    public func addMarker(_ text: String) {
        guard recording, let queue = core.writerQueue else { return }
        let now = MachTime.nowNanos(), slot = recorderSlot
        queue.async { slot.recorder?.recordNote(text, nanos: now) }
    }

    /// Starts or stops the bug-report recorder to match the setting. A recorder started mid-run takes the
    /// current config and activation, so its clips replay from the right state.
    private func updateRecording() {
        let wanted = settings.diagnostics.recordForBugReports
        guard wanted != recording, let queue = core.writerQueue else { return }
        recording = wanted
        let slot = recorderSlot
        if wanted {
            let recorder = TraceRecorder(t0: core.t0, devices: core.source.devices, initialConfig: publishedConfig,
                                         initialActive: wasActive, windowSeconds: Double(settings.diagnostics.rollingSeconds))
            queue.async { slot.recorder = recorder }
        } else {
            sessionURL = nil
            queue.async { slot.recorder?.stopSession(); slot.recorder = nil }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    // MARK: Activation

    /// The only writer of the activation flags and the only publisher of engine configs.
    public func recomputeActivation() {
        let profile = ProfileResolver().resolve(bundleID: status.frontmost, in: settings)
        // The config goes out before the flag, so the first active frame already uses it.
        if let p = profile, p.engine != publishedConfig {
            core.mailbox.publish(p.engine)
            publishedConfig = p.engine
            if recording, let queue = core.writerQueue {
                let config = p.engine, now = MachTime.nowNanos(), slot = recorderSlot
                queue.async { slot.recorder?.recordConfig(config, nanos: now) }
            }
        }
        let gateConfig = profile?.gate ?? GateConfig()
        core.flags.activation.swallowTrackpadScroll.store(gateConfig.swallowTrackpadScroll, ordering: .relaxed)
        core.flags.activation.swallowGestureEvents.store(gateConfig.swallowGestureEvents, ordering: .relaxed)
        core.flags.activation.scrollModifierMask.store(gateConfig.scrollModifier.mask, ordering: .relaxed)

        inputs.enabled = settings.enabled && !asleep
        inputs.targetFrontmost = profile != nil
        inputs.injectorHealthy = injectorHealth.isHealthy
        inputs.tapInstalled = gate?.isInstalled ?? false
        inputs.permissions = permissions.snapshot
        let blockers = ActivationRule.blockers(inputs)
        let active = blockers.isEmpty
        if wasActive && !active { core.hotLoop.abortActiveDrag() }   // release now; the engine follows next frame
        core.flags.activation.targetActive.store(active, ordering: .releasing)
        wasActive = active
        updateMarker(active: active, profile: profile)

        var s = status
        s.active = active
        s.blockers = blockers
        s.permissions = inputs.permissions
        s.injector = injectorHealth
        s.tapInstalled = inputs.tapInstalled
        s.tapUnstable = tapHealth.isUnstable
        s.touchStalled = touchStalled
        s.asleep = asleep
        s.profileName = profile?.name
        s.trackpadDataSuspicious = trackpadSuspicious
        s.marker = markerStatus(active: active)
        guard s != status else { return }
        status = s
        onStatusChange?(s)
    }

    // MARK: Scrolling over game windows

    /// Shows the Screen Recording prompt the first time; after that System Settings is the way.
    public func requestScreenRecording() {
        checks.requestScreenRecording()
        refreshScreenRecording()
    }

    private func refreshScreenRecording() {
        let now = checks.screenRecording()
        guard now != screenRecording else { return }
        screenRecording = now
        recomputeActivation()
    }

    /// Starts the capture while the tool acts in a profile that wants it, and stops it otherwise.
    private func updateMarker(active: Bool, profile: Profile?) {
        let bundle = status.frontmost
        let wanted = active && profile?.gate.scrollOverWindows == true && screenRecording == .granted && bundle != nil
        if marker != nil, !wanted || markerBundleID != bundle { stopMarker() }
        guard wanted, let bundle, marker == nil, !markerStarting, MachTime.nowNanos() >= markerRetryAfter else { return }
        startMarker(bundle)
    }

    private func startMarker(_ bundle: String) {
        markerStarting = true
        markerBundleID = bundle
        let source = makeMarkerSource()
        let flags = core.flags.activation
        let stopped: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.markerStopped(source) }
        }
        Task { @MainActor [weak self] in
            do {
                try await source.start(bundleIdentifier: bundle, onReading: { state in
                    flags.setMarkerRoute(state?.route, nanos: MachTime.nowNanos())
                }, onStop: stopped)
                guard let self else { await source.stop(); return }
                markerStarting = false
                marker = source
                markerError = nil
                markerMissingSince = nil
            } catch {
                guard let self else { return }
                markerStarting = false
                markerBundleID = nil
                markerError = (error as? MarkerCaptureError)?.description ?? "\(error)"
                markerRetryAfter = MachTime.nowNanos() + 3_000_000_000
                if (error as? MarkerCaptureError) == .notPermitted { screenRecording = .denied }
            }
            self?.recomputeActivation()       // stops it again if it is no longer wanted
        }
    }

    private func stopMarker() {
        guard let source = marker else { return }
        marker = nil
        markerBundleID = nil
        markerMissingSince = nil
        let flags = core.flags.activation
        flags.setMarkerRoute(nil, nanos: 0)
        Task {
            await source.stop()
            flags.setMarkerRoute(nil, nanos: 0)
        }
    }

    /// The system ended the capture, usually because the window went away (a display-mode change).
    private func markerStopped(_ source: any MarkerSource) {
        guard source === marker else { return }
        stopMarker()
        markerRetryAfter = MachTime.nowNanos() + 1_000_000_000
        recomputeActivation()
    }

    /// Once a second: notices a grant, retries a failed start, and restarts a capture that has not
    /// seen the marker for a while, in case the window changed under it.
    public func sampleMarker() {
        guard settings.primaryProfile.gate.scrollOverWindows else { return }
        if screenRecording != .granted { refreshScreenRecording() }
        let now = MachTime.nowNanos()
        if marker != nil {
            if core.flags.activation.markerRoute.load(ordering: .relaxed) != 0 {
                markerMissingSince = nil
            } else if let since = markerMissingSince {
                if now - since > 3_000_000_000, now - markerLastRestart > 10_000_000_000 {
                    markerLastRestart = now
                    stopMarker()
                }
            } else {
                markerMissingSince = now
            }
        }
        recomputeActivation()
    }

    private func markerStatus(active: Bool) -> MarkerStatus {
        guard settings.primaryProfile.gate.scrollOverWindows else { return .off }
        guard screenRecording == .granted else { return .needsScreenRecording }
        guard marker != nil else {
            if markerStarting { return .starting }
            if !active { return .waitingForGame }
            if let markerError { return .failed(markerError) }
            return .starting
        }
        let a = core.flags.activation
        let raw = a.markerRoute.load(ordering: .relaxed)
        let age = Int64(bitPattern: MachTime.nowNanos() &- a.markerNanos.load(ordering: .acquiring))
        guard raw != 0, age < 2_000_000_000, let route = GestureRoute(rawValue: raw - 1) else { return .notSeen }
        return .seen(MarkerState(route: route))
    }

    // MARK: Faults

    private func installGate() {
        guard let gate, !gate.isInstalled, let runLoop = tapThread.runLoop else { return }
        try? gate.install(on: runLoop)
    }

    /// The gate needs Accessibility: it goes with that grant, both ways.
    private func permissionsChanged() {
        if let gate {
            if permissions.snapshot.accessibility == .granted { installGate() } else if gate.isInstalled { gate.uninstall() }
        }
        recomputeActivation()
    }

    private func setStalled(_ stalled: Bool) {
        touchStalled = stalled
        recomputeActivation()
    }

    private func setPostsFailing(_ failing: Bool) {
        injectorHealth.postsFailing = failing
        postsFailingSince = failing ? MachTime.nowNanos() : nil
        if failing { permissions.refresh() }
        recomputeActivation()
    }

    /// Lets the engine post again after failures: on wake, and a few seconds after posts started failing.
    /// If they still fail, three more failed posts switch it off again.
    private func retryPosting() {
        guard injectorHealth.postsFailing else { return }
        postFailures.counter.withLock { $0 = PostFailureCounter() }
        injectorHealth.postsFailing = false
        postsFailingSince = nil
        recomputeActivation()
    }

    /// Once a second, from the health timer.
    public func sampleGateHealth() {
        if let since = postsFailingSince, MachTime.nowNanos() - since > options.postRetryNanos { retryPosting() }
        if core.source.rejectedContacts > 0, !trackpadSuspicious {
            trackpadSuspicious = true
            recomputeActivation()
        }
        guard let gate else { return }
        if tapHealth.sample(reenableCount: gate.reenables, nowNanos: MachTime.nowNanos()) {
            if tapHealth.isUnstable { permissions.refresh() }   // the usual cause is a revoked grant
            recomputeActivation()
        }
    }

    private func observeWorkspace() {
        let tracker = FrontmostTracker()
        tracker.onChange = { [weak self] id in self?.frontmostChanged(id) }
        frontmost = tracker
        status.frontmost = tracker.bundleID
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleWake() }
            },
        ]
    }
}

/// The post-failure counter, shared between the writer queue (which counts) and the main actor (which resets it).
final class PostFailureBox: Sendable {
    let counter = Mutex(PostFailureCounter())
}

/// Holds the bug-report recorder. Confined to the trace writer's queue: read and set only there.
final class RecorderSlot: @unchecked Sendable {
    var recorder: TraceRecorder?
}
