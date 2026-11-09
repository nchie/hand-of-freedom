/// What the event tap needs to know about an event. The tap reduces each CGEvent to this.
public struct GateEvent: Sendable, Equatable, BitwiseCopyable {
    public var type: UInt32
    public var scrollPhase: Int64
    public var momentumPhase: Int64
    /// Posted by us, recognised by the injector.
    public var isOwn: Bool

    public init(type: UInt32, scrollPhase: Int64 = 0, momentumPhase: Int64 = 0, isOwn: Bool = false) {
        self.type = type
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.isOwn = isOwn
    }
}

public struct GateContext: Sendable, Equatable, BitwiseCopyable {
    public var targetActive: Bool
    public var swallowTrackpadScroll: Bool
    public var swallowGestureEvents: Bool
    /// The engine routed the current gesture to macOS scrolling (`GestureRoute.scroll`).
    public var passTrackpadScroll: Bool

    public init(targetActive: Bool, swallowTrackpadScroll: Bool = true, swallowGestureEvents: Bool = true,
                passTrackpadScroll: Bool = false) {
        self.targetActive = targetActive
        self.swallowTrackpadScroll = swallowTrackpadScroll
        self.swallowGestureEvents = swallowGestureEvents
        self.passTrackpadScroll = passTrackpadScroll
    }
}

public enum GateDecision: Sendable, Equatable { case pass, swallow }

/// Decides which system events to swallow so the trackpad's own scrolling and gestures do not reach
/// the game while we drive it. While not acting, everything passes.
public enum GatePolicy {
    public static let scrollWheel: UInt32 = 22

    /// rotate, beginGesture, endGesture, gesture, magnify, swipe, smartMagnify
    public static func isGestureType(_ type: UInt32) -> Bool {
        switch type {
        case 18, 19, 20, 29, 30, 31, 32: true
        default: false
        }
    }

    public static func decide(_ e: GateEvent, _ c: GateContext) -> GateDecision {
        if e.isOwn || !c.targetActive { return .pass }
        if e.type == scrollWheel {
            // Mouse wheels carry no phase; only the trackpad's scrolls are swallowed.
            if e.scrollPhase == 0 && e.momentumPhase == 0 { return .pass }
            return c.swallowTrackpadScroll && !c.passTrackpadScroll ? .swallow : .pass
        }
        if isGestureType(e.type) { return c.swallowGestureEvents ? .swallow : .pass }
        return .pass
    }
}

/// Follows the trackpad's scroll sequences for the gate, so a scroll it let through keeps its momentum
/// after the fingers lift, when the engine has already left its scrolling phase. A new sequence takes the
/// engine's routing when it begins; the engine usually decides before macOS starts scrolling, but if it
/// decides later the sequence still opens up. Confined to the tap thread.
public struct ScrollSequenceGate: Sendable {
    /// CGScrollPhase values.
    public static let began: Int64 = 1, mayBegin: Int64 = 128

    public private(set) var passing = false

    public init() {}

    public mutating func decide(_ e: GateEvent, _ c: GateContext) -> GateDecision {
        if e.type == GatePolicy.scrollWheel && !e.isOwn {
            if e.scrollPhase == Self.began || e.scrollPhase == Self.mayBegin {
                passing = c.passTrackpadScroll
            } else if c.passTrackpadScroll {
                passing = true
            }
        }
        var context = c
        if passing { context.passTrackpadScroll = true }
        return GatePolicy.decide(e, context)
    }
}
