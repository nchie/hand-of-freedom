import Foundation
import Synchronization
import Testing
import GestureCore
import PlatformBackends
import Runtime

/// A listener the test controls.
final class FakeListener: EchoListener, @unchecked Sendable {
    let handler = Mutex<(@Sendable (EventIdentity) -> Void)?>(nil)
    var failWith: TapError?
    let stops = Atomic<Int>(0)

    func start(onEvent: @escaping @Sendable (EventIdentity) -> Void) throws(TapError) {
        if let failWith { throw failWith }
        handler.withLock { $0 = onEvent }
    }

    func stop() {
        handler.withLock { $0 = nil }
        stops.add(1, ordering: .relaxed)
    }

    func deliver(_ identity: EventIdentity) { handler.withLock { $0 }?(identity) }
    var isListening: Bool { handler.withLock { $0 != nil } }
}

/// Moves are echoed to the listener as `echo` (own, foreign or nothing), from another thread.
final class EchoInjector: Injector, @unchecked Sendable {
    enum Echo { case own, foreign, none }
    let name = "echo"
    let listener: FakeListener
    var echo: Echo = .own
    var moveResult: Int32 = 0
    let moves = Mutex<[SIMD2<Int32>]>([])
    let heldButtons = HeldButtons()

    init(listener: FakeListener) { self.listener = listener }

    func open() throws(InjectorError) {}
    func close() {}
    func buttonDown(_ b: MouseButton) -> Int32 { heldButtons.insert(b); return 0 }
    func buttonUp(_ b: MouseButton) -> Int32 { _ = heldButtons.remove(b); return 0 }
    func move(dx: Int32, dy: Int32, held: MouseButton?) -> Int32 {
        moves.withLock { $0.append(SIMD2(dx, dy)) }
        guard moveResult == 0 else { return moveResult }
        let identity = EventIdentity(sourcePID: echo == .own ? 42 : 7, sourceUserData: 0)
        if echo != .none {
            let l = listener
            Thread.detachNewThread { l.deliver(identity) }
        }
        return 0
    }
    func scroll(ticks: Int32) -> Int32 { 0 }
    var held: ButtonMask { heldButtons.mask }
    func isOwnEvent(_ identity: EventIdentity) -> Bool { identity.sourcePID == 42 }
}

@MainActor
@Suite("Injector probe")
struct ProbeTests {
    let listener = FakeListener()
    let flags = SharedFlags()
    var injector: EchoInjector { EchoInjector(listener: listener) }

    @Test func ownEchoIsHealthyAndTheCursorEndsWhereItStarted() async {
        let inj = injector
        let result = await InjectorProbe(timeout: .seconds(2)).run(injector: inj, listener: listener, flags: flags, permitted: true)
        #expect(result.isHealthy)
        #expect(inj.moves.withLock { $0 } == [SIMD2(1, -1), SIMD2(-1, 1)])
        #expect(!listener.isListening)
    }

    @Test func theOtherDirectionStartsLeftAndDown() async {
        let inj = injector
        _ = await InjectorProbe(timeout: .seconds(2), direction: -1).run(injector: inj, listener: listener, flags: flags, permitted: true)
        #expect(inj.moves.withLock { $0 } == [SIMD2(-1, 1), SIMD2(1, -1)])
    }

    @Test func silenceIsNoEcho() async {
        let inj = injector
        inj.echo = .none
        let result = await InjectorProbe(timeout: .milliseconds(20)).run(injector: inj, listener: listener, flags: flags, permitted: true)
        #expect(result == .noEcho)
        #expect(!listener.isListening)
    }

    @Test func someoneElsesMoveDoesNotCount() async {
        let inj = injector
        inj.echo = .foreign
        let result = await InjectorProbe(timeout: .milliseconds(50)).run(injector: inj, listener: listener, flags: flags, permitted: true)
        #expect(result == .noEcho)
    }

    @Test func neverPostsDuringADrag() async {
        let inj = injector
        var state = EngineState()
        state.phase = .dragging(.right, members: 2)
        flags.packedState.store(state.packed, ordering: .releasing)
        #expect(await InjectorProbe().run(injector: inj, listener: listener, flags: flags, permitted: true) == .busy)
        flags.packedState.store(EngineState().packed, ordering: .releasing)
        inj.buttonDown(.left)                            // a button held outside a drag counts too
        #expect(await InjectorProbe().run(injector: inj, listener: listener, flags: flags, permitted: true) == .busy)
        #expect(inj.moves.withLock { $0 }.isEmpty)
    }

    @Test func withoutPermissionNothingIsPosted() async {
        let inj = injector
        #expect(await InjectorProbe().run(injector: inj, listener: listener, flags: flags, permitted: false) == .notPermitted)
        #expect(inj.moves.withLock { $0 }.isEmpty)
    }

    @Test func withoutInputMonitoringNothingIsPostedBecauseSilenceWouldLookLikeADeadInjector() async {
        let inj = injector
        let result = await InjectorProbe().run(injector: inj, listener: listener, flags: flags, permitted: true, canListen: false)
        #expect(result == .cannotListen(.notPermitted))
        #expect(!result.isConclusive)
        #expect(inj.moves.withLock { $0 }.isEmpty)
    }

    @Test func aFailedPostIsReportedAndNotFollowedByTheInverse() async {
        let inj = injector
        inj.moveResult = -536870212
        let result = await InjectorProbe().run(injector: inj, listener: listener, flags: flags, permitted: true)
        #expect(result == .postFailed(-536870212))
        #expect(inj.moves.withLock { $0 }.count == 1)
        #expect(!listener.isListening)
    }

    @Test func withoutAnEarNothingIsPosted() async {
        let inj = injector
        listener.failWith = .notPermitted
        let result = await InjectorProbe().run(injector: inj, listener: listener, flags: flags, permitted: true)
        #expect(result == .cannotListen(.notPermitted))
        #expect(!result.isConclusive)
        #expect(inj.moves.withLock { $0 }.isEmpty)
    }
}
