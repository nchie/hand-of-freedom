import Darwin
import GestureCore
import PlatformBackends

/// Runs the engine inside the touch callback and injects synchronously, with no thread hop.
///
/// Single owner: every `var` is touched only on the touch source's thread. Other threads talk to it only
/// through `SharedFlags` atomics, the `ConfigMailbox`, and the trace ring. Built once per process;
/// the injector is never replaced. Hot-path rules: no allocation, no lock, no Objective-C, no strings,
/// no printing (docs/how-it-works.md).
public final class HotLoop: TouchFrameSink, @unchecked Sendable {
    private let injector: any Injector
    private let flags: SharedFlags
    private let mailbox: ConfigMailbox<EngineConfig>
    private let ring: SPSCRing<TraceEvent>

    private var engine = GestureEngine()
    private var config: EngineConfig
    private var seenGeneration: UInt64 = 0
    private var lastActive: Bool? = nil
    private var lastRoute: GestureRoute? = nil
    private var owner: pthread_t? = nil

    public init(injector: any Injector, flags: SharedFlags, mailbox: ConfigMailbox<EngineConfig>,
                ring: SPSCRing<TraceEvent>, initialConfig: EngineConfig) {
        self.injector = injector
        self.flags = flags
        self.mailbox = mailbox
        self.ring = ring
        self.config = initialConfig
    }

    public func handle(_ frame: TouchFrame) {
        let t0 = frame.entryNanos
        if let owner {
            assert(pthread_equal(owner, pthread_self()) != 0, "HotLoop used from two threads")
        } else {
            owner = pthread_self()
            sampleThread()
        }

        // Activation first: a writer publishes config before raising the flag (see `PipelineController.recomputeActivation`).
        let active = flags.activation.targetActive.load(ordering: .acquiring)
        _ = mailbox.refresh(into: &config, seen: &seenGeneration)
        if active != lastActive {
            ring.tryPush(.flag(targetActive: active, entryNanos: t0))
            lastActive = active
        }

        var out = EngineOutput()
        let request = ResetRequest(rawValue: flags.resetRequested.exchange(0, ordering: .acquiringAndReleasing)) ?? .none
        switch request {
        case .none:
            break
        case .abort:
            out = engine.abort()
        case .abortAndForget:
            out = engine.abort()
            engine.reset()
            owner = nil
        }
        if request != .none { ring.tryPush(.reset(request, entryNanos: t0)) }

        let route = currentRoute(t0)
        if route != lastRoute {
            ring.tryPush(.route(route, entryNanos: t0))
            lastRoute = route
        }

        ring.tryPush(.frame(frame))
        out.merge(engine.process(frame, config: config, targetActive: active, route: route))
        flags.activation.scrollPassthrough.store(engine.state.phase == .scrolling, ordering: .releasing)
        apply(out, t0: t0)

        let now = MachTime.nowNanos()
        flags.packedState.store(engine.state.packed, ordering: .releasing)
        flags.lastFrameNanos.store(now, ordering: .relaxed)
        flags.frameCount.add(1, ordering: .relaxed)
        flags.recordFrameCost(now &- t0)
    }

    /// A marker reading older than this no longer routes gestures.
    static let markerMaxAgeNanos: Int64 = 2_000_000_000

    /// The held scroll key wins; otherwise a fresh marker reading decides; otherwise drive.
    @inline(__always)
    private func currentRoute(_ t0: UInt64) -> GestureRoute {
        let a = flags.activation
        let mask = a.scrollModifierMask.load(ordering: .relaxed)
        if mask != 0, a.modifierFlags.load(ordering: .relaxed) & mask != 0 { return .scroll }
        let nanos = a.markerNanos.load(ordering: .acquiring)
        let marker = a.markerRoute.load(ordering: .relaxed)
        // Signed: a reading taken after this frame entered is fresh, not stale.
        guard marker != 0, Int64(bitPattern: t0 &- nanos) < Self.markerMaxAgeNanos else { return .drive }
        return GestureRoute(rawValue: marker - 1) ?? .drive
    }

    /// Any thread. Releases the held button now; the engine suspends on its next frame.
    public func abortActiveDrag() {
        injector.releaseAll()
        flags.requestReset(.abort)
    }

    /// Before a touch source restart. Releases now; the engine forgets all contacts on its next frame.
    public func abortAndForget() {
        injector.releaseAll()
        flags.requestReset(.abortAndForget)
    }

    private func apply(_ out: EngineOutput, t0: UInt64) {
        if !out.isEmpty { ring.tryPush(.output(out, entryNanos: t0, us: micros(since: t0))) }
        if let b = out.release { record(.buttonUp, b, .zero, injector.buttonUp(b), t0) }
        if let b = out.press { record(.buttonDown, b, .zero, injector.buttonDown(b), t0) }
        if out.movePx != .zero {
            record(.move, out.held, out.movePx, injector.move(dx: out.movePx.x, dy: out.movePx.y, held: out.held), t0)
        }
        if out.scrollTicks != 0 {
            record(.scroll, nil, SIMD2(0, out.scrollTicks), injector.scroll(ticks: out.scrollTicks), t0)
        }
        if let transition = out.transition {
            ring.tryPush(.state(transition, entryNanos: t0, us: micros(since: t0)))
        }
    }

    @inline(__always)
    private func record(_ op: InjectOp, _ button: MouseButton?, _ value: SIMD2<Int32>, _ rc: Int32, _ t0: UInt64) {
        ring.tryPush(.inject(op, button: button, value: value, rc: rc, entryNanos: t0, us: micros(since: t0)))
    }

    @inline(__always)
    private func micros(since t0: UInt64) -> UInt32 {
        UInt32(truncatingIfNeeded: min((MachTime.nowNanos() &- t0) / 1000, UInt64(UInt32.max)))
    }

    /// First-frame exception to the hot-path rules: one syscall pair to learn how the framework schedules us.
    private func sampleThread() {
        flags.callbackQoS.store(ThreadInfo.currentQoS(), ordering: .relaxed)
        let scheduling = ThreadInfo.currentScheduling()
        flags.callbackPrecedence.store(scheduling.precedence, ordering: .relaxed)
        flags.callbackTimeConstraint.store(scheduling.timeConstraint, ordering: .relaxed)
    }
}
