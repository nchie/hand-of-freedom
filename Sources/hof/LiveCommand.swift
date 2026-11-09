import AppKit
import GestureCore
import PlatformBackends
import Runtime

/// `hof live`: the full pipeline driving the game from a terminal. Developer-only: it posts input under
/// the terminal's permissions, which is what the bundled app exists to avoid.
@MainActor
func liveCommand(_ options: Options) throws -> Never {
    let config = try options.engineConfig()
    let injector = IOHIDInjector()
    let core = try PipelineCore(config: config, injector: injector)
    var pipelineOptions = PipelineOptions()
    pipelineOptions.useTap = !options.has("--no-tap")
    var settings = Settings.firstRun()
    settings.primaryProfile.engine = config
    settings.actInAllApps = options.has("--any-app")
    let tap = EventTap(flags: core.flags.activation) { [injector] identity in injector.isOwnEvent(identity) }
    let controller = PipelineController(core: core, gate: tap, settings: settings, options: pipelineOptions)

    var file: TraceFile? = nil
    if let path = options.values["--record"] {
        file = try TraceFile(url: URL(fileURLWithPath: path), header: core.header(tool: "hof live", config: config))
        print("Recording to \(path)")
    }
    let console = LiveConsole(pipeline: core, file: file)
    controller.onEvent = { console.handle($0) }
    controller.onStatusChange = { console.status($0) }

    let missing = controller.permissions.snapshot.missing
    if !missing.isEmpty { print("This terminal is missing: \(missing.map(\.rawValue).joined(separator: ", ")). See hof permissions.") }
    try controller.start()
    print("Live: two fingers = right drag, three = left drag, pinch = zoom, \(settings.actInAllApps ? "in every app" : "while World of Warcraft is frontmost"). Ctrl-C to stop.")
    runUntilStopped(seconds: options.seconds) {
        controller.stop()
        file?.close()
        console.summary(gate: tap)
    }
}

final class LiveConsole: @unchecked Sendable {
    private let pipeline: Pipeline
    private let file: TraceFile?
    private var failures = 0
    private var wroteSys = false
    private var drags = 0
    private var ticks = 0
    private var lastStatusLine = ""
    private var lastStalled = false
    private var lastUnstable = false

    init(pipeline: Pipeline, file: TraceFile?) {
        self.pipeline = pipeline
        self.file = file
    }

    func handle(_ event: TraceEvent) {
        file?.write(event)
        switch event {
        case .frame:
            if !wroteSys, let t = pipeline.threadReport {
                wroteSys = true
                print("callback thread: QoS \(t.qos), precedence \(t.precedence), real-time policy \(t.timeConstraint ? "yes" : "no")")
                file?.write(TraceCodec.sysLine(qos: t.qos, precedence: t.precedence, timeConstraint: t.timeConstraint, tSeconds: 0))
            }
        case .state(let tr, _, _):
            if case .dragging(let b, let n) = tr.to { drags += 1; print("  \(b) drag with \(n) fingers") }
        case .output(let o, _, _):
            ticks += Int(o.scrollTicks)
        case .inject(let op, _, _, let rc, _, _):
            if rc != 0 {
                failures += 1
                if failures <= 5 { print("  injection failed: \(op) returned \(rc)") }
            }
        default:
            break
        }
    }

    /// Prints activation changes and faults as they happen.
    @MainActor func status(_ s: PipelineStatus) {
        let line: String
        if s.active {
            line = "▶ active (\(s.frontmost ?? "?") frontmost)"
        } else {
            let reasons = s.blockers.map { $0 == .targetNotFrontmost ? "\(s.frontmost ?? "nothing") frontmost" : "\($0)" }
            line = "⏸ inactive: \(reasons.joined(separator: ", "))"
        }
        if line != lastStatusLine { print(line); lastStatusLine = line }
        if s.touchStalled != lastStalled {
            print(s.touchStalled ? "  touch frames stalled mid-drag: button released" : "  touch frames resumed")
            lastStalled = s.touchStalled
        }
        if s.tapUnstable != lastUnstable {
            print(s.tapUnstable ? "  event gate unstable: macOS keeps disabling it (a revoked grant?)" : "  event gate stable again")
            lastUnstable = s.tapUnstable
        }
    }

    func summary(gate: any EventGate) {
        let cost = Double(pipeline.flags.frameCostMaxNanos.load(ordering: .relaxed)) / 1000
        print("""

        \(drags) drags, \(ticks) net scroll ticks, \(failures) injection failures
        worst frame cost \(String(format: "%.0f", cost)) µs, ring drops \(pipeline.ring.dropped.load(ordering: .relaxed))
        tap: \(gate.swallowed) events swallowed, re-enabled \(gate.reenables) times
        """)
    }
}
