import GestureCore

/// Posts nothing. For logging, recording, replay and tests.
public final class NullInjector: Injector {
    public let name = "none"
    private let heldButtons = HeldButtons()

    public init() {}
    public func open() throws(InjectorError) {}
    public func close() {}
    public func buttonDown(_ b: MouseButton) -> Int32 { heldButtons.insert(b); return 0 }
    public func buttonUp(_ b: MouseButton) -> Int32 { _ = heldButtons.remove(b); return 0 }
    public func move(dx: Int32, dy: Int32, held: MouseButton?) -> Int32 { 0 }
    public func scroll(ticks: Int32) -> Int32 { 0 }
    public var held: ButtonMask { heldButtons.mask }
    public func isOwnEvent(_ identity: EventIdentity) -> Bool { false }
}
