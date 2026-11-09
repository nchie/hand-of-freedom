import Testing
import GestureCore
import TestSupport

@Suite("Pinch zoom")
struct PinchTests {
    @Test func symmetricPinchZoomsWithoutPress() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveEach([1: (-0.3, 0), 2: (0.3, 0)], frames: 30)
        let r = b.run()
        #expect(r.buttonEvents.isEmpty)
        #expect(r.totalScroll() >= 4)
    }

    @Test func pinchInZoomsOut() {
        var b = FrameBuilder()
        b.land(1, at: (50, 50)); b.land(2, at: (90, 50))
        b.frames(3)
        b.moveEach([1: (0.3, 0), 2: (-0.3, 0)], frames: 30)
        let r = b.run()
        #expect(r.buttonEvents.isEmpty)
        #expect(r.totalScroll() <= -4)
    }

    @Test func anchoredThumbPinchZoomsWithoutPress() {
        var b = FrameBuilder()
        b.land(5, at: (40, 8))                           // thumb resting first
        b.frames(30)
        b.land(1, at: (70, 40))                          // index lands later
        b.frames(3)
        let axis = SIMD2<Float>(30, 32) / (30 * 30 + 32 * 32 as Float).squareRoot()
        b.move([1], by: (axis.x * 0.5, axis.y * 0.5), frames: 30)
        let r = b.run()
        #expect(r.buttonEvents.isEmpty)
        #expect(r.totalScroll() >= 3)
    }

    @Test func pinchDuringTurnZoomsAndTurns() {
        var b = FrameBuilder()
        b.land(1, at: (60, 40)); b.land(2, at: (80, 40))
        b.frames(3)
        b.moveAll(by: (0, 1), frames: 5)                 // turning: right drag
        b.mark("pinch")
        b.moveEach([1: (-0.3, 1), 2: (0.3, 1)], frames: 30)
        let r = b.run()
        let at = b.marks["pinch"]!
        #expect(r.presses == [.right])
        #expect(r.totalScroll(from: at) >= 4)
        #expect(r.totalMove(from: at).y < -250)          // still turning, upward on screen
        #expect(abs(r.totalMove(from: at).x) <= 2)       // the spreading itself is not camera motion
    }

    @Test func asymmetricTwoFingerPinchDoesNotTurn() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.move([2], by: (0.5, 0), frames: 30)            // finger 1 anchored, finger 2 spreads away
        let r = b.run()
        #expect(r.buttonEvents.isEmpty)
        #expect(r.totalScroll() >= 3)
    }

    @Test func longTurnWithDriftNeverZooms() {
        var b = FrameBuilder()
        b.land(1, at: (40, 40)); b.land(2, at: (60, 40))
        b.frames(3)
        b.moveEach([1: (0.5, 0), 2: (0.52, 0)], frames: 400)   // 8 mm of slow spread drift over a long turn
        let r = b.run()
        #expect(r.totalScroll() == 0)
        #expect(r.presses == [.right])
    }

    /// The leaky baseline trades very slow pinches for stability: spread changing at 0.16 mm per frame
    /// (about 19 mm/s) during a turn never reaches the dead band, so it never zooms.
    @Test func moderateSpreadDriftDuringTurnNeverZooms() {
        var b = FrameBuilder()
        b.land(1, at: (40, 40)); b.land(2, at: (60, 40))
        b.frames(3)
        b.moveEach([1: (0, 1), 2: (0.16, 1)], frames: 100)
        let r = b.run()
        #expect(r.totalScroll() == 0)
        #expect(r.presses == [.right])
    }

    @Test func pinchStopsAfterQuietFrames() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveEach([1: (-0.3, 0), 2: (0.3, 0)], frames: 20)
        b.frames(20)
        b.mark("after")
        b.move([1], by: (-0.5, 0))                       // a small twitch must not zoom again
        b.frames(5)
        let r = b.run()
        #expect(r.totalScroll(from: b.marks["after"]!) == 0)
        #expect(r.engine.state.zoomEngaged == false)
    }

    @Test func palmIsNeverAPinchPartner() {
        var b = FrameBuilder()
        b.land(9, at: (40, 10), size: 3.0)
        b.land(1, at: (70, 50))
        b.frames(3)
        b.move([1], by: (0.5, 0.5), frames: 30)
        #expect(b.run().totalScroll() == 0)
    }

    @Test func zoomCanBeDisabled() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveEach([1: (-0.3, 0), 2: (0.3, 0)], frames: 30)
        #expect(b.run(config: .default.with { $0.zoom.enabled = false }).totalScroll() == 0)
    }

    /// Fingers side by side, swiping sideways fast at slightly different speeds: the spread changes every
    /// frame, so the pinch protection is on, but the movement both fingers share must still turn.
    @Test func fastSwipeAlongTheFingerLineStillTurns() {
        var b = FrameBuilder()
        b.land(1, at: (50, 50)); b.land(2, at: (70, 50))
        b.frames(3)
        b.mark("swipe")
        b.moveEach([1: (2.0, 0), 2: (2.4, 0)], frames: 12)
        let r = b.run()
        #expect(r.presses == [.right])
        let sent = r.totalMove(from: b.marks["swipe"]!)
        #expect(sent.x >= 200)                             // about 2 mm a frame for 12 frames at 10 px/mm, less the start
        #expect(r.totalScroll() == 0)                      // and no zoom
    }
}
