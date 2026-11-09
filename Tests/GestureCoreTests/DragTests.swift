import Foundation
import Testing
import GestureCore
import TestSupport

@Suite("Drag")
struct DragTests {
    /// Two fingers resting side by side in the middle of the pad.
    func twoFingers() -> FrameBuilder {
        var b = FrameBuilder()
        b.land(1, at: (60, 50))
        b.land(2, at: (80, 50))
        b.frames(3)
        return b
    }

    @Test func twoFingerTapEmitsNothing() {
        var b = twoFingers()
        b.move([1, 2], by: (0.05, 0), frames: 3)        // jitter well under the threshold
        b.liftAll()
        let r = b.run()
        #expect(r.buttonEvents.isEmpty)
        #expect(r.totalMove() == .zero)
    }

    @Test func dragStartsOnDistanceNotTime() {
        var b = twoFingers()
        b.frames(200)                                    // resting for over a second never presses
        b.mark("first")
        b.move([1, 2], by: (0.25, 0), frames: 2)
        let r = b.run()
        let first = b.marks["first"]!
        #expect(r.outputs[..<first].allSatisfy { $0.press == nil })
        #expect(r.outputs[first].press == nil)           // 0.25 mm: not yet
        #expect(r.outputs[first + 1].press == .right)    // 0.5 mm: pressed
    }

    @Test func twoFingersHoldRightThreeHoldLeft() {
        var two = twoFingers()
        two.moveAll(by: (0.5, 0), frames: 3)
        two.liftAll()
        #expect(two.run().buttonEvents == ["+right", "-right"])

        var three = FrameBuilder()
        three.land(1, at: (50, 50)); three.land(2, at: (65, 52)); three.land(3, at: (80, 50))
        three.frames(2)
        three.moveAll(by: (0.5, 0), frames: 3)
        three.liftAll()
        #expect(three.run().buttonEvents == ["+left", "-left"])
    }

    @Test func movementMapsToScreenDirection() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 1)               // start the drag
        b.mark("move")
        b.moveAll(by: (1, -1), frames: 5)                // right and toward the bottom of the pad
        let r = b.run()
        let total = r.totalMove(from: b.marks["move"]!)
        #expect(total == SIMD2(50, 50))                  // 10 px/mm, screen y grows downward
    }

    @Test func oneFrameFlickerKeepsDrag() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 3)
        b.dropout(2, frames: 1)
        b.moveAll(by: (0.5, 0), frames: 5)
        b.liftAll()
        let r = b.run()
        #expect(r.buttonEvents == ["+right", "-right"])
        #expect(r.maxStepPx <= 6)                        // the returning finger's missed frame is not replayed as a jump
    }

    @Test func wholeFrameDropoutKeepsDrag() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 3)
        b.emptyFrames(2)
        b.moveAll(by: (0.5, 0), frames: 5)
        b.liftAll()
        let r = b.run()
        #expect(r.buttonEvents == ["+right", "-right"])
        #expect(r.maxStepPx <= 6)                        // the reappearing fingers do not jump
    }

    @Test func dropoutLongerThanGraceEndsDrag() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 3)
        b.mark("dropout")
        b.dropout(2, frames: 3)
        b.moveAll(by: (0.5, 0), frames: 3)
        let r = b.run()
        let start = b.marks["dropout"]!
        #expect(r.outputs[start...].compactMap(\.release) == [.right])
    }

    @Test func liftReleasesOnTheLiftFrame() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 3)
        b.lift(1)
        b.mark("lift")
        b.frames(1)
        let r = b.run()
        #expect(r.outputs[b.marks["lift"]!].release == .right)
    }

    @Test func grazingThirdFingerNeverRetypes() {
        var b = twoFingers()
        b.moveAll(by: (0.25, 0), frames: 2)              // 0.5 mm: right down
        b.land(3, at: (95, 48))
        b.frames(3)
        b.moveAll(by: (0.3, 0), frames: 5)
        b.lift(3)
        b.frames(3)
        b.liftAll()
        let r = b.run()
        #expect(r.buttonEvents == ["+right", "-right"])
        #expect(r.phases.contains(.dragging(.right, members: 2)))
    }

    @Test func memberLiftEndsGestureUntilAllLifted() {
        var b = FrameBuilder()
        b.land(1, at: (50, 50)); b.land(2, at: (65, 52)); b.land(3, at: (80, 50))
        b.frames(2)
        b.moveAll(by: (0.5, 0), frames: 5)               // left drag
        b.lift(1)
        b.move([2, 3], by: (1, 0), frames: 10)           // remaining two keep sliding: must not become a right drag
        b.liftAll()
        b.land(4, at: (60, 50)); b.land(5, at: (80, 50))
        b.frames(2)
        b.moveAll(by: (0.5, 0), frames: 3)               // a fresh gesture works again
        let r = b.run()
        #expect(r.buttonEvents == ["+left", "-left", "+right"])
    }

    @Test func staggeredThirdFingerResetsTravel() {
        var b = FrameBuilder()
        b.land(1, at: (50, 50)); b.land(2, at: (65, 52))
        b.frames(2)
        b.moveAll(by: (0.1, 0), frames: 1)               // two fingers start moving a little
        b.land(3, at: (80, 50))
        b.moveAll(by: (0.25, 0), frames: 4)
        let r = b.run()
        #expect(r.presses == [.left])
        #expect(r.phases.contains(.dragging(.left, members: 3)))   // the late finger is a full member
    }

    @Test func unmappedCountNeverPresses() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 5)
        let r = b.run(config: .default.with { $0.mapping.twoFingers = .off })
        #expect(r.buttonEvents.isEmpty)
    }

    @Test func idSwapProducesNoJump() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 3)
        b.swapID(2, to: 7)
        b.moveAll(by: (0.5, 0), frames: 10)
        let r = b.run()
        #expect(r.maxStepPx <= 6)
    }

    @Test func subpixelMotionAccumulates() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 1)
        b.mark("slow")
        b.moveAll(by: (0.03, 0), frames: 100)            // 0.3 px per frame, 30 px in total
        let r = b.run()
        let total = r.totalMove(from: b.marks["slow"]!)
        #expect(abs(total.x - 30) <= 1)
    }

    @Test func perFrameClampApplies() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 1)
        b.mark("jump")
        b.moveAll(by: (20, 0), frames: 1)                // 200 px of bad data
        let r = b.run()
        #expect(r.outputs[b.marks["jump"]!].movePx.x == 60)
    }

    @Test func sensitivityChangeTakesEffectNextFrame() {
        var b = twoFingers()
        b.moveAll(by: (0.5, 0), frames: 1)
        b.moveAll(by: (1, 0), frames: 2)
        b.mark("change")
        b.setConfig(.default.with { $0.pointer.pxPerMM = 20 })
        b.moveAll(by: (1, 0), frames: 1)
        let r = b.run()
        let at = b.marks["change"]!
        #expect(r.outputs[at - 1].movePx.x == 10)
        #expect(r.outputs[at + 1].movePx.x == 20)
    }

    @Test func liftOffDriftNeverStartsADrag() {
        var b = twoFingers()
        // Rolling off: both contacts shrink well below their peak while their centres slide 1 mm.
        for size: Float in [0.6, 0.45, 0.3, 0.2] {
            b.setSize(1, size); b.setSize(2, size)
            b.moveAll(by: (0, 0.25), frames: 1)
        }
        b.liftAll()
        #expect(b.run().buttonEvents.isEmpty)
        let unguarded = EngineConfig.default.with { $0.thresholds.liftOffSizeRatio = 0 }
        #expect(b.run(config: unguarded).buttonEvents == ["+right", "-right"])
    }

    @Test func aSwipeWithLighterFingersStillStartsAtOnce() {
        var b = twoFingers()
        b.setSize(1, 0.75); b.setSize(2, 0.75)          // lighter than at landing, above the 0.7 cutoff
        b.mark("swipe")
        b.moveAll(by: (0.3, 0), frames: 2)
        let r = b.run()
        #expect(r.outputs[b.marks["swipe"]! + 1].press == .right)
    }

    @Test func liftingOffWhileArmedKeepsTravelSoFar() {
        var b = twoFingers()
        b.moveAll(by: (0.3, 0), frames: 1)               // 0.3 mm of real travel
        b.setSize(1, 0.5)
        b.moveAll(by: (0.3, 0), frames: 2)               // drift while one finger rolls off adds nothing
        b.setSize(1, 1.0)                                // pressed back down
        b.mark("resume")
        b.moveAll(by: (0.3, 0), frames: 1)               // 0.6 mm in total: pressed
        let r = b.run()
        let resume = b.marks["resume"]!
        #expect(r.outputs[..<resume].allSatisfy { $0.press == nil })
        #expect(r.outputs[resume].press == .right)
    }

    @Test func thresholdsFromBeforeLiftOffStillDecode() throws {
        let json = #"{"dragStartMM":0.4,"ghostFrames":2}"#
        let t = try JSONDecoder().decode(Thresholds.self, from: Data(json.utf8))
        #expect(t.dragStartMM == 0.4)
        #expect(t.liftOffSizeRatio == Thresholds().liftOffSizeRatio)
    }

    /// From a recording: the third finger was reported approaching on the frame two fast fingers crossed the
    /// threshold, and touched two frames later.
    @Test func approachingThirdFingerHoldsTheRightPress() {
        var b = FrameBuilder()
        b.land(1, at: (50, 50)); b.land(2, at: (65, 52))
        b.frames(1)
        b.moveAll(by: (0.3, 0), frames: 1)
        b.approach(3, at: (80, 50))
        b.moveAll(by: (0.3, 0), frames: 2)               // two fingers past the threshold, the third still on its way
        b.touchDown(3)
        b.moveAll(by: (0.3, 0), frames: 4)
        b.liftAll()
        let r = b.run()
        #expect(r.buttonEvents == ["+left", "-left"])
        let early = EngineConfig.default.with { $0.thresholds.landingLookaheadFrames = 0 }
        #expect(b.run(config: early).buttonEvents.first == "+right")
    }

    @Test func fingerHoveringTooLongStopsHoldingThePress() {
        var b = FrameBuilder()
        b.land(1, at: (50, 50)); b.land(2, at: (65, 52))
        b.frames(1)
        b.approach(3, at: (80, 50), phase: .hovering)    // hovers and never lands
        b.mark("move")
        b.moveAll(by: (0.3, 0), frames: 6)
        let r = b.run()
        let at = r.outputs.firstIndex { $0.press != nil }!
        #expect(r.outputs[at].press == .right)
        #expect(at - b.marks["move"]! <= 3)              // a turn starts at most a couple of frames late
    }

    @Test func approachingFingerThatKeepsTheButtonDoesNotDelay() {
        var b = FrameBuilder()
        b.land(1, at: (50, 50)); b.land(2, at: (65, 52)); b.land(3, at: (80, 50))
        b.frames(3)
        b.approach(4, at: (95, 50))                      // a fourth finger would map to nothing...
        b.mark("move")
        b.moveAll(by: (0.3, 0), frames: 2)
        let r = b.run(config: .default.with { $0.mapping.fourFingers = .left })   // ...unless four is also left
        #expect(r.outputs[b.marks["move"]! + 1].press == .left)
    }
}
