import AllocCounter
import Foundation
import GestureCore
import PlatformBackends
import Runtime
import Testing
import TestSupport

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// Hot-path rule 1: no heap allocation per frame, transient ones included. Counts every allocation the
/// test thread makes while the hot loop runs, so other tests running in parallel cannot disturb it.
/// Unoptimized builds allocate (about 35 per frame), so this runs in release builds only:
///
///     swift test -c release --filter AllocationTests
@Suite("Allocation", .enabled(if: optimized, "the no-allocation rule applies to optimized builds"))
struct AllocationTests {
    @Test func hotLoopDoesNotAllocatePerFrame() {
        var b = FrameBuilder()
        for round in 0..<25 {
            let base = Int32(round * 10)
            b.land(base + 1, at: (60, 40)); b.land(base + 2, at: (80, 40))
            b.frames(3)
            b.moveAll(by: (0.5, 0.2), frames: 20)
            b.moveEach([base + 1: (-0.3, 0.5), base + 2: (0.3, 0.5)], frames: 30)
            b.dropout(base + 2, frames: 1)
            b.moveAll(by: (0.4, 0), frames: 5)
            b.liftAll()
        }
        let frames = b.allFrames
        let flags = SharedFlags()
        flags.activation.targetActive.store(true, ordering: .releasing)
        let ring = SPSCRing<TraceEvent>(capacityPowerOfTwo: 1 << 12)
        let loop = HotLoop(injector: NullInjector(), flags: flags, mailbox: ConfigMailbox(.default), ring: ring,
                           initialConfig: .default)

        let warmUp = 200
        for f in frames.prefix(warmUp) { loop.handle(f); while ring.pop() != nil {} }
        var outputs = 0
        let measured = Array(frames.dropFirst(warmUp))
        alloc_counter_start()
        for f in measured {
            loop.handle(f)
            while ring.pop() != nil { outputs += 1 }
        }
        let allocations = alloc_counter_stop()
        #expect(measured.count >= 1000)
        #expect(outputs > 0)
        #expect(allocations == 0, "\(allocations) heap allocations over \(measured.count) frames")
    }
}
