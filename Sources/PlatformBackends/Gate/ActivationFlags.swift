import GestureCore
import Synchronization

/// The state the event tap and the hot thread share. Each field has one writer: activation and the
/// modifier mask are written on the main thread, `modifierFlags` by the tap thread, `scrollPassthrough` by
/// the hot thread, and the marker pair by the marker capture's queue.
public final class ActivationFlags: Sendable {
    public let targetActive = Atomic<Bool>(false)
    public let swallowTrackpadScroll = Atomic<Bool>(true)
    public let swallowGestureEvents = Atomic<Bool>(true)
    /// CGEventFlags bits that route a gesture to macOS scrolling while held. 0 means none.
    public let scrollModifierMask = Atomic<UInt64>(0)
    /// CGEventFlags of the keyboard's modifiers, from the gate's flagsChanged events.
    public let modifierFlags = Atomic<UInt64>(0)
    /// The engine is in its scrolling phase. Written by the hot thread, read by the gate.
    public let scrollPassthrough = Atomic<Bool>(false)
    /// What the game's marker says a gesture starting now should do: 0 nothing known, otherwise a
    /// `GestureRoute` raw value plus one. With `markerNanos`, the mach time it was read.
    public let markerRoute = Atomic<UInt8>(0)
    public let markerNanos = Atomic<UInt64>(0)

    /// Called by the marker capture for every frame it reads.
    public func setMarkerRoute(_ route: GestureRoute?, nanos: UInt64) {
        markerRoute.store(route.map { $0.rawValue + 1 } ?? 0, ordering: .relaxed)
        markerNanos.store(nanos, ordering: .releasing)
    }

    public init() {}
}
