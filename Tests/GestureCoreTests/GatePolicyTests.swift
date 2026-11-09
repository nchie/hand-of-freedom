import Testing
import GestureCore

@Suite("Event gate")
struct GatePolicyTests {
    let active = GateContext(targetActive: true)
    let inactive = GateContext(targetActive: false)

    @Test func trackpadScrollSwallowedOnlyWhileActive() {
        let scroll = GateEvent(type: GatePolicy.scrollWheel, scrollPhase: 2)
        #expect(GatePolicy.decide(scroll, active) == .swallow)
        #expect(GatePolicy.decide(scroll, inactive) == .pass)
    }

    @Test func momentumScrollSwallowed() {
        #expect(GatePolicy.decide(GateEvent(type: GatePolicy.scrollWheel, momentumPhase: 1), active) == .swallow)
    }

    @Test func mouseWheelPasses() {
        #expect(GatePolicy.decide(GateEvent(type: GatePolicy.scrollWheel), active) == .pass)
    }

    @Test(arguments: [18, 19, 20, 29, 30, 31, 32] as [UInt32])
    func gestureEventsSwallowedWhileActive(type: UInt32) {
        #expect(GatePolicy.decide(GateEvent(type: type), active) == .swallow)
        #expect(GatePolicy.decide(GateEvent(type: type), inactive) == .pass)
    }

    @Test func otherEventsPass() {
        #expect(GatePolicy.decide(GateEvent(type: 5), active) == .pass)
    }

    @Test func ownEventsAlwaysPass() {
        #expect(GatePolicy.decide(GateEvent(type: GatePolicy.scrollWheel, scrollPhase: 2, isOwn: true), active) == .pass)
        #expect(GatePolicy.decide(GateEvent(type: 29, isOwn: true), active) == .pass)
    }

    @Test func swallowingCanBeTurnedOff() {
        let open = GateContext(targetActive: true, swallowTrackpadScroll: false, swallowGestureEvents: false)
        #expect(GatePolicy.decide(GateEvent(type: GatePolicy.scrollWheel, scrollPhase: 2), open) == .pass)
        #expect(GatePolicy.decide(GateEvent(type: 30), open) == .pass)
    }
}

@Suite("Scroll sequences")
struct ScrollSequenceGateTests {
    let scroll = GatePolicy.scrollWheel
    func context(_ pass: Bool) -> GateContext { GateContext(targetActive: true, passTrackpadScroll: pass) }

    @Test func aRoutedScrollAndItsMomentumPass() {
        var gate = ScrollSequenceGate()
        #expect(gate.decide(GateEvent(type: scroll, scrollPhase: 128), context(true)) == .pass)
        #expect(gate.decide(GateEvent(type: scroll, scrollPhase: 1), context(true)) == .pass)
        #expect(gate.decide(GateEvent(type: scroll, scrollPhase: 2), context(true)) == .pass)
        // Fingers lifted: the engine is idle again, but the sequence's end and momentum still pass.
        #expect(gate.decide(GateEvent(type: scroll, scrollPhase: 4), context(false)) == .pass)
        #expect(gate.decide(GateEvent(type: scroll, momentumPhase: 1), context(false)) == .pass)
        #expect(gate.decide(GateEvent(type: scroll, momentumPhase: 3), context(false)) == .pass)
    }

    @Test func theNextTurnIsSwallowedAgain() {
        var gate = ScrollSequenceGate()
        _ = gate.decide(GateEvent(type: scroll, scrollPhase: 1), context(true))
        #expect(gate.decide(GateEvent(type: scroll, scrollPhase: 1), context(false)) == .swallow)
        #expect(gate.decide(GateEvent(type: scroll, scrollPhase: 2), context(false)) == .swallow)
        #expect(gate.decide(GateEvent(type: scroll, momentumPhase: 1), context(false)) == .swallow)
    }

    @Test func aRouteDecidedAfterMacOSBeganScrollingStillOpens() {
        var gate = ScrollSequenceGate()
        #expect(gate.decide(GateEvent(type: scroll, scrollPhase: 1), context(false)) == .swallow)
        #expect(gate.decide(GateEvent(type: scroll, scrollPhase: 2), context(true)) == .pass)
        #expect(gate.decide(GateEvent(type: scroll, momentumPhase: 2), context(false)) == .pass)
    }

    @Test func gesturesStaySwallowedWhileScrolling() {
        var gate = ScrollSequenceGate()
        _ = gate.decide(GateEvent(type: scroll, scrollPhase: 1), context(true))
        #expect(gate.decide(GateEvent(type: 29), context(true)) == .swallow)
    }
}
