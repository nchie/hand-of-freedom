import GestureCore

/// Scripts synthetic trackpad sessions. Positions are millimetres on a 150 x 95 mm pad, origin bottom-left.
/// A landing finger reports `making` for one frame, then `touching`. A lift reports `breaking`, then
/// `leaving`, then disappears, which is the sequence MultitouchSupport is expected to report.
public struct FrameBuilder {
    public init() {}
    public static let padMM = SIMD2<Float>(150, 95)

    public enum Step {
        case frame(TouchFrame)
        case active(Bool)
        case config(EngineConfig)
        case route(GestureRoute)
        case abort
    }

    struct Finger {
        var id: Int32
        var pos: SIMD2<Float>
        var phase: ContactPhase
        var size: Float
        var dropout = 0
        var gone = false
    }

    public private(set) var steps: [Step] = []
    private var fingers: [Finger] = []
    private var sequence: Int32 = 0
    private var emptyRemaining = 0
    public private(set) var marks: [String: Int] = [:]

    /// Just the frames, in order.
    public var allFrames: [TouchFrame] {
        steps.compactMap { if case .frame(let f) = $0 { f } else { nil } }
    }

    /// The index of the next step, to look up its output after a run.
    public mutating func mark(_ name: String) { marks[name] = steps.count }

    public mutating func land(_ id: Int32, at p: (Float, Float), size: Float = 1.0) {
        fingers.append(Finger(id: id, pos: SIMD2(p.0, p.1), phase: .making, size: size))
    }

    /// A finger approaching the pad: reported as `phase` (starting or hovering) every frame until `touchDown`.
    public mutating func approach(_ id: Int32, at p: (Float, Float), phase: ContactPhase = .starting) {
        fingers.append(Finger(id: id, pos: SIMD2(p.0, p.1), phase: phase, size: 0.3))
    }

    /// An approaching finger lands: `making` for one frame, then `touching`.
    public mutating func touchDown(_ id: Int32, size: Float = 1.0) {
        for i in fingers.indices where fingers[i].id == id {
            fingers[i].phase = .making
            fingers[i].size = size
        }
    }

    public mutating func lift(_ id: Int32) {
        for i in fingers.indices where fingers[i].id == id { fingers[i].phase = .breaking }
    }

    /// Lifts every finger and emits frames until the pad is empty.
    public mutating func liftAll() {
        for i in fingers.indices { fingers[i].phase = .breaking }
        while !fingers.isEmpty { emit() }
    }

    public mutating func setSize(_ id: Int32, _ size: Float) {
        for i in fingers.indices where fingers[i].id == id { fingers[i].size = size }
    }

    /// The same physical finger gets a new identifier, as MultitouchSupport occasionally does.
    public mutating func swapID(_ id: Int32, to newID: Int32) {
        for i in fingers.indices where fingers[i].id == id { fingers[i].id = newID }
    }

    /// Omits a finger from the next `n` frames while it keeps moving.
    public mutating func dropout(_ id: Int32, frames n: Int) {
        for i in fingers.indices where fingers[i].id == id { fingers[i].dropout = n }
    }

    /// The next `n` frames carry no contacts at all.
    public mutating func emptyFrames(_ n: Int) {
        emptyRemaining = n
        frames(n)
    }

    public mutating func frames(_ n: Int = 1) {
        for _ in 0..<n { emit() }
    }

    public mutating func move(_ ids: [Int32], by d: (Float, Float), frames n: Int = 1) {
        for _ in 0..<n {
            for i in fingers.indices where ids.contains(fingers[i].id) { fingers[i].pos += SIMD2(d.0, d.1) }
            emit()
        }
    }

    /// Moves each listed finger by its own delta, every frame.
    public mutating func moveEach(_ moves: [Int32: (Float, Float)], frames n: Int = 1) {
        for _ in 0..<n {
            for i in fingers.indices {
                if let d = moves[fingers[i].id] { fingers[i].pos += SIMD2(d.0, d.1) }
            }
            emit()
        }
    }

    public mutating func moveAll(by d: (Float, Float), frames n: Int = 1) {
        move(fingers.map(\.id), by: d, frames: n)
    }

    public mutating func setActive(_ active: Bool) { steps.append(.active(active)) }
    public mutating func setConfig(_ config: EngineConfig) { steps.append(.config(config)) }
    public mutating func abort() { steps.append(.abort) }
    /// The route frames from here on are processed with, as if the scroll key was pressed or released.
    public mutating func setRoute(_ route: GestureRoute) { steps.append(.route(route)) }

    private mutating func emit() {
        sequence += 1
        var frame = TouchFrame(sequence: sequence, entryNanos: UInt64(sequence) * 8_333_333,
                               deviceTimestamp: Double(sequence) / 120)
        if emptyRemaining > 0 {
            emptyRemaining -= 1
        } else {
            for f in fingers where f.dropout == 0 {
                frame.append(Contact(id: f.id, phase: f.phase, positionMM: f.pos, normalized: f.pos / Self.padMM,
                                     size: f.size, majorAxisMM: f.size * 5, minorAxisMM: f.size * 4))
            }
        }
        steps.append(.frame(frame))

        for i in fingers.indices {
            if fingers[i].dropout > 0 { fingers[i].dropout -= 1 }
            switch fingers[i].phase {
            case .making: fingers[i].phase = .touching
            case .breaking: fingers[i].phase = .leaving
            case .leaving: fingers[i].gone = true
            default: break
            }
        }
        fingers.removeAll(where: \.gone)
    }

    public func run(config: EngineConfig = .default, active: Bool = true, timeScale: Double = 1) -> RunResult {
        var engine = GestureEngine()
        var cfg = config
        var isActive = active
        var route = GestureRoute.drive
        var result = RunResult()
        for step in steps {
            switch step {
            case .frame(var frame):
                frame.deviceTimestamp *= timeScale
                frame.entryNanos = UInt64(Double(frame.entryNanos) * timeScale)
                result.append(engine.process(frame, config: cfg, targetActive: isActive, route: route), engine.state.phase)
            case .active(let a):
                isActive = a
                result.append(.none, engine.state.phase)
            case .config(let c):
                cfg = c
                result.append(.none, engine.state.phase)
            case .route(let r):
                route = r
                result.append(.none, engine.state.phase)
            case .abort:
                result.append(engine.abort(), engine.state.phase)
            }
        }
        result.engine = engine
        return result
    }
}

/// One output and resulting phase per step.
public struct RunResult {
    public var outputs: [EngineOutput] = []
    public var phases: [EngineState.Phase] = []
    public var engine = GestureEngine()

    public init() {}

    public mutating func append(_ out: EngineOutput, _ phase: EngineState.Phase) {
        outputs.append(out)
        phases.append(phase)
    }

    public var presses: [MouseButton] { outputs.compactMap(\.press) }
    public var releases: [MouseButton] { outputs.compactMap(\.release) }

    /// Presses and releases in order, as "+right" / "-right".
    public var buttonEvents: [String] {
        outputs.flatMap { o -> [String] in
            var e: [String] = []
            if let r = o.release { e.append("-\(r)") }
            if let p = o.press { e.append("+\(p)") }
            return e
        }
    }

    public func totalMove(from start: Int = 0) -> SIMD2<Int32> {
        outputs[start...].reduce(.zero) { $0 &+ $1.movePx }
    }

    public func totalScroll(from start: Int = 0) -> Int32 {
        outputs[start...].reduce(0) { $0 + $1.scrollTicks }
    }

    public var maxStepPx: Float {
        outputs.map { o in
            let x = Float(o.movePx.x), y = Float(o.movePx.y)
            return (x * x + y * y).squareRoot()
        }.max() ?? 0
    }
}

extension EngineConfig {
    public func with(_ change: (inout EngineConfig) -> Void) -> EngineConfig {
        var c = self
        change(&c)
        return c
    }
}
