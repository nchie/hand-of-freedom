/// Turns trackpad frames into mouse actions. Pure and deterministic: the same frames, configs and
/// activation flags always give the same outputs. Never allocates, never reads a clock or a timestamp;
/// every window is counted in frames.
public struct GestureEngine: Sendable {
    public private(set) var state = EngineState()
    public private(set) var trace = EngineTrace()
    /// Increments per `process` call. The engine's only clock.
    public private(set) var frameIndex: Int32 = 0

    var tracker = ContactTracker()
    var drag = DragController()
    var pinch = PinchController()
    var mapper = MotionMapper()

    public init() {}

    /// Call for every frame, even while the target is inactive, so contacts stay tracked.
    /// `route` is read only while no gesture is committed; see `GestureRoute`.
    public mutating func process(_ frame: TouchFrame, config: EngineConfig, targetActive: Bool,
                                 route: GestureRoute = .drive) -> EngineOutput {
        frameIndex &+= 1
        var out = EngineOutput()
        let previous = state.phase

        tracker.ingest(frame, frameIndex: frameIndex, ghostFrames: config.thresholds.ghostFrames, rejection: config.rejection)
        let members = drag.members
        ContactClassifier.classify(&tracker, members: members, cfg: config.rejection)
        let count = FingerCounter.count(tracker, members: members, ghostFrames: config.thresholds.ghostFrames,
                                        lookahead: config.thresholds.landingLookaheadFrames)
        let pair = PairGeometry.select(tracker, members: members)
        // A gesture routed away from the game does not zoom either.
        let axis = pinch.step(pair: pair, cfg: config.zoom, targetActive: targetActive && !drag.isPassive, out: &out)
        let motion = GroupMotion.compute(tracker, ids: members?.ids ?? count.ids,
                                         count: members?.count ?? count.counted, projectAxis: axis,
                                         liftOffRatio: config.thresholds.liftOffSizeRatio)
        drag.step(count: count, motion: motion, trackerEmpty: tracker.isEmpty, cfg: config,
                  targetActive: targetActive, route: route, mapper: &mapper, out: &out)

        state.phase = drag.publicPhase
        state.countedFingers = count.counted
        state.rawTouching = count.rawTouching
        state.zoomEngaged = pinch.engaged
        if state.phase != previous { out.transition = .init(from: previous, to: state.phase) }

        trace.countedFingers = count.counted
        trace.rawTouching = count.rawTouching
        trace.approaching = count.approaching
        trace.meanDeltaMM = motion.meanDeltaMM
        trace.projected = motion.projected
        trace.liftingOff = motion.liftingOff
        trace.armedTravelMM = drag.armedTravelMM
        trace.spreadMM = pair?.spreadMM ?? 0
        trace.pinchBaselineMM = pinch.baselineMM
        trace.pinchAccumulatorMM = pinch.accumulatorMM
        trace.pinchEngaged = pinch.engaged
        return out
    }

    /// Releases a held button, stops any zoom and suspends until the pad is clear.
    /// For sleep, disable, permission loss and stalls.
    public mutating func abort() -> EngineOutput {
        var out = EngineOutput()
        let previous = state.phase
        drag.abort(out: &out)
        pinch.clear()
        mapper.reset()
        state.phase = drag.publicPhase
        state.zoomEngaged = false
        if state.phase != previous { out.transition = .init(from: previous, to: state.phase) }
        return out
    }

    /// Forgets every contact and returns to idle without emitting anything.
    public mutating func reset() {
        self = GestureEngine()
    }

    /// The role the classifier gave a contact, for diagnostics and tests.
    public func role(of id: Int32) -> ContactRole? {
        tracker.slot(id: id)?.role
    }
}
