import CoreFoundation
import Foundation
import Synchronization
import Testing
import GestureCore
import PlatformBackends
import Runtime
import TestSupport

final class FakeTouchSource: TouchSource, @unchecked Sendable {
    let devices = [TouchDeviceInfo(index: 0, isBuiltIn: true)]
    var starts = 0, stops = 0, restarts = 0
    func start(sink: any TouchFrameSink) throws(TouchSourceError) { starts += 1 }
    func stop() { stops += 1 }
    func restart() throws(TouchSourceError) { restarts += 1 }
}

final class FakeGate: EventGate, @unchecked Sendable {
    var installed = false
    var failInstall = false
    var reenableValue: Int32 = 0
    var isInstalled: Bool { installed }
    func install(on runLoop: CFRunLoop) throws(TapError) {
        if failInstall { throw .notPermitted }
        installed = true
    }
    func uninstall() { installed = false }
    func checkEnabled() {}
    var reenables: Int32 { reenableValue }
    var swallowed: Int64 { 0 }
}

final class FakeChecks: PermissionChecks, @unchecked Sendable {
    let state = Mutex(PermissionSnapshot.allGranted)
    func snapshot() -> PermissionSnapshot { state.withLock { $0 } }
    func request(_ permissions: [Permission]) {}
    func set(_ change: (inout PermissionSnapshot) -> Void) { state.withLock { change(&$0) } }
    let screen = Mutex(PermissionState.granted)
    func screenRecording() -> PermissionState { screen.withLock { $0 } }
    func requestScreenRecording() {}
}

final class FakeMarkerSource: MarkerSource, @unchecked Sendable {
    var starts: [String] = []
    var stops = 0
    var failWith: MarkerCaptureError?
    private var onReading: (@Sendable (MarkerState?) -> Void)?
    private var onStop: (@Sendable () -> Void)?

    func start(bundleIdentifier: String, onReading: @escaping @Sendable (MarkerState?) -> Void,
               onStop: @escaping @Sendable () -> Void) async throws {
        if let failWith { throw failWith }
        starts.append(bundleIdentifier)
        self.onReading = onReading
        self.onStop = onStop
    }

    func stop() async { stops += 1 }
    func emit(_ state: MarkerState?) { onReading?(state) }
    func endBySystem() { onStop?() }
}

@MainActor
@Suite("Pipeline controller", .serialized)
struct PipelineControllerTests {
    let source = FakeTouchSource()
    let gate = FakeGate()
    let checks = FakeChecks()
    let listener = FakeListener()
    let injector: EchoInjector
    let controller: PipelineController

    init() throws {
        injector = EchoInjector(listener: listener)
        var options = PipelineOptions()
        options.observeWorkspace = false
        options.postRetryNanos = 200_000_000
        options.clipsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("hof-ctl-clips-\(UUID().uuidString)")
        let core = try PipelineCore(config: .default, injector: injector, source: source)
        controller = PipelineController(core: core, gate: gate, options: options, permissionChecks: checks)
    }

    func started(frontmost: String? = "com.blizzard.worldofwarcraft") async throws -> PipelineController {
        try controller.start()
        controller.frontmostChanged(frontmost)
        return controller
    }

    var targetActive: Bool { controller.core.flags.activation.targetActive.load(ordering: .acquiring) }

    @Test func actsOnlyWhileTheGameIsFrontmost() async throws {
        let c = try await started()
        defer { c.stop() }
        #expect(targetActive)
        #expect(c.status.injector.isHealthy)
        c.frontmostChanged("com.apple.finder")
        #expect(!targetActive)
        #expect(c.status.blockers == [.targetNotFrontmost])
    }

    @Test func becomingInactiveReleasesAHeldButtonAtOnce() async throws {
        let c = try await started()
        defer { c.stop() }
        injector.buttonDown(.right)
        c.frontmostChanged(nil)
        #expect(injector.held.raw == 0)
    }

    @Test func sleepReleasesAndStopsAndWakeRestarts() async throws {
        let c = try await started()
        defer { c.stop() }
        injector.buttonDown(.left)
        c.handleSleep()
        #expect(injector.held.raw == 0)
        #expect(!targetActive)
        #expect(source.stops == 1)
        #expect(c.status.asleep)
        c.handleWake()
        #expect(source.restarts == 1)
        #expect(targetActive)
    }

    @Test func revokedAccessibilityStopsActingAndARegrantResumes() async throws {
        let c = try await started()
        defer { c.stop() }
        checks.set { $0.accessibility = .denied }
        c.permissions.refresh()
        #expect(!targetActive)
        #expect(c.status.blockers == [.missingPermission(.accessibility), .gateNotInstalled])   // the gate needs it too
        checks.set { $0.accessibility = .granted }
        c.permissions.refresh()
        #expect(targetActive)
    }

    @Test func failingPostsStopActingAndPostingIsRetriedAfterAWhile() async throws {
        let c = try await started()
        defer { c.stop() }
        injector.moveResult = -1
        try await feedTurn(c, lift: false)                   // the release would succeed and clear it
        try await Task.sleep(for: .milliseconds(50))         // the verdict hops to the main actor
        #expect(!targetActive)
        #expect(c.status.blockers == [.injectorUnavailable])
        #expect(StatusPresentation.make(c.status, phase: .idle, targetName: "WoW").headline.contains("mouse input"))
        injector.moveResult = 0
        try await Task.sleep(for: .milliseconds(250))
        c.sampleGateHealth()
        #expect(targetActive)
    }

    @Test func theGateFollowsAccessibilityBothWays() async throws {
        gate.failInstall = true
        checks.set { $0.accessibility = .denied }
        let c = try await started()
        defer { c.stop() }
        #expect(c.status.blockers == [.missingPermission(.accessibility), .gateNotInstalled])
        gate.failInstall = false
        checks.set { $0.accessibility = .granted }
        c.permissions.refresh()
        #expect(gate.installed)
        #expect(targetActive)
        checks.set { $0.accessibility = .denied }
        c.permissions.refresh()
        #expect(!gate.installed)
        #expect(!targetActive)
    }

    /// Posting and the gate need only Accessibility.
    @Test func inputMonitoringIsNotNeededAndNothingIsPostedAtStart() async throws {
        checks.set { $0.inputMonitoring = .denied }
        let c = try await started()
        defer { c.stop() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(targetActive)
        #expect(injector.moves.withLock { $0 }.isEmpty)
    }

    @Test func disablingStopsActing() async throws {
        let c = try await started()
        defer { c.stop() }
        c.settings.enabled = false
        #expect(!targetActive)
        #expect(c.status.blockers == [.disabled])
    }

    @Test func theFrontmostAppsProfileDecidesConfigAndGate() async throws {
        var s = Settings.firstRun()
        s.primaryProfile.engine.pointer.pxPerMM = 17
        s.primaryProfile.gate.swallowTrackpadScroll = false
        var other = Profile(name: "Other game", bundleIdentifiers: ["com.example.game"])
        other.engine.pointer.pxPerMM = 5
        s.profiles.append(other)
        let c = try await started()
        defer { c.stop() }
        c.settings = s
        #expect(c.activeConfig.pointer.pxPerMM == 17)
        var swallows = c.core.flags.activation.swallowTrackpadScroll.load(ordering: .relaxed)
        #expect(!swallows)
        #expect(c.status.profileName == "World of Warcraft")
        c.frontmostChanged("com.example.game")
        #expect(targetActive)
        #expect(c.activeConfig.pointer.pxPerMM == 5)
        swallows = c.core.flags.activation.swallowTrackpadScroll.load(ordering: .relaxed)
        #expect(swallows)
        c.frontmostChanged("com.apple.finder")
        #expect(!targetActive)
        #expect(c.status.profileName == nil)
    }

    @Test func actInAllAppsUsesTheFirstEnabledProfileAnywhere() async throws {
        let c = try await started(frontmost: "com.apple.finder")
        defer { c.stop() }
        #expect(!targetActive)
        c.settings.actInAllApps = true
        #expect(targetActive)
    }

    /// A turn fed straight into the hot loop, as the touch source would.
    func feedTurn(_ c: PipelineController, lift: Bool = true) async throws {
        var b = FrameBuilder()
        b.emptyFrames(1)
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (0.5, 0), frames: 10)
        if lift {
            b.liftAll()
            b.emptyFrames(1)
        }
        let now = MachTime.nowNanos()
        for var f in b.allFrames {
            f.entryNanos = now &+ f.entryNanos             // recent, so inside the rolling window
            c.core.hotLoop.handle(f)
        }
        try await Task.sleep(for: .milliseconds(150))        // the writer drains every 50 ms
    }

    func recordingForBugReports(_ c: PipelineController) {
        var s = c.settings
        s.diagnostics.recordForBugReports = true
        c.settings = s
    }

    @Test func nothingIsRecordedUnlessTurnedOn() async throws {
        let c = try await started()
        defer { c.stop() }
        try await feedTurn(c)
        #expect(!c.isRecording)
        #expect(await c.saveClip() == .failure(.notRecording))
        #expect(c.startSession() == .failure(.notRecording))
    }

    @Test func savesTheLastSecondsAsAClipThatReplays() async throws {
        let c = try await started()
        defer { c.stop() }
        recordingForBugReports(c)
        #expect(await c.saveClip() == .failure(.nothingRecorded))
        try await feedTurn(c)
        c.addMarker("before the save")
        guard case .success(let url) = await c.saveClip(note: "felt late") else { Issue.record("no clip"); return }
        #expect(url.deletingLastPathComponent().standardizedFileURL.path == c.clipsDirectory.standardizedFileURL.path)
        let trace = try TraceReader.read(url)
        #expect(trace.frames.count > 10)
        #expect(Replay.run(trace).contains { $0.output.press == .right })
    }

    @Test func aSessionRecordsUntilStopped() async throws {
        let c = try await started()
        defer { c.stop() }
        recordingForBugReports(c)
        guard case .success(let url) = c.startSession() else { Issue.record("no session"); return }
        #expect(c.sessionURL == url)
        try await feedTurn(c)
        c.stopSession()
        #expect(c.sessionURL == nil)
        #expect(try TraceReader.read(url).frames.count > 10)
    }

    @Test func turningRecordingOffEndsASession() async throws {
        let c = try await started()
        defer { c.stop() }
        recordingForBugReports(c)
        _ = c.startSession()
        var s = c.settings
        s.diagnostics.recordForBugReports = false
        c.settings = s
        #expect(c.sessionURL == nil)
        #expect(await c.saveClip() == .failure(.notRecording))
    }

    @Test func stopReleasesAndUninstalls() async throws {
        let c = try await started()
        injector.buttonDown(.right)
        c.stop()
        #expect(injector.held.raw == 0)
        #expect(!gate.installed)
        #expect(!targetActive)
    }
}
