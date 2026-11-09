import GestureCore
import PlatformBackends
import Synchronization

public enum ProbeResult: Sendable, Equatable, CustomStringConvertible {
    /// Our move came back through the window server, after this many microseconds.
    case healthy(latencyMicros: UInt64)
    /// Posted without error, but no event of ours arrived in time: the window server dropped it.
    case noEcho
    /// The grant posting needs is missing, so nothing was posted.
    case notPermitted
    /// The listening tap could not be created, so nothing was posted and the result is unknown.
    case cannotListen(TapError)
    case postFailed(Int32)
    /// A drag is running or a button is held. Try again once the pad is idle.
    case busy

    public var isHealthy: Bool { if case .healthy = self { true } else { false } }
    /// Says something about the injector, as opposed to about the probe's own preconditions.
    public var isConclusive: Bool {
        switch self {
        case .healthy, .noEcho, .postFailed: true
        case .notPermitted, .cannotListen, .busy: false
        }
    }

    public var description: String {
        switch self {
        case .healthy(let us): "healthy, echo after \(us) µs"
        case .noEcho: "no echo: posted events are being dropped"
        case .notPermitted: "not permitted to post, nothing posted"
        case .cannotListen(let e): "cannot listen for the echo (\(e)), nothing posted"
        case .postFailed(let rc): "posting failed with \(rc)"
        case .busy: "busy: a drag is running"
        }
    }
}

/// Checks that injected input really arrives: listens for pointer moves, posts a one-pixel move and its
/// inverse, and waits for one that the injector recognises as its own. Net cursor displacement is zero.
/// Never runs during a drag, so it cannot interleave with the hot thread's input.
@MainActor
public struct InjectorProbe {
    public var timeout: Duration
    /// +1 posts right-and-up first, -1 left-and-down first. A cursor pinned in a corner can swallow one
    /// direction, so a retry goes the other way.
    public var direction: Int32

    public init(timeout: Duration = .milliseconds(50), direction: Int32 = 1) {
        self.timeout = timeout
        self.direction = direction
    }

    /// `permitted`: the grant posting needs is present. `canListen`: the listener's grant is present.
    /// Without it a listening tap is created but hears nothing, which would look exactly like a dead
    /// injector, so the probe posts nothing and reports `.cannotListen`.
    public func run(injector: any Injector, listener: any EchoListener, flags: SharedFlags,
                    permitted: Bool, canListen: Bool = true) async -> ProbeResult {
        guard EngineState(packed: flags.packedState.load(ordering: .acquiring)).phase == .idle,
              injector.held.raw == 0 else { return .busy }
        guard permitted else { return .notPermitted }
        guard canListen else { return .cannotListen(.notPermitted) }

        let outcome = ProbeOutcome()
        let result = await withCheckedContinuation { (cont: CheckedContinuation<ProbeResult, Never>) in
            outcome.arm(cont)
            do throws(TapError) {
                try listener.start { identity in
                    if injector.isOwnEvent(identity) { outcome.finish { .healthy(latencyMicros: $0) } }
                }
            } catch {
                outcome.finish { _ in .cannotListen(error) }
                return
            }
            outcome.markPosted()
            let d = direction >= 0 ? Int32(1) : -1
            let rc = injector.move(dx: d, dy: -d, held: nil)
            if rc != 0 {
                outcome.finish { _ in .postFailed(rc) }
                return
            }
            let back = injector.move(dx: -d, dy: d, held: nil)
            if back != 0 { outcome.finish { _ in .postFailed(back) } }
            let timeout = self.timeout
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                outcome.finish { _ in .noEcho }
            }
        }
        listener.stop()
        return result
    }
}

/// Resolves the probe exactly once, from whichever thread gets there first.
private final class ProbeOutcome: Sendable {
    private struct State {
        var continuation: CheckedContinuation<ProbeResult, Never>?
        var postedAt: UInt64 = 0
    }
    private let state = Mutex(State())

    func arm(_ c: CheckedContinuation<ProbeResult, Never>) { state.withLock { $0.continuation = c } }

    func markPosted() { state.withLock { $0.postedAt = MachTime.nowNanos() } }

    /// `make` gets the microseconds since posting.
    func finish(_ make: (UInt64) -> ProbeResult) {
        let now = MachTime.nowNanos()
        let pending: (CheckedContinuation<ProbeResult, Never>, UInt64)? = state.withLock { s in
            guard let c = s.continuation else { return nil }
            s.continuation = nil
            return (c, s.postedAt)
        }
        guard let (c, postedAt) = pending else { return }
        c.resume(returning: make(postedAt == 0 ? 0 : (now &- postedAt) / 1000))
    }
}
