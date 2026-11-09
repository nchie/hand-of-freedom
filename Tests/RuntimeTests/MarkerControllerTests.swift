import Foundation
import Testing
import GestureCore
import PlatformBackends
import Runtime
import TestSupport

@MainActor
@Suite("Scrolling over game windows", .serialized)
struct MarkerControllerTests {
    let checks = FakeChecks()
    let marker = FakeMarkerSource()
    let controller: PipelineController
    static let wow = "com.blizzard.worldofwarcraft"

    init() throws {
        var options = PipelineOptions()
        options.observeWorkspace = false
        options.clipsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("hof-marker-\(UUID().uuidString)")
        let core = try PipelineCore(config: .default, injector: EchoInjector(listener: FakeListener()), source: FakeTouchSource())
        let m = marker
        controller = PipelineController(core: core, gate: FakeGate(), options: options, permissionChecks: checks,
                                        makeMarkerSource: { m })
    }

    func start(on: Bool = true) async throws {
        var s = Settings.firstRun()
        s.profiles[0].gate.scrollOverWindows = on
        controller.settings = s
        try controller.start()
        controller.frontmostChanged(Self.wow)
    }

    /// Lets the controller's start task run.
    func settle(until done: () -> Bool) async {
        for _ in 0..<100 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    /// Waits until the controller holds the started capture, not just until the fake was asked to start.
    func reading(starts: Int = 1) async {
        await settle { marker.starts.count >= starts && controller.status.marker != .starting }
    }

    var route: UInt8 { controller.core.flags.activation.markerRoute.load(ordering: .relaxed) }

    @Test func offByDefault() async throws {
        try await start(on: false)
        defer { controller.stop() }
        await settle { false }
        #expect(marker.starts.isEmpty)
        #expect(controller.status.marker == .off)
    }

    @Test func readsTheGameWhileItIsInFrontAndStopsWhenItIsNot() async throws {
        try await start()
        defer { controller.stop() }
        await reading()
        #expect(marker.starts == [Self.wow])

        marker.emit(.scrollable)
        #expect(route == GestureRoute.scroll.rawValue + 1)
        controller.sampleMarker()
        #expect(controller.status.marker == .seen(.scrollable))

        marker.emit(nil)
        controller.sampleMarker()
        #expect(controller.status.marker == .notSeen)

        controller.frontmostChanged("com.apple.finder")
        await settle { marker.stops > 0 }
        #expect(marker.stops == 1)
        #expect(route == 0)
        #expect(controller.status.marker == .waitingForGame)
    }

    @Test func waitsForScreenRecording() async throws {
        checks.screen.withLock { $0 = .denied }
        try await start()
        defer { controller.stop() }
        await settle { false }
        #expect(marker.starts.isEmpty)
        #expect(controller.status.marker == .needsScreenRecording)

        checks.screen.withLock { $0 = .granted }
        controller.sampleMarker()
        await reading()
        #expect(marker.starts.count == 1)
    }

    @Test func aFailedStartIsReported() async throws {
        marker.failWith = .windowNotFound
        try await start()
        defer { controller.stop() }
        await settle { controller.status.marker != .starting }
        #expect(controller.status.marker == .failed("the game has no window on screen"))
    }

    @Test func aCaptureTheSystemEndsIsClearedAndRestarted() async throws {
        try await start()
        defer { controller.stop() }
        await reading()
        marker.emit(.window)
        #expect(route != 0)
        marker.endBySystem()
        await settle { route == 0 }
        #expect(route == 0)
        try await Task.sleep(for: .milliseconds(1100))  // the restart waits a second
        controller.sampleMarker()
        await reading(starts: 2)
        #expect(marker.starts.count == 2)
    }

    @Test func turningTheSettingOffStopsReading() async throws {
        try await start()
        defer { controller.stop() }
        await reading()
        var s = controller.settings
        s.profiles[0].gate.scrollOverWindows = false
        controller.settings = s
        await settle { marker.stops > 0 }
        #expect(marker.stops == 1)
        #expect(controller.status.marker == .off)
    }
}
