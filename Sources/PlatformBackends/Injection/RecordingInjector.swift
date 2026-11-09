import Darwin
import GestureCore
import Synchronization

public enum InjectorCall: Sendable, Equatable {
    case buttonDown(MouseButton)
    case buttonUp(MouseButton)
    case move(Int32, Int32, held: MouseButton?)
    case scroll(Int32)
}

/// Records every call and the thread it came from. For ordering and thread-affinity tests.
public final class RecordingInjector: Injector {
    public struct Record: Sendable, Equatable {
        public var call: InjectorCall
        public var thread: UInt64
    }

    public let name = "recording"
    private let heldButtons = HeldButtons()
    private let records: Mutex<[Record]>

    public init(capacity: Int = 10_000) {
        var initial: [Record] = []
        initial.reserveCapacity(capacity)
        records = Mutex(initial)
    }

    public var calls: [Record] { records.withLock { $0 } }

    private func log(_ call: InjectorCall) {
        var tid: UInt64 = 0
        pthread_threadid_np(nil, &tid)
        records.withLock { $0.append(Record(call: call, thread: tid)) }
    }

    public func open() throws(InjectorError) {}
    public func close() {}

    public func buttonDown(_ b: MouseButton) -> Int32 {
        heldButtons.insert(b)
        log(.buttonDown(b))
        return 0
    }

    public func buttonUp(_ b: MouseButton) -> Int32 {
        guard heldButtons.remove(b) else { return 0 }
        log(.buttonUp(b))
        return 0
    }

    public func move(dx: Int32, dy: Int32, held: MouseButton?) -> Int32 { log(.move(dx, dy, held: held)); return 0 }
    public func scroll(ticks: Int32) -> Int32 { log(.scroll(ticks)); return 0 }
    public var held: ButtonMask { heldButtons.mask }
    public func isOwnEvent(_ identity: EventIdentity) -> Bool { false }
}
