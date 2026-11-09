import Foundation
import Testing
import GestureCore
import PlatformBackends
import Runtime
import TestSupport

@Suite("Scroll route at runtime")
struct ScrollRouteRuntimeTests {
    static let fn = ScrollModifier.fn.mask

    func holdingFn(_ rig: Rig, _ held: Bool) {
        rig.flags.activation.scrollModifierMask.store(Self.fn, ordering: .relaxed)
        rig.flags.activation.modifierFlags.store(held ? Self.fn | 0x100 : 0x100, ordering: .relaxed)
    }

    @Test func theHeldKeyRoutesAGestureToScrollingAndOpensTheGate() {
        let rig = Rig()
        holdingFn(rig, true)
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (0, 1), frames: 10)
        rig.feed(b.allFrames)
        #expect(rig.calls.isEmpty)
        let open = rig.flags.activation.scrollPassthrough.load(ordering: .acquiring)
        #expect(open)
        #expect(rig.drain().contains { if case .route(.scroll, _) = $0 { true } else { false } })

        b.liftAll()
        b.emptyFrames(1)
        rig.feed(Array(b.allFrames.suffix(4)))
        let stillOpen = rig.flags.activation.scrollPassthrough.load(ordering: .acquiring)
        #expect(!stillOpen)
    }

    @Test func anotherModifierDoesNothing() {
        let rig = Rig()
        rig.flags.activation.scrollModifierMask.store(Self.fn, ordering: .relaxed)
        rig.flags.activation.modifierFlags.store(ScrollModifier.shift.mask, ordering: .relaxed)
        rig.feed(turnSession().allFrames)
        #expect(rig.downs == [.right])
    }

    @Test func noKeyConfiguredMeansAlwaysDrive() {
        let rig = Rig()
        rig.flags.activation.modifierFlags.store(UInt64.max, ordering: .relaxed)
        rig.feed(turnSession().allFrames)
        #expect(rig.downs == [.right])
    }

    func turnFrames(shiftedBy nanos: UInt64 = 0) -> [TouchFrame] {
        turnSession().allFrames.map { var f = $0; f.entryNanos &+= nanos; return f }
    }

    @Test func aFreshMarkerOverAScrollingWindowScrolls() {
        let rig = Rig()
        rig.flags.activation.setMarkerRoute(.scroll, nanos: MachTime.nowNanos())
        rig.feed(turnFrames())
        #expect(rig.downs.isEmpty)
        #expect(rig.drain().contains { if case .route(.scroll, _) = $0 { true } else { false } })
    }

    @Test func aMarkerOverAnotherWindowIgnoresAndKeepsTheGateShut() {
        let rig = Rig()
        rig.flags.activation.setMarkerRoute(.ignore, nanos: MachTime.nowNanos())
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (1, 0), frames: 10)
        rig.feed(b.allFrames)
        #expect(rig.calls.isEmpty)
        let open = rig.flags.activation.scrollPassthrough.load(ordering: .acquiring)
        #expect(!open)
        #expect(EngineState(packed: rig.flags.packedState.load(ordering: .acquiring)).phase == .ignoring)
    }

    @Test func aStaleMarkerFallsBackToTurning() {
        let rig = Rig()
        rig.flags.activation.setMarkerRoute(.ignore, nanos: 1_000)
        rig.feed(turnFrames(shiftedBy: 5_000_000_000))
        #expect(rig.downs == [.right])
    }

    @Test func theScrollKeyWinsOverTheMarker() {
        let rig = Rig()
        holdingFn(rig, true)
        rig.flags.activation.setMarkerRoute(.ignore, nanos: MachTime.nowNanos())
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (0, 1), frames: 5)
        rig.feed(b.allFrames)
        let open = rig.flags.activation.scrollPassthrough.load(ordering: .acquiring)
        #expect(open)
    }

    @Test func routeLinesRoundTripAndReplay() throws {
        let header = TraceHeader(tool: "test", devices: [], config: .default, t0Nanos: 0)
        var lines = [TraceCodec.headerLine(header), TraceCodec.flagLine(active: true, tSeconds: 0),
                     TraceCodec.line(.route(.scroll, entryNanos: 0), t0: 0)]
        for f in turnSession().allFrames { lines.append(TraceCodec.line(.frame(f), t0: 0)) }
        let trace = try TraceReader.parse(lines.joined(separator: "\n"))
        #expect(trace.records.contains { if case .route(.scroll, _) = $0 { true } else { false } })
        #expect(Replay.run(trace).allSatisfy { $0.output.press == nil })

        lines[2] = TraceCodec.line(.route(.ignore, entryNanos: 0), t0: 0)
        let ignored = try TraceReader.parse(lines.joined(separator: "\n"))
        #expect(ignored.records.contains { if case .route(.ignore, _) = $0 { true } else { false } })
        #expect(Replay.run(ignored).allSatisfy { $0.output.press == nil })

        lines.remove(at: 2)
        #expect(Replay.run(try TraceReader.parse(lines.joined(separator: "\n"))).contains { $0.output.press == .right })
    }

    @Test func aClipKeepsAKeyHeldSinceBeforeItsWindow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hof-route-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rig = Rig()
        holdingFn(rig, true)
        let recorder = TraceRecorder(t0: 0, devices: [], initialConfig: .default, windowSeconds: 0.4)
        var b = turnSession(turnFrames: 8)
        b.emptyFrames(60)
        b.land(1, at: (40, 50)); b.land(2, at: (60, 50))
        b.frames(3)
        b.moveAll(by: (0.4, 0.2), frames: 12)
        b.liftAll()
        for f in b.allFrames {
            rig.loop.handle(f)
            for e in rig.drain() { recorder.record(e) }
        }
        let url = dir.appendingPathComponent("clip.hoftrace.jsonl")
        #expect(try recorder.saveClip(to: url))
        let trace = try TraceReader.read(url)
        #expect(trace.records.contains { if case .route(.scroll, _) = $0 { true } else { false } })
        #expect(Replay.run(trace).allSatisfy { $0.output.press == nil })
    }

    @Test func olderSettingsWithoutTheKeyStillLoad() throws {
        let old = #"{"swallowTrackpadScroll":false,"swallowGestureEvents":true}"#
        let gate = try JSONDecoder().decode(GateConfig.self, from: Data(old.utf8))
        #expect(gate.scrollModifier == .none)
        #expect(gate.swallowTrackpadScroll == false)
        let unknown = #"{"scrollModifier":"hyper"}"#
        #expect(try JSONDecoder().decode(GateConfig.self, from: Data(unknown.utf8)).scrollModifier == .none)
        #expect(gate.scrollOverWindows == false)
        var g = GateConfig()
        g.scrollModifier = .option
        g.scrollOverWindows = true
        #expect(try JSONDecoder().decode(GateConfig.self, from: JSONEncoder().encode(g)) == g)
    }
}

@Suite("Addon installer")
struct AddonInstallerTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("hof-addon-\(UUID().uuidString)")

    func addon(version: String, in dir: URL) throws -> URL {
        let folder = dir.appendingPathComponent("HandOfFreedom", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "## Interface: 16001\n## Version: \(version)\nHandOfFreedom.lua\n"
            .write(to: folder.appendingPathComponent("HandOfFreedom.toc"), atomically: true, encoding: .utf8)
        try "-- marker".write(to: folder.appendingPathComponent("HandOfFreedom.lua"), atomically: true, encoding: .utf8)
        return folder
    }

    @Test func installsUpdatesAndReportsEachState() throws {
        let fm = FileManager.default
        let bundled = try addon(version: "2", in: root.appendingPathComponent("app"))
        let game = root.appendingPathComponent("game", isDirectory: true)
        let addOns = game.appendingPathComponent("Interface/AddOns", isDirectory: true)

        #expect(AddonInstaller(bundled: nil, addOns: addOns).state == .notBundled)
        #expect(AddonInstaller(bundled: bundled, addOns: addOns).state == .gameNotFound)
        try fm.createDirectory(at: game.appendingPathComponent("Interface"), withIntermediateDirectories: true)
        let installer = AddonInstaller(bundled: bundled, addOns: addOns)
        #expect(installer.state == .notInstalled)

        _ = try addon(version: "1", in: addOns)
        #expect(installer.state == .outdated)
        try installer.install()
        #expect(installer.state == .installed)
        #expect(fm.fileExists(atPath: addOns.appendingPathComponent("HandOfFreedom/HandOfFreedom.lua").path))
    }

    @Test func theRepositoryAddonHasAVersion() throws {
        let here = URL(fileURLWithPath: #filePath)
        let addon = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Addon/HandOfFreedom")
        #expect(AddonInstaller(bundled: addon, addOns: root).state != .notBundled)
    }
}
