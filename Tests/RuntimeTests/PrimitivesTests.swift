import Dispatch
import Foundation
import PlatformBackends
import Runtime
import Synchronization
import Testing

@Suite("Cross-thread primitives")
struct PrimitivesTests {
    struct Checked: Sendable, BitwiseCopyable, Equatable {
        var value: UInt64
        var check: UInt64
        init(_ v: UInt64) { value = v; check = ~v }
        var isConsistent: Bool { check == ~value }
    }

    @Test func mailboxNeverTearsAndConverges() {
        let box = ConfigMailbox(Checked(0))
        let done = Atomic<Bool>(false)
        DispatchQueue.global().async {
            for i in 1...20_000 { box.publish(Checked(UInt64(i))) }
            done.store(true, ordering: .releasing)
        }
        var local = Checked(0)
        var seen: UInt64 = 0
        var torn = 0
        var last: UInt64 = 0
        var backwards = 0
        while !done.load(ordering: .acquiring) {
            if box.refresh(into: &local, seen: &seen) {
                if !local.isConsistent { torn += 1 }
                if local.value < last { backwards += 1 }
                last = local.value
            }
        }
        while box.refresh(into: &local, seen: &seen) {}
        #expect(torn == 0)
        #expect(backwards == 0)
        #expect(local.value == 20_000)
    }

    @Test func ringPreservesOrderAcrossThreads() {
        let ring = SPSCRing<UInt64>(capacityPowerOfTwo: 256)
        let total: UInt64 = 100_000
        DispatchQueue.global().async {
            var i: UInt64 = 0
            while i < total { if ring.tryPush(i) { i += 1 } }
        }
        var expected: UInt64 = 0
        var outOfOrder = 0
        let deadline = Date().addingTimeInterval(10)
        while expected < total && Date() < deadline {
            if let v = ring.pop() {
                if v != expected { outOfOrder += 1 }
                expected = v + 1
            }
        }
        #expect(expected == total)
        #expect(outOfOrder == 0)
    }

    @Test func fullRingDropsAndCounts() {
        let ring = SPSCRing<Int>(capacityPowerOfTwo: 4)
        for i in 0..<6 { ring.tryPush(i) }
        let v1 = ring.dropped.load(ordering: .relaxed)
        #expect(v1 == 2)
        var popped: [Int] = []
        while let v = ring.pop() { popped.append(v) }
        #expect(popped == [0, 1, 2, 3])
    }

    @Test func resetRequestsOnlyEscalate() {
        let flags = SharedFlags()
        flags.requestReset(.abortAndForget)
        flags.requestReset(.abort)
        let v2 = flags.resetRequested.load(ordering: .relaxed)
        #expect(v2 == ResetRequest.abortAndForget.rawValue)
    }

    @Test func gateCloseWaitsForTheRunningCallback() {
        let gate = QuiescenceGate()
        gate.open()
        let inside = DispatchSemaphore(value: 0)
        let finished = Atomic<Bool>(false)
        DispatchQueue.global().async {
            guard gate.enter() else { return }
            inside.signal()
            usleep(20_000)
            finished.store(true, ordering: .sequentiallyConsistent)
            gate.exit()
        }
        inside.wait()
        #expect(gate.close(timeoutNanos: 1_000_000_000))
        let v3 = finished.load(ordering: .sequentiallyConsistent)
        #expect(v3) // close returned only after the callback did
        #expect(gate.enter() == false)                               // and nothing gets in afterwards
    }

    @Test func heldButtonsReleaseExactlyOnce() {
        let held = HeldButtons()
        held.insert(.right)
        let wins = Atomic<Int>(0)
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            if held.remove(.right) { wins.add(1, ordering: .relaxed) }
        }
        let v4 = wins.load(ordering: .relaxed)
        #expect(v4 == 1)
    }
}
