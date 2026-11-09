import ApplicationServices
import CoreGraphics
import GestureCore
import Synchronization

public enum TapError: Error, Sendable, Equatable {
    case notPermitted
    case creationFailed
}

/// A HID-level event tap that swallows the trackpad's own scrolls and gestures while we drive the game,
/// and lets the scrolls through for a gesture the engine routed to macOS. It also watches the modifier
/// keys, which pick that route. The callback reads and writes atomics and runs the injector's identity
/// check, nothing else.
public final class EventTap: @unchecked Sendable {
    public let reenableCount = Atomic<Int32>(0)
    public let swallowedCount = Atomic<Int64>(0)
    private let installed = Atomic<Bool>(false)
    private let flags: ActivationFlags
    private let isOwn: @Sendable (EventIdentity) -> Bool
    // Written before the tap's run loop source is added, then read on the tap thread.
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    /// Touched only on the tap thread.
    private var sequence = ScrollSequenceGate()

    public init(flags: ActivationFlags, isOwn: @escaping @Sendable (EventIdentity) -> Bool) {
        self.flags = flags
        self.isOwn = isOwn
    }

    public var isInstalled: Bool { installed.load(ordering: .acquiring) }

    public func install(on runLoop: CFRunLoop) throws(TapError) {
        guard !isInstalled else { return }
        var mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue | 1 << CGEventType.flagsChanged.rawValue
        for type: UInt32 in [18, 19, 20, 29, 30, 31, 32] { mask |= 1 << CGEventMask(type) }   // gesture family
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: eventTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            // Measured: a modifying HID tap needs Accessibility; Input Monitoring is irrelevant to it.
            throw AXIsProcessTrusted() ? .creationFailed : .notPermitted
        }
        self.port = port
        self.runLoop = runLoop
        // Keys already held when the tap starts send no flagsChanged until they change.
        flags.modifierFlags.store(CGEventSource.flagsState(.combinedSessionState).rawValue, ordering: .relaxed)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        installed.store(true, ordering: .releasing)
    }

    public func uninstall() {
        guard isInstalled else { return }
        installed.store(false, ordering: .releasing)
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source, let runLoop { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
        port = nil
        source = nil
    }

    /// Re-enables a tap the system disabled. Called from a timer on the tap thread.
    public func checkEnabled() {
        guard isInstalled, let port, !CGEvent.tapIsEnabled(tap: port) else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        reenableCount.add(1, ordering: .relaxed)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            reenableCount.add(1, ordering: .relaxed)
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            flags.modifierFlags.store(event.flags.rawValue, ordering: .relaxed)
            return Unmanaged.passUnretained(event)
        }
        let identity = EventIdentity(sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
                                     sourceUserData: event.getIntegerValueField(.eventSourceUserData))
        let isScroll = type == .scrollWheel
        let gateEvent = GateEvent(type: type.rawValue,
                                  scrollPhase: isScroll ? event.getIntegerValueField(.scrollWheelEventScrollPhase) : 0,
                                  momentumPhase: isScroll ? event.getIntegerValueField(.scrollWheelEventMomentumPhase) : 0,
                                  isOwn: isOwn(identity))
        let context = GateContext(targetActive: flags.targetActive.load(ordering: .acquiring),
                                  swallowTrackpadScroll: flags.swallowTrackpadScroll.load(ordering: .relaxed),
                                  swallowGestureEvents: flags.swallowGestureEvents.load(ordering: .relaxed),
                                  passTrackpadScroll: flags.scrollPassthrough.load(ordering: .acquiring))
        if sequence.decide(gateEvent, context) == .swallow {
            swallowedCount.add(1, ordering: .relaxed)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}
