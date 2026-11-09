import Synchronization

/// Wait-free single-producer single-consumer ring. The hot thread pushes, one consumer pops.
/// A full ring drops and counts instead of blocking.
public final class SPSCRing<Element: BitwiseCopyable>: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<Element>
    private let mask: Int
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)
    public let dropped = Atomic<Int32>(0)

    public init(capacityPowerOfTwo capacity: Int) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0, "capacity must be a power of two")
        buffer = .allocate(capacity: capacity)
        mask = capacity - 1
    }

    deinit { buffer.deallocate() }

    public var capacity: Int { mask + 1 }

    @inline(__always) @discardableResult
    public func tryPush(_ element: Element) -> Bool {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        if h - t > mask {
            dropped.add(1, ordering: .relaxed)
            return false
        }
        (buffer + (h & mask)).initialize(to: element)
        head.store(h + 1, ordering: .releasing)
        return true
    }

    public func pop() -> Element? {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        guard t != h else { return nil }
        let element = buffer[t & mask]
        tail.store(t + 1, ordering: .releasing)
        return element
    }
}
