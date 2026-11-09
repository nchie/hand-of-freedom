import Foundation
import Testing
import GestureCore
import PlatformBackends
import Runtime
import TestSupport

@Suite("Trace recorder")
struct TraceRecorderTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hof-clips-\(UUID().uuidString)")

    /// Runs frames through a real hot loop and hands every ring event to the recorder, as the writer does.
    /// `between` runs after each frame index, for aborts and config changes.
    func live(_ b: FrameBuilder, rig: Rig, recorder: TraceRecorder,
              between: [Int: (Rig, TraceRecorder, UInt64) -> Void] = [:]) -> [(UInt64, EngineOutput)] {
        var outputs: [(UInt64, EngineOutput)] = []
        for (i, f) in b.allFrames.enumerated() {
            rig.loop.handle(f)
            for e in rig.drain() {
                recorder.record(e)
                if case .output(let o, let n, _) = e { outputs.append((n, o)) }
            }
            between[i]?(rig, recorder, f.entryNanos)
        }
        return outputs
    }

    /// An old turn, half a second of empty pad, then a new turn.
    func twoSessions() -> FrameBuilder {
        var b = turnSession(turnFrames: 8)
        b.emptyFrames(60)
        b.land(1, at: (40, 50)); b.land(2, at: (60, 50))
        b.frames(3)
        b.moveAll(by: (0.4, 0.2), frames: 12)
        b.liftAll()
        b.emptyFrames(1)
        return b
    }

    func replayed(_ url: URL) throws -> [(UInt64, EngineOutput)] {
        let trace = try TraceReader.read(url)
        return Replay.run(trace).filter { !$0.output.isEmpty }.map { ($0.frame.entryNanos, $0.output) }
    }

    func same(_ a: [(UInt64, EngineOutput)], _ b: [(UInt64, EngineOutput)]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs(Int64(bitPattern: $0.0 &- $1.0)) < 1000 && $0.1 == $1.1 }
    }

    @Test func aClipStartsAtTheFirstTouchInTheWindowAndReplaysLikeLive() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rig = Rig()
        let recorder = TraceRecorder(t0: 0, devices: [TouchDeviceInfo(index: 0, isBuiltIn: true)], initialConfig: .default,
                                     windowSeconds: 0.4)       // the old turn falls out of the window
        let b = twoSessions()
        let outputs = live(b, rig: rig, recorder: recorder)
        let url = dir.appendingPathComponent("clip.hoftrace.jsonl")
        #expect(try recorder.saveClip(to: url, note: "turn felt late"))

        let trace = try TraceReader.read(url)
        let firstFrame = trace.frames.first!.frame
        #expect(firstFrame.count == 2)                          // starts on the new turn's landing
        #expect(trace.records.contains { if case .note("turn felt late", _) = $0 { true } else { false } })
        let clipStart = firstFrame.entryNanos
        let liveInClip = outputs.filter { $0.0 >= clipStart }
        #expect(!liveInClip.isEmpty)
        #expect(same(try replayed(url), liveInClip))           // needs the carried-over active flag to press at all
    }

    @Test func aConfigChangedBeforeTheWindowIsTheClipsHeaderConfig() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var fast = EngineConfig.default
        fast.pointer.pxPerMM = 25
        let rig = Rig()
        let recorder = TraceRecorder(t0: 0, devices: [], initialConfig: .default, windowSeconds: 0.4)
        let b = twoSessions()
        let outputs = live(b, rig: rig, recorder: recorder, between: [2: { rig, rec, nanos in
            rig.mailbox.publish(fast)
            rec.recordConfig(fast, nanos: nanos)
        }])
        let url = dir.appendingPathComponent("clip.hoftrace.jsonl")
        try recorder.saveClip(to: url)
        let trace = try TraceReader.read(url)
        #expect(trace.header?.config == fast)
        let clipStart = trace.frames.first!.frame.entryNanos
        #expect(same(try replayed(url), outputs.filter { $0.0 >= clipStart }))
    }

    @Test func anAbortMidTurnReplaysLikeLive() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rig = Rig()
        let recorder = TraceRecorder(t0: 0, devices: [], initialConfig: .default, windowSeconds: 30)
        var b = FrameBuilder()
        b.emptyFrames(1)
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (0.5, 0), frames: 15)
        b.liftAll()
        b.emptyFrames(1)
        let outputs = live(b, rig: rig, recorder: recorder, between: [10: { rig, _, _ in rig.loop.abortActiveDrag() }])
        #expect(outputs.contains { $0.1.release != nil })
        let url = dir.appendingPathComponent("clip.hoftrace.jsonl")
        try recorder.saveClip(to: url)
        #expect(same(try replayed(url), outputs))
    }

    @Test func nothingTouchedMeansNoClip() throws {
        let recorder = TraceRecorder(t0: 0, devices: [], initialConfig: .default)
        recorder.recordNote("idle", nanos: 1)
        #expect(try !recorder.saveClip(to: dir.appendingPathComponent("none.hoftrace.jsonl")))
    }

    @Test func aSessionGetsEverything() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rig = Rig()
        let recorder = TraceRecorder(t0: 0, devices: [], initialConfig: .default, windowSeconds: 0.1)
        let url = dir.appendingPathComponent("session.hoftrace.jsonl")
        try recorder.startSession(to: url, config: .default, active: true)
        let b = twoSessions()
        _ = live(b, rig: rig, recorder: recorder)
        recorder.stopSession()
        #expect(try TraceReader.read(url).frames.count == b.allFrames.count)   // not limited to the window
    }
}
