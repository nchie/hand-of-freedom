/// Counts consecutive failed posts on the trace writer's queue, so the main actor hears only about changes.
public struct PostFailureCounter: Sendable, Equatable {
    /// Consecutive failed posts that mark the injector dead.
    public static let limit = 3
    public private(set) var consecutive = 0
    public private(set) var failing = false

    public init() {}

    /// One posted event's return code. Returns the new failing state when it changed.
    public mutating func record(rc: Int32) -> Bool? {
        consecutive = rc == 0 ? 0 : consecutive + 1
        let now = consecutive >= Self.limit
        guard now != failing else { return nil }
        failing = now
        return now
    }
}

/// Whether mouse input can be sent: the injector opened and its posts are not failing. Pure: kept on the main actor.
public struct InjectorHealth: Sendable, Equatable {
    public var openFailed = false
    public var postsFailing = false

    public init() {}

    public var isHealthy: Bool { !openFailed && !postsFailing }
}

/// Watches how often the system disables the event gate. A storm usually means a grant was revoked.
public struct TapHealth: Sendable, Equatable {
    public var limit = 5
    public var windowNanos: UInt64 = 60_000_000_000
    private var lastCount: Int32 = 0
    private var reenables: [UInt64] = []

    public init() {}

    /// More than `limit` re-enables in the last `windowNanos`.
    public var isUnstable: Bool { reenables.count > limit }

    /// Feed the tap's running re-enable count. Returns true when stability changed.
    public mutating func sample(reenableCount: Int32, nowNanos: UInt64) -> Bool {
        let before = isUnstable
        let new = max(0, Int(reenableCount &- lastCount))
        lastCount = reenableCount
        reenables.append(contentsOf: repeatElement(nowNanos, count: new))
        reenables.removeAll { nowNanos &- $0 > windowNanos }
        return isUnstable != before
    }
}
