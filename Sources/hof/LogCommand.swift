import Foundation
import GestureCore
import PlatformBackends
import Runtime

/// `hof log`: live finger frames and what the engine would do. Posts nothing, needs no permission.
@MainActor
func logCommand(_ options: Options) throws -> Never {
    let config = try options.engineConfig()
    let pipeline = try Pipeline(config: config, injector: NullInjector())
    pipeline.flags.activation.targetActive.store(true, ordering: .releasing)
    let raw = options.has("--raw")
    let printer = LogPrinter(pipeline: pipeline, raw: raw)
    try pipeline.start { printer.handle($0) }
    print("Logging trackpad frames\(raw ? "" : " (only frames where contacts or phases change; --raw for all)"). Ctrl-C to stop.")
    runUntilStopped(seconds: options.seconds) {
        pipeline.stop()
        printer.summary()
    }
}

final class LogPrinter: @unchecked Sendable {
    private let pipeline: Pipeline
    private let raw: Bool
    private var lastSignature: [String] = []
    private var frames = 0
    private var reportedThread = false

    init(pipeline: Pipeline, raw: Bool) {
        self.pipeline = pipeline
        self.raw = raw
    }

    func handle(_ event: TraceEvent) {
        switch event {
        case .frame(let f):
            frames += 1
            if !reportedThread, let t = pipeline.threadReport {
                reportedThread = true
                print("callback thread: QoS \(t.qos), precedence \(t.precedence), real-time policy \(t.timeConstraint ? "yes" : "no")")
            }
            let signature = (0..<f.count).map { "\(f[$0].id):\(f[$0].phase)" }
            if raw || signature != lastSignature {
                print(String(format: "%9.3f  seq %d  n=%d  ", pipeline.seconds(f.entryNanos), f.sequence, f.count) + describe(f))
                lastSignature = signature
            }
        case .output(let o, let entry, _):
            if o.press != nil || o.release != nil || o.scrollTicks != 0 {
                print(String(format: "%9.3f  → ", pipeline.seconds(entry)) + describe(o))
            }
        case .state(let tr, let entry, _):
            print(String(format: "%9.3f  state %@ → %@", pipeline.seconds(entry), tr.from.traceName, tr.to.traceName))
        default:
            break
        }
    }

    func summary() {
        let cost = Double(pipeline.flags.frameCostMaxNanos.load(ordering: .relaxed)) / 1000
        print("\n\(frames) frames, worst frame cost \(String(format: "%.0f", cost)) µs, ring drops \(pipeline.ring.dropped.load(ordering: .relaxed))")
    }
}
