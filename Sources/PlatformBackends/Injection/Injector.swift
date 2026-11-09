import GestureCore
import Synchronization

public enum InjectorError: Error, Sendable, Equatable {
    case openFailed(Int32)
    case notPermitted
    case unavailable
}

public struct ButtonMask: Sendable, Equatable, BitwiseCopyable {
    public var raw: UInt8
    public init(raw: UInt8) { self.raw = raw }
    public func contains(_ b: MouseButton) -> Bool { raw & (1 << b.rawValue) != 0 }
}

/// The seam in front of the OS input injection API. One implementation today (IOHIDPostEvent);
/// a virtual HID device backend would be another.
public protocol Injector: AnyObject, Sendable {
    var name: String { get }
    func open() throws(InjectorError)
    func close()
    // Hot path: synchronous, non-blocking, non-allocating. Return the backend's raw status, 0 = ok.
    @discardableResult func buttonDown(_ b: MouseButton) -> Int32
    /// Idempotent: posts only if the button is held.
    @discardableResult func buttonUp(_ b: MouseButton) -> Int32
    @discardableResult func move(dx: Int32, dy: Int32, held: MouseButton?) -> Int32
    @discardableResult func scroll(ticks: Int32) -> Int32
    // Any thread.
    var held: ButtonMask { get }
    func releaseAll()
    func isOwnEvent(_ identity: EventIdentity) -> Bool
}

/// Which buttons are down, shared by every thread that may release them. Whichever thread clears a
/// bit first posts the release; the other is a no-op.
public final class HeldButtons: Sendable {
    private let bits = Atomic<UInt8>(0)

    public init() {}

    public var mask: ButtonMask { ButtonMask(raw: bits.load(ordering: .acquiring)) }

    public func insert(_ b: MouseButton) {
        bits.bitwiseOr(1 << b.rawValue, ordering: .acquiringAndReleasing)
    }

    /// True if the button was held, so the caller should post the release.
    public func remove(_ b: MouseButton) -> Bool {
        let bit: UInt8 = 1 << b.rawValue
        return bits.bitwiseAnd(~bit, ordering: .acquiringAndReleasing).oldValue & bit != 0
    }
}

extension Injector {
    public func releaseAll() {
        for b in MouseButton.allCases where held.contains(b) { buttonUp(b) }
    }
}
