/// Zoom from the spread between two contacts, running alongside any drag.
///
/// A leaky baseline follows the spread while not engaged, so slow drift during a turn never zooms.
/// Engagement needs the spread to outrun the baseline by `deadBandMM`; after that every `mmPerTick`
/// of spread change is one scroll tick, until the spread holds still for `disengageFrames`.
struct PinchController: BitwiseCopyable {
    var hasPair = false
    var pairA: Int32 = 0
    var pairB: Int32 = 0
    var baselineMM: Float = 0
    var lastSpreadMM: Float = 0
    var accumulatorMM: Float = 0
    var engaged = false
    var quietFrames: Int32 = 0

    mutating func clear() { self = PinchController() }

    /// Returns the pair axis when the spread is changing, so the drag can drop motion along it.
    mutating func step(pair: PairGeometry?, cfg: ZoomConfig, targetActive: Bool, out: inout EngineOutput) -> SIMD2<Float>? {
        guard cfg.enabled, cfg.mmPerTick > 0, let p = pair else { clear(); return nil }

        if !hasPair || p.a != pairA || p.b != pairB {
            self = PinchController()
            hasPair = true
            pairA = p.a
            pairB = p.b
            baselineMM = p.spreadMM
            lastSpreadMM = p.spreadMM
            return nil
        }

        let delta = p.spreadMM - lastSpreadMM
        lastSpreadMM = p.spreadMM
        let moving = abs(delta) >= cfg.jitterFloorMM

        if !engaged {
            baselineMM += (p.spreadMM - baselineMM) * cfg.baselineLeak
            if abs(p.spreadMM - baselineMM) >= cfg.deadBandMM {
                engaged = true
                accumulatorMM = 0
                quietFrames = 0
            }
        } else {
            accumulatorMM += delta
            let ticks = Int32(accumulatorMM / cfg.mmPerTick)        // truncates toward zero
            if ticks != 0 {
                accumulatorMM -= Float(ticks) * cfg.mmPerTick
                if targetActive { out.scrollTicks &+= cfg.invert ? -ticks : ticks }
            }
            quietFrames = moving ? 0 : quietFrames + 1
            if quietFrames >= cfg.disengageFrames {
                engaged = false
                baselineMM = p.spreadMM
                accumulatorMM = 0
                quietFrames = 0
            }
        }
        return engaged || moving ? p.axis : nil
    }
}
