import Foundation
import GestureCore

public struct ReplayStep: Sendable {
    public var t: Double
    public var frame: TouchFrame
    public var active: Bool
    public var output: EngineOutput
    public var state: EngineState
    public var trace: EngineTrace
}

/// Feeds a recorded trace through a fresh engine. Frames, activation flags and config changes come
/// from the trace; outputs and states are regenerated, which is what golden tests compare.
public enum Replay {
    public static func run(_ trace: Trace, config override: EngineConfig? = nil) -> [ReplayStep] {
        var engine = GestureEngine()
        var config = override ?? trace.header?.config ?? .default
        var active = false
        var route = GestureRoute.drive
        var pending = EngineOutput()          // an abort's release, merged into the next frame as the hot loop does
        var steps: [ReplayStep] = []
        for record in trace.records {
            switch record {
            case .flag(let a, _):
                active = a
            case .route(let r, _):
                route = r
            case .config(let c, _):
                if override == nil { config = c }
            case .reset(let request, _):
                pending.merge(engine.abort())
                if request == .abortAndForget { engine.reset() }
            case .frame(let frame, let t):
                var out = pending
                pending = EngineOutput()
                out.merge(engine.process(frame, config: config, targetActive: active, route: route))
                steps.append(ReplayStep(t: t, frame: frame, active: active, output: out, state: engine.state, trace: engine.trace))
            case .sys, .note, .other:
                break
            }
        }
        return steps
    }

    /// The `out` and `state` lines a golden file holds.
    public static func goldenLines(_ steps: [ReplayStep], t0: UInt64 = 0) -> [String] {
        var lines: [String] = []
        for s in steps {
            if !s.output.isEmpty { lines.append(TraceCodec.line(.output(s.output, entryNanos: s.frame.entryNanos, us: 0), t0: t0)) }
            if let tr = s.output.transition { lines.append(TraceCodec.line(.state(tr, entryNanos: s.frame.entryNanos, us: 0), t0: t0)) }
        }
        return lines
    }
}
