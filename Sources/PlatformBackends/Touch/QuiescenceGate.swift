import Darwin
import Synchronization

/// Lets `stop()` wait until no frame callback is running, without a lock on the callback path.
///
/// Dekker pattern, both flags sequentially consistent. Callback: set `inCallback`, then check `stopped`.
/// Stop: set `stopped`, then wait while `inCallback`. Either the callback sees `stopped` and drops the
/// frame, or `close` sees `inCallback` and waits for it.
public final class QuiescenceGate: Sendable {
    private let inCallback = Atomic<Bool>(false)
    private let stopped = Atomic<Bool>(true)

    public init() {}

    /// Callback side. When this returns true the caller must call `exit()`.
    @inline(__always) public func enter() -> Bool {
        inCallback.store(true, ordering: .sequentiallyConsistent)
        if stopped.load(ordering: .sequentiallyConsistent) {
            inCallback.store(false, ordering: .sequentiallyConsistent)
            return false
        }
        return true
    }

    @inline(__always) public func exit() {
        inCallback.store(false, ordering: .sequentiallyConsistent)
    }

    public func open() {
        stopped.store(false, ordering: .sequentiallyConsistent)
    }

    /// Returns false if a callback was still running after `timeoutNanos`.
    @discardableResult
    public func close(timeoutNanos: UInt64 = 50_000_000) -> Bool {
        stopped.store(true, ordering: .sequentiallyConsistent)
        let deadline = MachTime.nowNanos() + timeoutNanos
        while inCallback.load(ordering: .sequentiallyConsistent) {
            if MachTime.nowNanos() > deadline { return false }
            sched_yield()
        }
        return true
    }
}
