import CMultitouchSupport
import Foundation
import GestureCore
import PlatformBackends
import Runtime
import Testing
import TestSupport

@Suite("Traces")
struct TraceTests {
    /// Encodes a scripted session the way `hof record` does and parses it back.
    func roundTrip(_ b: FrameBuilder, config: EngineConfig = .default) throws -> Trace {
        let header = TraceHeader(tool: "test", devices: [TouchDeviceInfo(index: 0, isBuiltIn: true)], config: config, t0Nanos: 0)
        var lines = [TraceCodec.headerLine(header), TraceCodec.flagLine(active: true, tSeconds: 0)]
        for f in b.allFrames { lines.append(TraceCodec.line(.frame(f), t0: 0)) }
        return try TraceReader.parse(lines.joined(separator: "\n"))
    }

    @Test func framesRoundTripExactly() throws {
        var b = turnSession()
        b.land(9, at: (33.3333, 12.7), size: 2.71828)
        b.frames(2)
        let trace = try roundTrip(b)
        let original = b.allFrames
        let parsed = trace.frames.map(\.frame)
        #expect(parsed.count == original.count)
        for (p, o) in zip(parsed, original) {
            #expect(p.count == o.count)
            #expect(p.sequence == o.sequence)
            for i in 0..<o.count { #expect(p[i] == o[i]) }
        }
        #expect(trace.header?.config == .default)
    }

    @Test func replayOfARecordingMatchesTheLiveEngine() throws {
        var b = FrameBuilder()
        b.land(1, at: (60, 40)); b.land(2, at: (80, 40))
        b.frames(3)
        b.moveAll(by: (0, 1), frames: 5)
        b.moveEach([1: (-0.3, 1), 2: (0.3, 1)], frames: 30)
        b.liftAll()
        let live = b.run()
        let steps = Replay.run(try roundTrip(b))
        #expect(steps.map(\.output) == live.outputs)
        #expect(steps.contains { $0.output.scrollTicks != 0 })
    }

    @Test func configLinesChangeTheReplayConfig() throws {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (1, 0), frames: 3)
        let header = TraceHeader(tool: "test", devices: [], config: .default, t0Nanos: 0)
        var lines = [TraceCodec.headerLine(header), TraceCodec.flagLine(active: true, tSeconds: 0)]
        let frames = b.allFrames
        for f in frames.prefix(5) { lines.append(TraceCodec.line(.frame(f), t0: 0)) }
        lines.append(TraceCodec.configLine(.default.with { $0.pointer.pxPerMM = 20 }, tSeconds: 0.04))
        for f in frames.dropFirst(5) { lines.append(TraceCodec.line(.frame(f), t0: 0)) }
        let steps = Replay.run(try TraceReader.parse(lines.joined(separator: "\n")))
        #expect(steps.last?.output.movePx.x == 20)
    }

    @Test func statsReportLiftAndLandingSequences() throws {
        let stats = TraceStats.compute(try roundTrip(turnSession()))
        #expect(stats.liftSequences == ["breaking,leaving": 2])
        #expect(stats.landingSequences == ["making": 2])
        #expect(stats.contacts == 2)
        #expect(abs(stats.activeRateHz - 120) < 1)
        #expect(stats.sizeTouching.p50 == 1.0)
    }

    @Test func guidedNotesSplitATraceIntoSegments() throws {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.liftAll()
        let first = b.allFrames.count
        b.land(3, at: (60, 50)); b.land(4, at: (80, 50)); b.land(5, at: (95, 50))
        b.frames(3)
        b.liftAll()
        let frames = b.allFrames
        let header = TraceHeader(tool: "test", devices: [], config: .default, t0Nanos: 0)
        var lines = [TraceCodec.headerLine(header), TraceCodec.noteLine("Two fingers", tSeconds: 0)]
        for f in frames[..<first] { lines.append(TraceCodec.line(.frame(f), t0: 0)) }
        lines.append(TraceCodec.noteLine("Three fingers", tSeconds: frames[first].deviceTimestamp - 0.001))
        for f in frames[first...] { lines.append(TraceCodec.line(.frame(f), t0: 0)) }
        let segments = TraceStats.segments(try TraceReader.parse(lines.joined(separator: "\n")))
        #expect(segments.map(\.title) == ["Two fingers", "Three fingers"])
        #expect(segments.map { TraceStats.compute($0.trace).contacts } == [2, 3])
    }

    @Test func everyEventKindEncodesAsJSON() throws {
        var out = EngineOutput()
        out.press = .right
        out.held = .right
        out.movePx = SIMD2(3, -1)
        out.scrollTicks = 2
        let events: [TraceEvent] = [
            .output(out, entryNanos: 1_000_000, us: 12),
            .inject(.move, button: .right, value: SIMD2(3, -1), rc: 0, entryNanos: 1_000_000, us: 30),
            .inject(.scroll, button: nil, value: SIMD2(0, 2), rc: -536870201, entryNanos: 1_000_000, us: 40),
            .state(.init(from: .armed(count: 2), to: .dragging(.right, members: 2)), entryNanos: 1_000_000, us: 12),
            .flag(targetActive: false, entryNanos: 2_000_000),
            .reset(.abortAndForget, entryNanos: 3_000_000),
        ]
        var lines = events.map { TraceCodec.line($0, t0: 0) }
        lines.append(TraceCodec.sysLine(qos: "userInteractive", precedence: 47, timeConstraint: false, tSeconds: 0))
        lines.append(TraceCodec.noteLine("camera \"jumped\" here", tSeconds: 1.5))
        for line in lines {
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            #expect(obj?["k"] != nil, "not JSON: \(line)")
        }
        let trace = try TraceReader.parse(lines.joined(separator: "\n"))
        #expect(trace.records.count == lines.count)
    }

    @Test func implausibleContactsAreRejected() {
        var t = MTTouch()
        t.identifier = 7
        t.state = 4
        t.normalized.pos = MTPoint(x: 0.5, y: 0.4)
        t.mm.pos = MTPoint(x: 60, y: 30)
        t.size = 1.1
        t.majorAxis = 9
        t.minorAxis = 7
        let c = MTTouchConversion.contact(from: t)
        #expect(c?.id == 7)
        #expect(c?.phase == .touching)
        #expect(c?.positionMM == SIMD2(60, 30))

        var bad = t
        bad.mm.pos.x = .nan
        #expect(MTTouchConversion.contact(from: bad) == nil)
        bad = t
        bad.state = 12
        #expect(MTTouchConversion.contact(from: bad) == nil)
        bad = t
        bad.normalized.pos.x = 4
        #expect(MTTouchConversion.contact(from: bad) == nil)
    }
}
