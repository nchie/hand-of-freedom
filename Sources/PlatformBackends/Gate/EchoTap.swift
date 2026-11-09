import CoreGraphics
import Synchronization

/// Hears pointer moves, reduced to their identity. The injector probe's ear.
public protocol EchoListener: AnyObject, Sendable {
    /// `onEvent` is called on the listener's thread for every pointer move until `stop`.
    func start(onEvent: @escaping @Sendable (EventIdentity) -> Void) throws(TapError)
    func stop()
}

/// A short-lived listen-only session tap for pointer moves, hosted on the tap thread's run loop.
/// It never changes an event and exists only while a probe runs.
/// Needs Input Monitoring. Without it, creation still succeeds but no event arrives (measured in
/// measured), so callers must check `CGPreflightListenEventAccess` first.
public final class MoveEchoTap: EchoListener, @unchecked Sendable {
    private let runLoop: CFRunLoop
    private let handler = Mutex<(@Sendable (EventIdentity) -> Void)?>(nil)
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    public init(runLoop: CFRunLoop) {
        self.runLoop = runLoop
    }

    public func start(onEvent: @escaping @Sendable (EventIdentity) -> Void) throws(TapError) {
        stop()
        handler.withLock { $0 = onEvent }
        let mask: CGEventMask = 1 << CGEventType.mouseMoved.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                           eventsOfInterest: mask, callback: echoTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            handler.withLock { $0 = nil }
            throw CGPreflightListenEventAccess() ? .creationFailed : .notPermitted
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.port = port
        self.source = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        CFRunLoopWakeUp(runLoop)
    }

    public func stop() {
        handler.withLock { $0 = nil }
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
        port = nil
        source = nil
    }

    fileprivate func handle(_ event: CGEvent) {
        let identity = EventIdentity(sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
                                     sourceUserData: event.getIntegerValueField(.eventSourceUserData))
        handler.withLock { $0 }?(identity)
    }
}

private func echoTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                             refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .mouseMoved, let refcon {
        Unmanaged<MoveEchoTap>.fromOpaque(refcon).takeUnretainedValue().handle(event)
    }
    return Unmanaged.passUnretained(event)
}
