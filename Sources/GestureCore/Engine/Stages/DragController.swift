struct DragMembers: BitwiseCopyable {
    var count: Int32
    var ids: InlineArray<4, Int32>

    func contains(_ id: Int32) -> Bool {
        for k in 0..<Int(count) where ids[k] == id { return true }
        return false
    }
}

/// The drag state machine.
///
///     idle ──counted maps to a button──► armed ──travel ≥ dragStartMM──► dragging
///                                          (frames where a finger is lifting off add no travel;
///                                           a landing finger that would change the button holds the press)
///      ▲                                  │ count changes: re-arm, travel 0     │
///      └──────── count 0 or unmapped ─────┘                                     │
///      ▲                                                                        │
///      └─ member dropout too long, or palm ◄────────────────────────────────────┤
///   suspended ◄── member lifts, target inactive, abort ◄────────────────────────┘
///      └── leaves only when no finger is on the pad
///
///   idle or armed ──route is scroll or ignore──► scrolling or ignoring ──no counted finger──► idle
///      (nothing is pressed or moved; while scrolling the gate lets the trackpad's own scrolling through)
///
/// The button is latched at press and the member set is frozen, so a grazing extra finger can never
/// switch buttons. A member lift ends the whole gesture: the remaining fingers cannot start a new drag
/// until everything has lifted, so the end of a turn or orbit never turns into an accidental click.
struct DragController: BitwiseCopyable {
    enum Phase: BitwiseCopyable {
        case idle
        case armed(count: Int32, travelMM: Float)
        case dragging(MouseButton, DragMembers)
        case suspended
        /// Left to macOS (`passScroll`) or ignored.
        case passive(passScroll: Bool)
    }

    var phase: Phase = .idle

    var members: DragMembers? {
        if case .dragging(_, let m) = phase { return m }
        return nil
    }

    var publicPhase: EngineState.Phase {
        switch phase {
        case .idle: .idle
        case .armed(let count, _): .armed(count: count)
        case .dragging(let button, let m): .dragging(button, members: m.count)
        case .suspended: .suspended
        case .passive(let passScroll): passScroll ? .scrolling : .ignoring
        }
    }

    var isPassive: Bool {
        if case .passive = phase { return true }
        return false
    }

    var armedTravelMM: Float {
        if case .armed(_, let travel) = phase { return travel }
        return 0
    }

    mutating func step(count: FingerCount, motion: GroupMotion, trackerEmpty: Bool, cfg: EngineConfig,
                       targetActive: Bool, route: GestureRoute, mapper: inout MotionMapper, out: inout EngineOutput) {
        switch phase {
        case .suspended:
            if trackerEmpty { phase = .idle }

        case .passive:
            if !targetActive || count.counted == 0 { phase = .idle }

        case .idle:
            if targetActive, route != .drive, count.counted > 0 {
                phase = .passive(passScroll: route == .scroll)
            } else if targetActive, cfg.mapping.button(for: count.counted) != nil {
                phase = .armed(count: count.counted, travelMM: 0)
            }

        case .armed(let armedCount, let travel):
            guard targetActive, let button = cfg.mapping.button(for: count.counted) else {
                phase = .idle
                return
            }
            // Nothing is pressed yet, so the gesture can still go elsewhere.
            if route != .drive {
                phase = .passive(passScroll: route == .scroll)
                return
            }
            if count.counted != armedCount {
                phase = .armed(count: count.counted, travelMM: 0)
                return
            }
            // A finger rolling off the pad shrinks and its centre slides; that drift is not a swipe.
            guard !motion.liftingOff else { return }
            let total = travel + length(motion.meanDeltaMM)
            guard total >= cfg.thresholds.dragStartMM else {
                phase = .armed(count: armedCount, travelMM: total)
                return
            }
            // A finger about to land would change the button: wait for it instead of pressing the wrong one.
            if count.approaching > 0, cfg.mapping.button(for: armedCount + count.approaching) != button {
                phase = .armed(count: armedCount, travelMM: total)
                return
            }
            out.press = button
            out.held = button
            phase = .dragging(button, DragMembers(count: min(armedCount, 4), ids: count.ids))
            mapper.reset()
            out.movePx = mapper.map(deltaMM: motion.meanDeltaMM, cfg: cfg.pointer)

        case .dragging(let button, _):
            if !targetActive || !count.membersAlive {
                out.release = button
                phase = !targetActive || count.memberLifted ? .suspended : .idle
                mapper.reset()
            } else {
                out.held = button
                out.movePx = mapper.map(deltaMM: motion.meanDeltaMM, cfg: cfg.pointer)
            }
        }
    }

    /// Releases a held button and suspends until the pad is clear.
    mutating func abort(out: inout EngineOutput) {
        if case .dragging(let button, _) = phase { out.release = button }
        phase = .suspended
    }
}
