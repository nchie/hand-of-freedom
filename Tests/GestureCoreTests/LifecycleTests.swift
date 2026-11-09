import Testing
import GestureCore
import TestSupport

@Suite("Activation, abort and determinism")
struct LifecycleTests {
    func dragging() -> FrameBuilder {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (0.5, 0), frames: 3)
        return b
    }

    @Test func inactiveTargetNeverInjects() {
        var b = dragging()
        b.moveEach([1: (-0.3, 0), 2: (0.3, 0)], frames: 30)
        let r = b.run(active: false)
        #expect(r.buttonEvents.isEmpty)
        #expect(r.totalScroll() == 0)
        #expect(r.totalMove() == .zero)
    }

    @Test func targetLossMidDragReleasesAndStaysOff() {
        var b = dragging()
        b.setActive(false)
        b.moveAll(by: (0.5, 0), frames: 3)
        b.setActive(true)
        b.moveAll(by: (0.5, 0), frames: 5)               // same fingers still down: no new drag
        b.liftAll()
        b.land(3, at: (60, 50)); b.land(4, at: (80, 50))
        b.frames(2)
        b.moveAll(by: (0.5, 0), frames: 3)
        #expect(b.run().buttonEvents == ["+right", "-right", "+right"])
    }

    @Test func abortReleasesAndSuspendsUntilPadIsClear() {
        var b = dragging()
        b.abort()
        b.moveAll(by: (0.5, 0), frames: 5)
        b.liftAll()
        b.land(3, at: (60, 50)); b.land(4, at: (80, 50))
        b.frames(2)
        b.moveAll(by: (0.5, 0), frames: 3)
        let r = b.run()
        #expect(r.buttonEvents == ["+right", "-right", "+right"])
    }

    @Test func outputIsDeterministicAndIgnoresTimestamps() {
        var b = dragging()
        b.dropout(2, frames: 1)
        b.moveAll(by: (0.4, 0.2), frames: 10)
        b.moveEach([1: (-0.3, 0.5), 2: (0.3, 0.5)], frames: 20)
        b.land(3, at: (95, 45))
        b.frames(4)
        b.liftAll()
        let a = b.run()
        #expect(a.outputs == b.run().outputs)
        #expect(a.outputs == b.run(timeScale: 1.1).outputs)
        #expect(a.outputs.contains { $0.press != nil })
        #expect(a.outputs.contains { $0.scrollTicks != 0 })
    }

    @Test func transitionsAreReported() {
        var b = dragging()
        b.liftAll()
        let r = b.run()
        let transitions = r.outputs.compactMap(\.transition).map(\.to)
        #expect(transitions == [.armed(count: 2), .dragging(.right, members: 2), .suspended, .idle])
    }

    @Test(arguments: [
        EngineState.Phase.idle, .armed(count: 3), .dragging(.right, members: 2), .dragging(.middle, members: 4), .suspended,
    ])
    func packedStateRoundTrips(phase: EngineState.Phase) {
        var s = EngineState()
        s.phase = phase
        s.countedFingers = 3
        s.rawTouching = 5
        s.zoomEngaged = true
        #expect(EngineState(packed: s.packed) == s)
    }
}
