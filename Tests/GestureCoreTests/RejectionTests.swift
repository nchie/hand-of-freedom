import Testing
import GestureCore
import TestSupport

@Suite("Palm and thumb rejection")
struct RejectionTests {
    @Test func palmBySizeNeverCounts() {
        var b = FrameBuilder()
        b.land(9, at: (100, 40), size: 3.0)              // a palm resting outside the thumb zone
        b.frames(5)
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(2)
        b.move([1, 2], by: (0.3, 0), frames: 3)
        let r = b.run()
        #expect(r.presses == [.right])                   // two fingers, not three
        #expect(r.engine.role(of: 9) == .palm)
    }

    @Test func contactGrowingInsideWindowBecomesPalm() {
        var b = FrameBuilder()
        b.land(1, at: (50, 50)); b.land(2, at: (70, 50)); b.land(9, at: (90, 40))
        b.frames(2)                                      // three fingers armed
        b.setSize(9, 3.0)                                // it was a palm landing small
        b.frames(1)
        b.move([1, 2], by: (0.3, 0), frames: 3)
        let r = b.run()
        #expect(r.presses == [.right])
    }

    /// From a recording: a piece of a resting palm landed finger-sized beside it, then grew palm-sized
    /// well after the growth window, while one finger moved.
    @Test func palmPieceThatGrowsLateNeverCounts() {
        var b = FrameBuilder()
        b.land(9, at: (100, 40), size: 3.0)              // the resting palm
        b.land(1, at: (40, 20))                          // the finger that moves
        b.frames(5)
        b.land(10, at: (85, 50), size: 1.3)              // a piece of the palm, just under the limits
        b.frames(15)                                     // past palmGrowthFrames
        b.setSize(10, 3.5)                               // grows palm-sized
        b.mark("grown")
        b.move([1], by: (-0.2, 0.3), frames: 5)          // across the line to the palm piece, so not a pinch
        let r = b.run()
        #expect(r.buttonEvents.isEmpty)
        #expect(r.engine.role(of: 10) == .palm)
    }

    @Test func memberPressingFlatterLateInADragKeepsTheDrag() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(2)
        b.moveAll(by: (0.3, 0), frames: 20)              // a long turn, well past the growth window
        b.setSize(1, 3.0)                                // one finger flattens
        b.moveAll(by: (0.3, 0), frames: 5)
        let r = b.run()
        #expect(r.buttonEvents == ["+right"])            // still held
    }

    @Test func lateThumbInZoneIsIgnored() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(20)
        b.land(5, at: (60, 8))                           // thumb drops onto the bottom edge later
        b.frames(3)
        b.move([1, 2], by: (0.3, 0), frames: 3)
        let r = b.run()
        #expect(r.presses == [.right])
        #expect(r.engine.role(of: 5) == .thumbCandidate)
    }

    @Test func restingThumbIsIgnoredWhenFingersLand() {
        var b = FrameBuilder()
        b.land(5, at: (60, 8))                           // thumb resting first
        b.frames(30)
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(2)
        b.move([1, 2], by: (0.3, 0), frames: 3)
        let r = b.run()
        #expect(r.presses == [.right])
        #expect(r.engine.role(of: 5) == .thumbCandidate)
    }

    @Test func fingersLandingTogetherLowOnPadCount() {
        var b = FrameBuilder()
        b.land(1, at: (60, 8)); b.land(2, at: (80, 8))
        b.frames(2)
        b.moveAll(by: (0.3, 0), frames: 3)
        #expect(b.run().presses == [.right])
    }

    @Test func lateThumbCountsWithoutTheZoneRule() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(20)
        b.land(5, at: (60, 30))                          // same late landing, but outside the zone: a real finger
        b.frames(3)
        b.moveAll(by: (0.3, 0), frames: 3)
        #expect(b.run().presses == [.left])
    }

    @Test func thumbMovingWithFingersBecomesFinger() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(20)
        b.land(5, at: (40, 8))
        b.frames(3)
        b.moveAll(by: (0.3, 0.3), frames: 6)             // all three move together
        let r = b.run(config: .default.with { $0.mapping.twoFingers = .off })
        #expect(r.presses == [.left])
        #expect(r.engine.role(of: 5) == .finger)
    }
}
