import Synchronization

/// Hands settings to the hot thread without ever blocking it.
///
/// The writer locks, copies and bumps a generation. The reader does one atomic load per frame; only when
/// the generation changed does it try the lock once, and if the writer holds it at that instant it keeps
/// its previous copy and retries next frame. Staleness is bounded by one frame.
public final class ConfigMailbox<Value: Sendable & BitwiseCopyable>: Sendable {
    private let generation = Atomic<UInt64>(0)
    private let storage: Mutex<Value>

    public init(_ initial: Value) {
        storage = Mutex(initial)
    }

    /// Writer side, any thread except the hot one.
    public func publish(_ value: Value) {
        storage.withLock { stored in
            stored = value
            generation.add(1, ordering: .releasing)
        }
    }

    /// Reader side, the hot thread. Returns true when `local` was updated.
    @inline(__always)
    public func refresh(into local: inout Value, seen: inout UInt64) -> Bool {
        let current = generation.load(ordering: .acquiring)
        guard current != seen else { return false }
        guard let value = storage.withLockIfAvailable({ $0 }) else { return false }
        local = value
        seen = current
        return true
    }
}
