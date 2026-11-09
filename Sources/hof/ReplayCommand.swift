import Foundation
import GestureCore
import Runtime

/// `hof replay file`: regenerates the engine's decisions from a recording.
func replayCommand(_ options: Options) throws {
    guard let path = options.positional.first else { throw CLIError("usage: hof replay [--stats] [--trace] [--config file] file.hoftrace.jsonl") }
    let trace = try TraceReader.read(URL(fileURLWithPath: path))
    if options.has("--stats") {
        print(TraceStats.compute(trace).report)
        let segments = TraceStats.segments(trace)
        guard segments.count > 1 else { return }
        let steps = Replay.run(trace)
        for (index, segment) in segments.enumerated() {
            let end = index + 1 < segments.count ? segments[index + 1].start : .infinity
            let mine = steps.filter { $0.t >= segment.start && $0.t < end }
            let stats = TraceStats.compute(segment.trace)
            let buttons = mine.flatMap { s -> [String] in
                var e: [String] = []
                if let r = s.output.release { e.append("-\(r)") }
                if let p = s.output.press { e.append("+\(p)") }
                return e
            }
            let scroll = mine.reduce(0) { $0 + Int($1.output.scrollTicks) }
            print("""

            ── \(segment.title)
               contacts \(stats.contacts), landings \(stats.landingSequences), lifts \(stats.liftSequences)
               size \(stats.sizeTouching.text)
               max size per contact \(stats.maxSizePerContact.text)
               major axis \(stats.majorAxisTouching.text)
               engine: \(buttons.isEmpty ? "no buttons" : buttons.joined(separator: " ")), scroll \(scroll)
            """)
        }
        return
    }
    let override: EngineConfig? = options.values["--config"] != nil || options.values["--sens"] != nil ? try options.engineConfig() : nil
    let steps = Replay.run(trace, config: override)
    if options.has("--trace") {
        for s in steps {
            let tr = s.trace
            print(String(format: "%9.3f  %@  counted %d raw %d%@  Δ(%.2f,%.2f)mm%@%@  travel %.2f  spread %.1f base %.1f acc %.2f%@  %@",
                         s.t, s.state.phase.traceName, tr.countedFingers, tr.rawTouching,
                         tr.approaching > 0 ? " approaching \(tr.approaching)" : "", tr.meanDeltaMM.x, tr.meanDeltaMM.y,
                         tr.projected ? " projected" : "", tr.liftingOff ? " lifting" : "", tr.armedTravelMM, tr.spreadMM, tr.pinchBaselineMM, tr.pinchAccumulatorMM,
                         tr.pinchEngaged ? " zooming" : "", describe(s.output)))
        }
    } else {
        for line in Replay.goldenLines(steps, t0: trace.header?.t0Nanos ?? 0) { print(line) }
    }
    let presses = steps.compactMap(\.output.press).count
    let scroll = steps.reduce(0) { $0 + Int($1.output.scrollTicks) }
    FileHandle.standardError.write(Data("\(steps.count) frames, \(presses) presses, \(scroll) scroll ticks\n".utf8))
}
