import CoreFoundation

/// The scroll-and-gesture gate as the controller sees it. `EventTap` is the one implementation.
public protocol EventGate: AnyObject, Sendable {
    var isInstalled: Bool { get }
    func install(on runLoop: CFRunLoop) throws(TapError)
    func uninstall()
    /// Re-enables the gate if the system disabled it. Called once a second on the tap thread.
    func checkEnabled()
    /// Times the system disabled the gate and it was turned back on, since install.
    var reenables: Int32 { get }
    var swallowed: Int64 { get }
}

extension EventTap: EventGate {
    public var reenables: Int32 { reenableCount.load(ordering: .relaxed) }
    public var swallowed: Int64 { swallowedCount.load(ordering: .relaxed) }
}
