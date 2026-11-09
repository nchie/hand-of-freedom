/// Everything the engine wants done this frame. Applied in fixed order: release, press, move, scroll.
public struct EngineOutput: Sendable, Equatable, BitwiseCopyable {
    public var release: MouseButton? = nil
    public var press: MouseButton? = nil
    /// The button `movePx` is a drag of. nil means a plain move.
    public var held: MouseButton? = nil
    public var movePx: SIMD2<Int32> = .zero
    public var scrollTicks: Int32 = 0
    public var transition: EngineState.Transition? = nil

    public init() {}

    public static let none = EngineOutput()

    public var isEmpty: Bool { release == nil && press == nil && movePx == .zero && scrollTicks == 0 }

    /// Combines an abort with the same frame's processing. `self` happens first.
    public mutating func merge(_ later: EngineOutput) {
        if release == nil { release = later.release }
        if press == nil { press = later.press }
        held = later.held
        movePx &+= later.movePx
        scrollTicks &+= later.scrollTicks
        switch (transition, later.transition) {
        case (nil, let t): transition = t
        case (let a?, let b?): transition = .init(from: a.from, to: b.to)
        case (_?, nil): break
        }
    }
}
