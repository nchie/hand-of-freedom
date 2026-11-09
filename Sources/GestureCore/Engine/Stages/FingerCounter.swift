struct FingerCount: BitwiseCopyable {
    var rawTouching: Int32 = 0
    /// Touching contacts with the finger role.
    var counted: Int32 = 0
    /// The first four counted fingers, in first-seen order.
    var ids = InlineArray<4, Int32>(repeating: 0)
    /// While dragging: every member is touching or within its dropout grace.
    var membersAlive = true
    /// While dragging: a member ended by a real lift, not a dropout.
    var memberLifted = false
    /// Contacts approaching the pad that have never touched, seen for at most `landingLookaheadFrames`.
    var approaching: Int32 = 0
}

/// Counts fingers. Idle counting has no delay. While dragging, a member survives a dropout of up to
/// `ghostFrames` frames, even a fully empty frame, but dies on the frame it reports a lift phase.
enum FingerCounter {
    static func count(_ t: ContactTracker, members: DragMembers?, ghostFrames: Int32, lookahead: Int32) -> FingerCount {
        var fc = FingerCount()
        for i in 0..<t.count {
            let s = t.slots[i]
            if s.isApproaching(within: lookahead) { fc.approaching += 1 }
            guard s.isTouchingNow else { continue }
            fc.rawTouching += 1
            if s.role == .finger {
                if fc.counted < 4 { fc.ids[Int(fc.counted)] = s.id }
                fc.counted += 1
            }
        }

        if let m = members {
            for k in 0..<Int(m.count) {
                guard let s = t.slot(id: m.ids[k]) else { fc.membersAlive = false; continue }   // evicted: dropout too long
                if s.role == .palm { fc.membersAlive = false; continue }
                if s.lifted { fc.membersAlive = false; fc.memberLifted = true; continue }
                if !s.isTouchingNow && s.framesNotTouching > ghostFrames { fc.membersAlive = false }
            }
        }
        return fc
    }
}
