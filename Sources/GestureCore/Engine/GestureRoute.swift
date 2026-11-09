/// Where a gesture that starts now goes. The engine samples it only before a gesture commits
/// (idle or armed); after that the gesture keeps its route until the fingers lift.
public enum GestureRoute: UInt8, Sendable, BitwiseCopyable {
    /// Turn and orbit drags and pinch zoom. The default.
    case drive = 0
    /// Leave the gesture to macOS: no drags and no zoom, and the gate lets the trackpad's own scrolling
    /// through, so the window under the pointer scrolls.
    case scroll = 1
    /// Do nothing at all: the pointer is over a game window that neither turns nor scrolls, where a press
    /// would click whatever is under it.
    case ignore = 2
}
