/// The two contacts a pinch is measured between, ids in ascending order.
struct PairGeometry: BitwiseCopyable {
    var a: Int32
    var b: Int32
    var spreadMM: Float
    /// Unit vector from the first contact to the second.
    var axis: SIMD2<Float>

    /// The two members of a two-finger drag, or otherwise exactly two touching fingers or thumb candidates.
    static func select(_ t: ContactTracker, members: DragMembers?) -> PairGeometry? {
        if let m = members {
            guard m.count == 2,
                  let x = t.slot(id: m.ids[0]), x.isTouchingNow,
                  let y = t.slot(id: m.ids[1]), y.isTouchingNow else { return nil }
            return make(x, y)
        }
        var first: TrackedContact? = nil
        var second: TrackedContact? = nil
        var n = 0
        for i in 0..<t.count {
            let s = t.slots[i]
            guard s.isTouchingNow, s.role == .finger || s.role == .thumbCandidate else { continue }
            n += 1
            if n == 1 { first = s } else if n == 2 { second = s }
        }
        guard n == 2, let x = first, let y = second else { return nil }
        return make(x, y)
    }

    private static func make(_ x: TrackedContact, _ y: TrackedContact) -> PairGeometry {
        let (p, q) = x.id < y.id ? (x, y) : (y, x)
        let d = q.last.positionMM - p.last.positionMM
        let spread = length(d)
        let axis = spread > 0.001 ? d / spread : SIMD2<Float>(1, 0)
        return PairGeometry(a: p.id, b: q.id, spreadMM: spread, axis: axis)
    }
}
