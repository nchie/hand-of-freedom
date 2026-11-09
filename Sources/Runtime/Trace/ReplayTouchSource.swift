import Foundation
import GestureCore
import PlatformBackends

/// Delivers recorded or scripted frames to a sink on its own thread, with the same stop guarantee as
/// the real source. For tests and replays through the full hot loop.
public final class ReplayTouchSource: TouchSource, @unchecked Sendable {
    public let devices: [TouchDeviceInfo] = []
    private let frames: [TouchFrame]
    private let intervalNanos: UInt64
    private let gate = QuiescenceGate()
    private var sink: (any TouchFrameSink)?
    private let finished = DispatchSemaphore(value: 0)

    public init(frames: [TouchFrame], intervalNanos: UInt64 = 0) {
        self.frames = frames
        self.intervalNanos = intervalNanos
    }

    public func start(sink: any TouchFrameSink) throws(TouchSourceError) {
        if self.sink == nil { self.sink = sink }
        gate.open()
        let frames = self.frames, interval = self.intervalNanos, gate = self.gate, finished = self.finished
        let thread = Thread {
            for frame in frames {
                guard gate.enter() else { break }
                sink.handle(frame)
                gate.exit()
                if interval > 0 { usleep(useconds_t(interval / 1000)) }
            }
            finished.signal()
        }
        thread.name = "hof.replay"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func stop() { gate.close() }

    public func restart() throws(TouchSourceError) {
        stop()
        guard let sink else { return }
        try start(sink: sink)
    }

    /// Blocks until every frame was delivered or the source stopped.
    public func waitUntilFinished(timeout: DispatchTime = .distantFuture) -> Bool {
        finished.wait(timeout: timeout) == .success
    }
}
