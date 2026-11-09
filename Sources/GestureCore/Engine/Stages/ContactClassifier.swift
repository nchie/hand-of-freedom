/// Palm and thumb rejection with sticky roles.
///
/// 1. Palm by shape, checked on every touching frame because palms land small, grow, and split into pieces that
///    start finger-sized. A drag member is only checked during its first `palmGrowthFrames`, so a long turn is
///    never ended by a finger pressing flatter.
/// 2. Thumb candidate by landing time and zone:
///    (a) a zone contact that lands alone while other contacts are already on the pad,
///    (b) a lone zone contact resting first, demoted when a later landing group arrives,
///    (c) zone contacts landing together with others are fingers,
///    (d) contacts outside the zone are always fingers.
/// 3. A candidate travelling at least `thumbPromoteTravelMM` in the same direction as the fingers becomes a finger, once.
///
/// Drag members keep their role, except that a member may still turn out to be a palm, which ends the drag.
enum ContactClassifier {
    static func classify(_ t: inout ContactTracker, members: DragMembers?, cfg: RejectionConfig) {
        markPalms(&t, members: members, cfg: cfg)
        classifyLandings(&t, members: members, cfg: cfg)
        promoteCandidates(&t, cfg: cfg)
    }

    private static func markPalms(_ t: inout ContactTracker, members: DragMembers?, cfg: RejectionConfig) {
        for i in 0..<t.count {
            let s = t.slots[i]
            guard s.isTouchingNow, s.role != .palm else { continue }
            if members?.contains(s.id) ?? false, s.framesTouching > cfg.palmGrowthFrames { continue }
            if s.last.size >= cfg.palmMinSize || s.last.majorAxisMM >= cfg.palmMinMajorAxisMM {
                t.slots[i].role = .palm
            }
        }
    }

    private static func classifyLandings(_ t: inout ContactTracker, members: DragMembers?, cfg: RejectionConfig) {
        let window = cfg.thumbLateLandingFrames
        for i in 0..<t.count {
            let c = t.slots[i]
            guard c.isTouchingNow, c.role == .none else { continue }

            var hasGroupMate = false
            var earlierCount = 0
            var earlierIndex = -1
            for k in 0..<t.count where k != i {
                let o = t.slots[k]
                guard o.isActive, o.role != .palm else { continue }
                if abs(o.landedAtFrame - c.landedAtFrame) <= window {
                    hasGroupMate = true
                } else if c.landedAtFrame - o.landedAtFrame > window {
                    earlierCount += 1
                    earlierIndex = k
                }
            }

            if !c.isZoneContact {
                t.slots[i].role = .finger                                     // (d)
            } else if hasGroupMate {
                t.slots[i].role = .finger                                     // (c)
            } else if earlierCount > 0 {
                becomeCandidate(&t.slots[i])                                  // (a)
            } else {
                t.slots[i].role = .finger                                     // first and alone: provisional finger
            }

            // (c) also rescues a candidate that turns out to have landed with this contact.
            for k in 0..<t.count where k != i {
                let o = t.slots[k]
                if o.role == .thumbCandidate, o.isActive, abs(o.landedAtFrame - c.landedAtFrame) <= window {
                    t.slots[k].role = .finger
                    t.slots[k].promoted = true
                }
            }

            // (b) the thumb that was resting first.
            if earlierCount == 1 {
                let e = t.slots[earlierIndex]
                let isMember = members?.contains(e.id) ?? false
                if e.isZoneContact, e.role == .finger, !e.promoted, !isMember,
                   e.travelMM < cfg.thumbPromoteTravelMM, !hasMate(t, of: earlierIndex, window: window) {
                    becomeCandidate(&t.slots[earlierIndex])
                }
            }
        }
    }

    private static func hasMate(_ t: ContactTracker, of index: Int, window: Int32) -> Bool {
        let e = t.slots[index]
        for k in 0..<t.count where k != index {
            let o = t.slots[k]
            if o.isActive, o.role != .palm, abs(o.landedAtFrame - e.landedAtFrame) <= window { return true }
        }
        return false
    }

    private static func becomeCandidate(_ s: inout TrackedContact) {
        s.role = .thumbCandidate
        s.candidateTravelMM = 0
        s.candidateCumulative = .zero
        s.groupCumulative = .zero
    }

    private static func promoteCandidates(_ t: inout ContactTracker, cfg: RejectionConfig) {
        var sum = SIMD2<Float>.zero
        var n: Float = 0
        for i in 0..<t.count where t.slots[i].role == .finger && t.slots[i].hasDelta {
            sum += t.slots[i].deltaMM
            n += 1
        }
        let groupDelta = n > 0 ? sum / n : .zero

        for i in 0..<t.count where t.slots[i].role == .thumbCandidate && t.slots[i].hasDelta {
            var s = t.slots[i]
            s.candidateTravelMM += length(s.deltaMM)
            s.candidateCumulative += s.deltaMM
            s.groupCumulative += groupDelta
            if s.candidateTravelMM >= cfg.thumbPromoteTravelMM && dot(s.candidateCumulative, s.groupCumulative) > 0 {
                s.role = .finger
                s.promoted = true
            }
            t.slots[i] = s
        }
    }
}
