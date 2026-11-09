/// Lifecycle of a contact as MultitouchSupport reports it (`MTTouch.state`).
/// `touching` (4) is the only phase that counts as a finger on the pad.
/// `breaking`, `lingering` and `leaving` (5, 6, 7) announce a real lift.
public enum ContactPhase: UInt8, Sendable, Codable, CaseIterable, BitwiseCopyable {
    case notTracking = 0, starting, hovering, making, touching, breaking, lingering, leaving

    public var isLifting: Bool { self == .breaking || self == .lingering || self == .leaving }
}

/// One contact in one frame. Positions are physical millimetres, origin bottom-left, y up.
public struct Contact: Sendable, Equatable, BitwiseCopyable {
    public var id: Int32
    public var phase: ContactPhase
    public var positionMM: SIMD2<Float>
    public var velocityMM: SIMD2<Float>
    public var normalized: SIMD2<Float>
    public var size: Float
    public var majorAxisMM: Float
    public var minorAxisMM: Float
    public var angle: Float

    public init(id: Int32, phase: ContactPhase, positionMM: SIMD2<Float>, velocityMM: SIMD2<Float> = .zero,
                normalized: SIMD2<Float>, size: Float, majorAxisMM: Float, minorAxisMM: Float, angle: Float = 0) {
        self.id = id
        self.phase = phase
        self.positionMM = positionMM
        self.velocityMM = velocityMM
        self.normalized = normalized
        self.size = size
        self.majorAxisMM = majorAxisMM
        self.minorAxisMM = minorAxisMM
        self.angle = angle
    }

    public static let zero = Contact(id: 0, phase: .notTracking, positionMM: .zero, normalized: .zero,
                                     size: 0, majorAxisMM: 0, minorAxisMM: 0)

    public var isTouching: Bool { phase == .touching }
    public var isLifting: Bool { phase.isLifting }
}
