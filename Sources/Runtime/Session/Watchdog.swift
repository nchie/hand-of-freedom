import Dispatch
import GestureCore
import PlatformBackends

/// Releases a held button when touch frames stop arriving mid-drag. Never restarts the source.
/// `onStall` and `onResume` run on the watchdog's queue: once per stall, and when frames arrive again.
public final class Watchdog: @unchecked Sendable {
    private let flags: SharedFlags
    private let hotLoop: HotLoop
    private let stallNanos: UInt64
    private let clock: @Sendable () -> UInt64
    private let onStall: @Sendable () -> Void
    private let onResume: @Sendable () -> Void
    private let queue = DispatchQueue(label: "hof.watchdog", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var lastSeen: UInt64 = 0
    private var handled = false

    public init(flags: SharedFlags, hotLoop: HotLoop, stallMilliseconds: UInt64 = 300,
                clock: @escaping @Sendable () -> UInt64 = { MachTime.nowNanos() },
                onStall: @escaping @Sendable () -> Void = {}, onResume: @escaping @Sendable () -> Void = {}) {
        self.flags = flags
        self.hotLoop = hotLoop
        self.stallNanos = stallMilliseconds * 1_000_000
        self.clock = clock
        self.onStall = onStall
        self.onResume = onResume
    }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        t.setEventHandler { [self] in tick() }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// One check. Public so tests can drive it with a fake clock.
    public func tick() {
        let last = flags.lastFrameNanos.load(ordering: .relaxed)
        if last != lastSeen {
            lastSeen = last
            if handled { onResume() }
            handled = false
            return
        }
        let state = EngineState(packed: flags.packedState.load(ordering: .acquiring))
        guard state.phase.isDragging, !handled, clock() &- last > stallNanos else { return }
        handled = true
        hotLoop.abortActiveDrag()
        onStall()
    }
}
