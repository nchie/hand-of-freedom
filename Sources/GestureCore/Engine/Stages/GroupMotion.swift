/// Mean movement of a set of contacts this frame, over those touching in this and the previous frame.
/// A contact that just landed, just left or was swapped for another contributes nothing, so there is never a jump.
struct GroupMotion: BitwiseCopyable {
    var meanDeltaMM: SIMD2<Float> = .zero
    var commonCount: Int32 = 0
    var projected = false
    /// A member is touching but has shrunk well below its peak size, so this frame's movement is lift-off drift.
    var liftingOff = false

    /// With `projectAxis` (the spread is changing, so this may be a pinch), movement along the finger axis
    /// keeps only the part every finger shares: if all move the same way along it, the smallest of those
    /// movements; if any moves the other way or stays put, nothing. A pinch, symmetric or with one finger
    /// anchored, therefore never turns, while a fast swipe along the axis, whose fingers never move at
    /// exactly the same speed, keeps almost all of its movement. Movement across the axis is kept in full.
    static func compute(_ t: ContactTracker, ids: InlineArray<4, Int32>, count: Int32, projectAxis: SIMD2<Float>?,
                        liftOffRatio: Float) -> GroupMotion {
        var sum = SIMD2<Float>.zero
        var n: Int32 = 0
        var liftingOff = false
        var minAlong: Float = .infinity
        var allPositive = true
        var allNegative = true
        for k in 0..<Int(min(count, 4)) {
            guard let s = t.slot(id: ids[k]) else { continue }
            if s.isLiftingOff(ratio: liftOffRatio) { liftingOff = true }
            guard s.hasDelta else { continue }
            var d = s.deltaMM
            if let a = projectAxis {
                let along = dot(d, a)
                d -= along * a
                minAlong = min(minAlong, abs(along))
                if !(along > 0) { allPositive = false }
                if !(along < 0) { allNegative = false }
            }
            sum += d
            n += 1
        }
        var mean = n > 0 ? sum / Float(n) : .zero
        if let a = projectAxis, n > 0, allPositive || allNegative {
            mean += (allPositive ? minAlong : -minAlong) * a
        }
        return GroupMotion(meanDeltaMM: mean, commonCount: n, projected: projectAxis != nil,
                           liftingOff: liftingOff)
    }
}
