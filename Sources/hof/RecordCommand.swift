import Foundation
import GestureCore
import PlatformBackends
import Runtime

/// `hof record out.hoftrace.jsonl`: writes a trace of raw frames and engine decisions. Posts nothing.
@MainActor
func recordCommand(_ options: Options) throws -> Never {
    guard let path = options.positional.first else { throw CLIError("usage: hof record [--guided | --seconds N] [--inactive] [--config file] out.hoftrace.jsonl") }
    let config = try options.engineConfig()
    let pipeline = try Pipeline(config: config, injector: NullInjector())
    pipeline.flags.activation.targetActive.store(!options.has("--inactive"), ordering: .releasing)
    let file = try TraceFile(url: URL(fileURLWithPath: path), header: pipeline.header(tool: "hof record", config: config))
    let recorder = Recorder(pipeline: pipeline, file: file)
    try pipeline.start { recorder.handle($0) }
    var seconds = options.seconds
    if options.has("--guided") {
        seconds = GuidedSession.start(pipeline: pipeline, file: file)
    } else {
        print("Recording to \(path)\(options.seconds.map { " for \(Int($0)) s" } ?? ""). Ctrl-C to stop.")
    }
    runUntilStopped(seconds: seconds) {
        pipeline.stop()
        pipeline.injector.releaseAll()
        file.close()
        print("\nWrote \(recorder.frames) frames to \(path). Inspect with: hof replay --stats \(path)")
    }
}

final class Recorder: @unchecked Sendable {
    private let pipeline: Pipeline
    private let file: TraceFile
    private(set) var frames = 0
    private var wroteSys = false

    init(pipeline: Pipeline, file: TraceFile) {
        self.pipeline = pipeline
        self.file = file
    }

    func handle(_ event: TraceEvent) {
        file.write(event)
        if case .frame = event {
            frames += 1
            if !wroteSys, let t = pipeline.threadReport {
                wroteSys = true
                file.write(TraceCodec.sysLine(qos: t.qos, precedence: t.precedence, timeConstraint: t.timeConstraint, tSeconds: 0))
            }
            if frames % 600 == 0 { print("  \(frames) frames") }
        }
    }
}

/// Prompts through a calibration set of gestures and marks each one in the trace with a note.
enum GuidedSession {
    static let steps: [(prompt: String, seconds: Double)] = [
        ("Hands off the trackpad.", 3),
        ("Two-finger TAPS: tap with two fingers a few times.", 7),
        ("Two-finger SWIPES: swipe in all directions, lifting between swipes.", 10),
        ("Three-finger SWIPES: swipe in all directions, lifting between swipes.", 10),
        ("PINCH: pinch in and out with two fingers, a few times.", 10),
        ("THUMB: rest your thumb on the bottom edge, then swipe with two other fingers.", 10),
        ("PALM: rest your palm on the trackpad the way you do when typing, and move one finger.", 8),
        ("LIFT ONE BY ONE: swipe with three fingers and lift them one at a time.", 8),
        ("Hands off again.", 3),
    ]

    /// Schedules the prompts on the main queue and returns the total duration.
    @MainActor
    static func start(pipeline: Pipeline, file: TraceFile) -> Double {
        print("Guided recording, about \(Int(steps.reduce(0) { $0 + $1.seconds })) seconds. Follow each prompt until the next one appears.\n")
        var at = 0.0
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                print("[\(index + 1)/\(steps.count)] \(step.prompt)")
                let t = pipeline.seconds(MachTime.nowNanos())
                pipeline.writerQueue?.async { file.write(TraceCodec.noteLine(step.prompt, tSeconds: t)) }
            }
            at += step.seconds
        }
        return at
    }
}
