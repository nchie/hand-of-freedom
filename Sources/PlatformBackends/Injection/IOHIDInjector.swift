import CHIDInject
import Darwin
import GestureCore

/// Relative injection through IOHIDPostEvent, the way a real mouse reports. Deprecated since macOS 11
/// but the only non-entitled path a game in mouselook accepts without jumps: the game ignores the delta
/// fields of posted CGEvents and derives motion from cursor positions, and it warps its hidden cursor
/// during mouselook, so a position-based event that lands after a warp turns the camera by the distance
/// back to the warp target. The documented replacement, IOHIDUserDevice, needs a restricted entitlement.
public final class IOHIDInjector: Injector {
    public let name = "IOHIDPostEvent"
    private let heldButtons = HeldButtons()
    private let pid = Int64(getpid())

    public init() {}

    public func open() throws(InjectorError) {
        let rc = hid_open()
        if rc != 0 { throw .openFailed(rc) }
    }

    public func close() { hid_close() }

    public func buttonDown(_ b: MouseButton) -> Int32 {
        heldButtons.insert(b)
        return hid_post_button(Int32(b.rawValue), 1)
    }

    public func buttonUp(_ b: MouseButton) -> Int32 {
        guard heldButtons.remove(b) else { return 0 }
        return hid_post_button(Int32(b.rawValue), 0)
    }

    public func move(dx: Int32, dy: Int32, held: MouseButton?) -> Int32 {
        hid_post_move(dx, dy, held.map { Int32($0.rawValue) } ?? -1)
    }

    public func scroll(ticks: Int32) -> Int32 { hid_post_scroll(ticks) }

    public var held: ButtonMask { heldButtons.mask }

    public func isOwnEvent(_ identity: EventIdentity) -> Bool { identity.sourcePID == pid }
}
