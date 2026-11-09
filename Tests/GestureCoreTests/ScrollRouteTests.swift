import Testing
import GestureCore
import TestSupport

/// A gesture routed to scrolling is left to macOS: nothing pressed, moved or zoomed.
@Suite("Scroll route")
struct ScrollRouteTests {
    func land(_ b: inout FrameBuilder) {
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
    }

    @Test func keyHeldAsFingersLandScrollsInsteadOfTurning() {
        var b = FrameBuilder()
        b.setRoute(.scroll)
        land(&b)
        b.moveAll(by: (0, 1), frames: 20)
        let r = b.run()
        #expect(r.buttonEvents.isEmpty)
        #expect(r.totalMove() == .zero)
        #expect(r.phases.last == .scrolling)
    }

    @Test func releasingTheKeyMidScrollKeepsScrollingUntilTheFingersLift() {
        var b = FrameBuilder()
        b.setRoute(.scroll)
        land(&b)
        b.moveAll(by: (0, 1), frames: 5)
        b.setRoute(.drive)
        b.moveAll(by: (0, 1), frames: 10)
        b.liftAll()
        b.frames(2)
        b.mark("next")
        land(&b)
        b.moveAll(by: (1, 0), frames: 10)
        let r = b.run()
        #expect(r.buttonEvents == ["+right"])            // only the second gesture turns
        #expect(r.totalMove(from: b.marks["next"]!).x > 0)
        #expect(r.phases[b.marks["next"]! - 1] == .idle)
    }

    @Test func keyPressedBeforeTheTurnStartsStillScrolls() {
        var b = FrameBuilder()
        land(&b)                                         // armed, nothing pressed yet
        b.setRoute(.scroll)
        b.moveAll(by: (0, 1), frames: 10)
        let r = b.run()
        #expect(r.buttonEvents.isEmpty)
        #expect(r.phases.last == .scrolling)
    }

    @Test func keyPressedMidTurnIsIgnored() {
        var b = FrameBuilder()
        land(&b)
        b.moveAll(by: (1, 0), frames: 5)
        b.setRoute(.scroll)
        b.mark("key")
        b.moveAll(by: (1, 0), frames: 10)
        b.liftAll()
        let r = b.run()
        #expect(r.buttonEvents == ["+right", "-right"])
        #expect(r.totalMove(from: b.marks["key"]!).x > 0)
    }

    @Test func aPinchWhileScrollingDoesNotZoom() {
        var b = FrameBuilder()
        b.setRoute(.scroll)
        land(&b)
        b.moveEach([1: (-0.3, 0), 2: (0.3, 0)], frames: 30)
        let r = b.run()
        #expect(r.totalScroll() == 0)
        #expect(r.buttonEvents.isEmpty)
    }

    @Test func nothingScrollsWhileTheGameIsNotInFront() {
        var b = FrameBuilder()
        b.setRoute(.scroll)
        land(&b)
        let r = b.run(active: false)
        #expect(r.phases.last == .idle)
    }

    @Test func scrollingSurvivesThePackedState() {
        var s = EngineState()
        s.phase = .scrolling
        s.countedFingers = 2
        #expect(EngineState(packed: s.packed) == s)
        s.phase = .idle
        #expect(EngineState(packed: s.packed).phase == .idle)
    }
}

/// Over a game window that does not scroll, a gesture does nothing at all.
@Suite("Ignore route")
struct IgnoreRouteTests {
    @Test func aGestureOverAWindowDoesNothingUntilTheFingersLift() {
        var b = FrameBuilder()
        b.setRoute(.ignore)
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (1, 0), frames: 10)
        b.setRoute(.drive)                               // the pointer reached the world mid-gesture
        b.moveAll(by: (1, 0), frames: 10)
        b.mark("lifted")
        b.liftAll()
        b.frames(2)
        b.land(3, at: (60, 50)); b.land(4, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (1, 0), frames: 5)
        let r = b.run()
        #expect(r.phases[b.marks["lifted"]! - 1] == .ignoring)
        #expect(r.buttonEvents == ["+right"])            // only the next gesture turns
    }

    @Test func aPinchOverAWindowDoesNotZoom() {
        var b = FrameBuilder()
        b.setRoute(.ignore)
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveEach([1: (-0.3, 0), 2: (0.3, 0)], frames: 30)
        #expect(b.run().totalScroll() == 0)
    }

    @Test func ignoringSurvivesThePackedState() {
        var s = EngineState()
        s.phase = .ignoring
        #expect(EngineState(packed: s.packed) == s)
    }
}
