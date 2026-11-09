/// Per-stage intermediates from the last `process` call, for replay diagnostics and stage tests.
/// Always filled, never read by the engine itself.
public struct EngineTrace: Sendable, Equatable, BitwiseCopyable {
    public var countedFingers: Int32 = 0
    public var rawTouching: Int32 = 0
    /// Contacts approaching the pad within the landing lookahead.
    public var approaching: Int32 = 0
    public var meanDeltaMM: SIMD2<Float> = .zero
    /// Pinch motion along the finger axis was removed from the drag motion this frame.
    public var projected = false
    /// A counted finger was lifting off, so this frame added no drag-start travel.
    public var liftingOff = false
    public var armedTravelMM: Float = 0
    public var spreadMM: Float = 0
    public var pinchBaselineMM: Float = 0
    public var pinchAccumulatorMM: Float = 0
    public var pinchEngaged = false

    public init() {}
}

public enum ContactRole: UInt8, Sendable, Codable, BitwiseCopyable {
    case none = 0, finger, palm, thumbCandidate
}
