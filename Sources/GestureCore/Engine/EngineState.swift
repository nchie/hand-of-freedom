public struct EngineState: Sendable, Equatable, BitwiseCopyable {
    public enum Phase: Sendable, Equatable, BitwiseCopyable {
        case idle
        case armed(count: Int32)
        case dragging(MouseButton, members: Int32)
        /// Aborted or ended by a lift. Refuses to arm until no finger is on the pad.
        case suspended
        /// A gesture routed to macOS scrolling. Ends when the last finger lifts.
        case scrolling
        /// A gesture routed nowhere: nothing is pressed, moved, zoomed or scrolled. Ends when the last finger lifts.
        case ignoring

        public var isDragging: Bool {
            switch self {
            case .dragging: true
            default: false
            }
        }
    }

    public struct Transition: Sendable, Equatable, BitwiseCopyable {
        public var from: Phase
        public var to: Phase
        public init(from: Phase, to: Phase) { self.from = from; self.to = to }
    }

    public var phase: Phase = .idle
    /// Fingers that count after palm and thumb rejection.
    public var countedFingers: Int32 = 0
    /// Contacts in the touching phase, any role.
    public var rawTouching: Int32 = 0
    public var zoomEngaged = false

    public init() {}

    /// Single-word encoding for an atomic the UI can poll.
    /// Bits: 0-1 phase, 2-3 button, 4-8 armed or member count, 9-13 counted, 14-18 raw, 19 zoom, 20 scrolling, 21 ignoring.
    public var packed: UInt64 {
        func five(_ v: Int32) -> UInt64 { UInt64(max(0, min(31, v))) }
        var v: UInt64 = 0
        switch phase {
        case .idle: break
        case .armed(let count): v |= 1 | five(count) << 4
        case .dragging(let button, let members): v |= 2 | UInt64(button.rawValue) << 2 | five(members) << 4
        case .suspended: v |= 3
        case .scrolling: v |= 1 << 20
        case .ignoring: v |= 1 << 21
        }
        v |= five(countedFingers) << 9
        v |= five(rawTouching) << 14
        if zoomEngaged { v |= 1 << 19 }
        return v
    }

    public init(packed v: UInt64) {
        let count = Int32((v >> 4) & 31)
        switch v & 3 {
        case 1: phase = .armed(count: count)
        case 2: phase = .dragging(MouseButton(rawValue: UInt8((v >> 2) & 3)) ?? .left, members: count)
        case 3: phase = .suspended
        default: phase = (v >> 20) & 1 == 1 ? .scrolling : (v >> 21) & 1 == 1 ? .ignoring : .idle
        }
        countedFingers = Int32((v >> 9) & 31)
        rawTouching = Int32((v >> 14) & 31)
        zoomEngaged = (v >> 19) & 1 == 1
    }
}
