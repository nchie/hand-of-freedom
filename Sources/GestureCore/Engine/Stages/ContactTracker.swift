/// Everything the engine remembers about one contact.
struct TrackedContact: BitwiseCopyable {
    var id: Int32 = 0
    var role: ContactRole = .none
    var last: Contact = .zero
    var present = false
    var presentPrev = false
    /// Has reached the touching phase at least once. Contacts that only hovered are never counted.
    var everTouched = false
    /// Was seen in a lift phase. A lifted contact is dead for counting and is evicted once absent.
    var lifted = false
    var landedAtFrame: Int32 = -1
    var framesTouching: Int32 = 0
    /// Consecutive frames absent or present but not touching.
    var framesNotTouching: Int32 = 0
    var isZoneContact = false
    var travelMM: Float = 0
    /// Largest size seen while touching. A contact well below it is rolling off the pad.
    var peakSize: Float = 0
    /// This frame's movement. Only valid when `hasDelta`: touching in this and the previous frame.
    var deltaMM: SIMD2<Float> = .zero
    var hasDelta = false
    /// Promoted from thumb candidate to finger. Never becomes a candidate again.
    var promoted = false
    var candidateTravelMM: Float = 0
    var candidateCumulative: SIMD2<Float> = .zero
    var groupCumulative: SIMD2<Float> = .zero

    var isTouchingNow: Bool { present && last.phase == .touching }
    /// On its way down: present, never touched, not lifting, and first seen at most `frames` frames ago.
    func isApproaching(within frames: Int32) -> Bool {
        present && !everTouched && !last.isLifting && last.phase != .notTracking && framesNotTouching < frames
    }
    /// Touching, but shrunk below `ratio` of its peak size: the finger is lifting.
    func isLiftingOff(ratio: Float) -> Bool { isTouchingNow && last.size < ratio * peakSize }
    /// On the pad as far as the engine is concerned: touching now, or a recent dropout.
    var isActive: Bool { everTouched && !lifted && (isTouchingNow || (!present && last.phase == .touching)) }
}

/// Identity across frames, keyed by MultitouchSupport's contact identifier. Order is first-seen and stable.
struct ContactTracker: BitwiseCopyable {
    static let capacity = 16
    var slots = InlineArray<16, TrackedContact>(repeating: TrackedContact())
    var count = 0

    func index(of id: Int32) -> Int? {
        for i in 0..<count where slots[i].id == id { return i }
        return nil
    }

    func slot(id: Int32) -> TrackedContact? {
        index(of: id).map { slots[$0] }
    }

    /// No contact on the pad and no dropout still in its grace period.
    var isEmpty: Bool {
        for i in 0..<count where slots[i].isActive { return false }
        return true
    }

    mutating func ingest(_ frame: TouchFrame, frameIndex: Int32, ghostFrames: Int32, rejection: RejectionConfig) {
        for i in 0..<count {
            slots[i].presentPrev = slots[i].present
            slots[i].present = false
            slots[i].hasDelta = false
            slots[i].deltaMM = .zero
        }

        for j in 0..<frame.count {
            let c = frame[j]
            if c.phase == .notTracking { continue }
            if let i = index(of: c.id) {
                var s = slots[i]
                let wasTouching = s.presentPrev && s.last.phase == .touching
                if c.phase == .touching && wasTouching {
                    s.deltaMM = c.positionMM - s.last.positionMM
                    s.hasDelta = true
                    s.travelMM += length(s.deltaMM)
                }
                s.last = c
                s.present = true
                if c.phase == .touching {
                    if !s.everTouched { land(&s, c, frameIndex: frameIndex, rejection: rejection) }
                    s.peakSize = max(s.peakSize, c.size)
                    s.framesTouching += 1
                    s.framesNotTouching = 0
                } else {
                    s.framesNotTouching += 1
                    if c.isLifting && s.everTouched { s.lifted = true }
                }
                slots[i] = s
            } else {
                if c.isLifting { continue }           // the lift of a contact we never saw land
                guard count < Self.capacity else { continue }
                var s = TrackedContact()
                s.id = c.id
                s.last = c
                s.present = true
                if c.phase == .touching {
                    land(&s, c, frameIndex: frameIndex, rejection: rejection)
                    s.peakSize = c.size
                    s.framesTouching = 1
                }
                slots[count] = s
                count += 1
            }
        }

        // Absent contacts: ghost a recent dropout, evict everything else.
        var kept = 0
        for i in 0..<count {
            var s = slots[i]
            if !s.present {
                s.framesNotTouching += 1
                let isDropout = s.everTouched && !s.lifted && s.last.phase == .touching
                if !isDropout || s.framesNotTouching > ghostFrames { continue }
            }
            slots[kept] = s
            kept += 1
        }
        count = kept
    }

    private func land(_ s: inout TrackedContact, _ c: Contact, frameIndex: Int32, rejection: RejectionConfig) {
        s.everTouched = true
        s.landedAtFrame = frameIndex
        s.isZoneContact = rejection.isInThumbZone(c.normalized)
    }
}
