/// One trackpad frame. Fixed size and heap-free so it can be built on the stack of the touch callback.
public struct TouchFrame: Sendable, BitwiseCopyable {
    public static let capacity = 16

    /// MultitouchSupport frame counter.
    public var sequence: Int32
    /// mach time at callback entry. The trace time base; never read by the engine.
    public var entryNanos: UInt64
    /// Device timestamp in seconds. Copied into traces; never read by the engine.
    public var deviceTimestamp: Double

    public private(set) var count: Int = 0
    /// More than `capacity` contacts were delivered; the extras were dropped.
    public private(set) var overflowed: Bool = false
    private var storage = InlineArray<16, Contact>(repeating: .zero)

    public init(sequence: Int32 = 0, entryNanos: UInt64 = 0, deviceTimestamp: Double = 0) {
        self.sequence = sequence
        self.entryNanos = entryNanos
        self.deviceTimestamp = deviceTimestamp
    }

    public mutating func append(_ contact: Contact) {
        guard count < Self.capacity else { overflowed = true; return }
        storage[count] = contact
        count += 1
    }

    public subscript(index: Int) -> Contact {
        precondition(index >= 0 && index < count, "contact index out of range")
        return storage[index]
    }
}
