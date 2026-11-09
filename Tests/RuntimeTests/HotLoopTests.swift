import Dispatch
import Foundation
import GestureCore
import PlatformBackends
import Runtime
import Synchronization
import Testing
import TestSupport

@Suite("Hot loop")
struct HotLoopTests {
    @Test func injectsWhatTheEngineDecides() {
        let session = turnSession()
        let expected = session.run()
        let rig = Rig()
        rig.feed(session.allFrames)

        var wanted: [InjectorCall] = []
        for o in expected.outputs {
            if let b = o.release { wanted.append(.buttonUp(b)) }
            if let b = o.press { wanted.append(.buttonDown(b)) }
            if o.movePx != .zero { wanted.append(.move(o.movePx.x, o.movePx.y, held: o.held)) }
            if o.scrollTicks != 0 { wanted.append(.scroll(o.scrollTicks)) }
        }
        #expect(rig.calls == wanted)
        #expect(rig.downs == [.right])
        #expect(rig.ups == [.right])
    }

    @Test func injectsOnTheThreadThatDeliveredTheFrame() throws {
        let rig = Rig()
        let source = ReplayTouchSource(frames: turnSession().allFrames)
        try source.start(sink: rig.loop)
        #expect(source.waitUntilFinished(timeout: .now() + 5))
        let threads = Set(rig.injector.calls.map(\.thread))
        #expect(threads.count == 1)
        #expect(!threads.contains(currentThreadID()))
    }

    @Test func abortFromAnotherThreadReleasesOnceAndBlocksUntilLift() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (0.5, 0), frames: 5)
        let start = b.allFrames.count
        b.moveAll(by: (0.5, 0), frames: 10)              // fingers keep going after the abort
        b.liftAll()
        b.land(3, at: (60, 50)); b.land(4, at: (80, 50))
        b.frames(2)
        b.moveAll(by: (0.5, 0), frames: 3)
        let frames = b.allFrames

        let rig = Rig()
        rig.feed(Array(frames[..<start]))
        DispatchQueue.global().sync { rig.loop.abortActiveDrag() }
        #expect(rig.injector.held.contains(.right) == false)  // released at once, not on the next frame
        rig.feed(Array(frames[start...]))
        #expect(rig.downs == [.right, .right])            // the second press is the fresh gesture only
        #expect(rig.ups == [.right])                      // the abort's release; the engine's own is a no-op
    }

    @Test func publishedConfigIsUsedFromTheNextFrame() {
        var b = FrameBuilder()
        b.land(1, at: (60, 50)); b.land(2, at: (80, 50))
        b.frames(3)
        b.moveAll(by: (1, 0), frames: 3)
        let split = b.allFrames.count
        b.moveAll(by: (1, 0), frames: 3)
        let frames = b.allFrames

        let rig = Rig()
        rig.feed(Array(frames[..<split]))
        rig.mailbox.publish(.default.with { $0.pointer.pxPerMM = 20 })
        rig.feed(Array(frames[split...]))
        let moves = rig.calls.compactMap { if case .move(let x, _, _) = $0 { x } else { nil } }
        #expect(moves.suffix(3) == [20, 20, 20])
        #expect(moves.dropLast(3).last == 10)
    }

    @Test func deactivationMidDragReleases() {
        let frames = turnSession(turnFrames: 20).allFrames
        let rig = Rig()
        rig.feed(Array(frames[..<10]))
        rig.flags.activation.targetActive.store(false, ordering: .releasing)
        rig.feed(Array(frames[10...]))
        #expect(rig.downs == [.right])
        #expect(rig.ups == [.right])
    }

    @Test func traceRingCarriesEveryKindOfEvent() {
        let rig = Rig()
        rig.feed(turnSession().allFrames)
        let events = rig.drain()
        #expect(events.contains { if case .frame = $0 { true } else { false } })
        #expect(events.contains { if case .output = $0 { true } else { false } })
        #expect(events.contains { if case .inject(.buttonDown, .right, _, 0, _, _) = $0 { true } else { false } })
        #expect(events.contains { if case .state = $0 { true } else { false } })
        #expect(events.contains { if case .flag(true, _) = $0 { true } else { false } })
        let v1 = rig.ring.dropped.load(ordering: .relaxed)
        #expect(v1 == 0)
        let v2 = rig.flags.frameCount.load(ordering: .relaxed)
        #expect(v2 == UInt64(turnSession().allFrames.count))
    }

    @Test func firstFrameSamplesTheCallbackThread() {
        let rig = Rig()
        rig.feed(Array(turnSession().allFrames.prefix(1)))
        let v3 = rig.flags.callbackQoS.load(ordering: .relaxed)
        let v4 = rig.flags.callbackPrecedence.load(ordering: .relaxed)
        #expect(v3 != 0 || v4 >= 0)
    }
}

@Suite("Watchdog")
struct WatchdogTests {
    final class FakeClock: Sendable {
        let now = Atomic<UInt64>(0)
    }

    @Test func releasesOnceWhenFramesStopMidDrag() {
        let frames = turnSession(turnFrames: 10).allFrames
        let rig = Rig()
        rig.feed(Array(frames[..<8]))                    // dragging, then the frames stop
        #expect(rig.injector.held.contains(.right))
        let clock = FakeClock()
        let last = rig.flags.lastFrameNanos.load(ordering: .relaxed)
        clock.now.store(last, ordering: .relaxed)
        let stalls = Atomic<Int>(0)
        let dog = Watchdog(flags: rig.flags, hotLoop: rig.loop, stallMilliseconds: 300,
                           clock: { clock.now.load(ordering: .relaxed) },
                           onStall: { stalls.add(1, ordering: .relaxed) })
        dog.tick()                                       // learns the last frame time
        clock.now.store(last + 200_000_000, ordering: .relaxed)
        dog.tick()
        #expect(rig.injector.held.contains(.right))      // 200 ms: still fine
        clock.now.store(last + 400_000_000, ordering: .relaxed)
        dog.tick()
        dog.tick()
        #expect(!rig.injector.held.contains(.right))
        let v5 = stalls.load(ordering: .relaxed)
        #expect(v5 == 1)
        #expect(rig.ups == [.right])
    }

    @Test func doesNothingWhenIdle() {
        let rig = Rig()
        let clock = FakeClock()
        let stalls = Atomic<Int>(0)
        let dog = Watchdog(flags: rig.flags, hotLoop: rig.loop, clock: { clock.now.load(ordering: .relaxed) },
                           onStall: { stalls.add(1, ordering: .relaxed) })
        dog.tick()
        clock.now.store(10_000_000_000, ordering: .relaxed)
        dog.tick()
        let v6 = stalls.load(ordering: .relaxed)
        #expect(v6 == 0)
    }
}
