/// Millimetres of finger travel to pixels, with the sub-pixel remainder carried so slow motion is not lost.
struct MotionMapper: BitwiseCopyable {
    var remainder: SIMD2<Float> = .zero

    mutating func reset() { remainder = .zero }

    mutating func map(deltaMM: SIMD2<Float>, cfg: PointerConfig) -> SIMD2<Int32> {
        var px = SIMD2<Float>(deltaMM.x, -deltaMM.y) * cfg.pxPerMM      // pad y up, screen y down
        if cfg.invertY { px.y = -px.y }
        let magnitude = length(px)
        if magnitude > cfg.maxStepPx && magnitude > 0 { px *= cfg.maxStepPx / magnitude }
        px += remainder
        let rounded = SIMD2<Float>(px.x.rounded(.toNearestOrEven), px.y.rounded(.toNearestOrEven))
        remainder = px - rounded
        return SIMD2<Int32>(Int32(rounded.x), Int32(rounded.y))
    }
}
