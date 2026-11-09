import Foundation
import GestureCore
import PlatformBackends
import Runtime

typealias Pipeline = PipelineCore

/// Runs the main run loop until Ctrl-C, SIGTERM or the optional deadline, then calls `shutdown` once.
@MainActor
func runUntilStopped(seconds: Double?, shutdown: @escaping @MainActor () -> Void) -> Never {
    var done = false
    let finish: @MainActor () -> Void = {
        guard !done else { return }
        done = true
        shutdown()
        exit(0)
    }
    var sources: [DispatchSourceSignal] = []
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        s.setEventHandler { MainActor.assumeIsolated { finish() } }
        s.resume()
        sources.append(s)
    }
    if let seconds {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { finish() } }
    }
    withExtendedLifetime(sources) { CFRunLoopRun() }
    exit(0)
}

func describe(_ f: TouchFrame) -> String {
    (0..<f.count).map { i in
        let c = f[i]
        return String(format: "#%d %@ (%.1f,%.1f)mm n(%.2f,%.2f) sz %.2f ax %.1f/%.1f",
                      c.id, "\(c.phase)", c.positionMM.x, c.positionMM.y, c.normalized.x, c.normalized.y,
                      c.size, c.majorAxisMM, c.minorAxisMM)
    }.joined(separator: "  ")
}

func describe(_ o: EngineOutput) -> String {
    var parts: [String] = []
    if let b = o.release { parts.append("release \(b)") }
    if let b = o.press { parts.append("press \(b)") }
    if o.movePx != .zero { parts.append("move (\(o.movePx.x),\(o.movePx.y))\(o.held.map { " holding \($0)" } ?? "")") }
    if o.scrollTicks != 0 { parts.append("scroll \(o.scrollTicks)") }
    return parts.joined(separator: ", ")
}
