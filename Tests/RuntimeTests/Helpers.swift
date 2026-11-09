import Darwin
import GestureCore
import PlatformBackends
import Runtime
import TestSupport

/// A hot loop wired to a recording injector, driven directly from the test thread.
struct Rig {
    let injector = RecordingInjector()
    let flags = SharedFlags()
    let ring = SPSCRing<TraceEvent>(capacityPowerOfTwo: 1 << 14)
    let mailbox: ConfigMailbox<EngineConfig>
    let loop: HotLoop

    init(config: EngineConfig = .default, active: Bool = true) {
        mailbox = ConfigMailbox(config)
        loop = HotLoop(injector: injector, flags: flags, mailbox: mailbox, ring: ring, initialConfig: config)
        flags.activation.targetActive.store(active, ordering: .releasing)
    }

    func feed(_ frames: [TouchFrame]) { for f in frames { loop.handle(f) } }

    func drain() -> [TraceEvent] {
        var events: [TraceEvent] = []
        while let e = ring.pop() { events.append(e) }
        return events
    }

    var calls: [InjectorCall] { injector.calls.map(\.call) }
    var downs: [MouseButton] { calls.compactMap { if case .buttonDown(let b) = $0 { b } else { nil } } }
    var ups: [MouseButton] { calls.compactMap { if case .buttonUp(let b) = $0 { b } else { nil } } }
}

func currentThreadID() -> UInt64 {
    var tid: UInt64 = 0
    pthread_threadid_np(nil, &tid)
    return tid
}

/// Two fingers land, turn for a while, and lift.
func turnSession(turnFrames: Int = 10) -> FrameBuilder {
    var b = FrameBuilder()
    b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
    b.frames(3)
    b.moveAll(by: (0.5, 0), frames: turnFrames)
    b.liftAll()
    return b
}
