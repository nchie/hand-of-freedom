import GestureCore

public enum InjectOp: UInt8, Sendable, BitwiseCopyable {
    case buttonDown, buttonUp, move, scroll
}

/// What the hot thread pushes into the trace ring. Heap-free, copied by memcpy.
/// `entryNanos` is the entry time of the frame the event belongs to; `us` is microseconds after it.
public enum TraceEvent: Sendable, BitwiseCopyable {
    case frame(TouchFrame)
    case output(EngineOutput, entryNanos: UInt64, us: UInt32)
    case inject(InjectOp, button: MouseButton?, value: SIMD2<Int32>, rc: Int32, entryNanos: UInt64, us: UInt32)
    case state(EngineState.Transition, entryNanos: UInt64, us: UInt32)
    case flag(targetActive: Bool, entryNanos: UInt64)
    /// The route the next frames are processed with, when it changes.
    case route(GestureRoute, entryNanos: UInt64)
    case reset(ResetRequest, entryNanos: UInt64)
}

extension EngineState.Phase {
    public var traceName: String {
        switch self {
        case .idle: "idle"
        case .armed(let count): "armed(\(count))"
        case .dragging(let button, let members): "dragging(\(button),\(members))"
        case .suspended: "suspended"
        case .scrolling: "scrolling"
        case .ignoring: "ignoring"
        }
    }
}

extension GestureRoute {
    public var traceName: String {
        switch self {
        case .drive: "drive"
        case .scroll: "scroll"
        case .ignore: "ignore"
        }
    }

    public init(traceName: String) {
        self = switch traceName {
        case "scroll": .scroll
        case "ignore": .ignore
        default: .drive
        }
    }
}
