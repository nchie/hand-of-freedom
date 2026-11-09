import Testing
import Runtime

@Suite("Health")
struct HealthTests {
    @Test func threeFailedPostsInARowStartFailingAndOneSuccessEndsIt() {
        var c = PostFailureCounter()
        #expect(c.record(rc: 1) == nil)
        #expect(c.record(rc: 1) == nil)
        #expect(c.record(rc: 0) == nil)                    // not in a row
        #expect(c.record(rc: 1) == nil)
        #expect(c.record(rc: 1) == nil)
        #expect(c.record(rc: 1) == true)
        #expect(c.record(rc: 1) == nil)                    // reported once
        #expect(c.record(rc: 0) == false)
    }

    @Test func aFailedOpenOrFailingPostsAreUnhealthy() {
        var h = InjectorHealth()
        #expect(h.isHealthy)
        h.openFailed = true
        #expect(!h.isHealthy)
        h.openFailed = false
        h.postsFailing = true
        #expect(!h.isHealthy)
    }

    @Test func reenableStormIsUnstableAndCalmsDownAfterTheWindow() {
        var t = TapHealth()
        let s: UInt64 = 1_000_000_000
        var changed = false
        changed = t.sample(reenableCount: 5, nowNanos: 10 * s); #expect(!changed)
        #expect(!t.isUnstable)                             // five in a minute is tolerated
        changed = t.sample(reenableCount: 6, nowNanos: 20 * s); #expect(changed)
        #expect(t.isUnstable)
        changed = t.sample(reenableCount: 6, nowNanos: 60 * s); #expect(!changed)
        changed = t.sample(reenableCount: 6, nowNanos: 71 * s); #expect(changed)   // the first five aged out
        #expect(!t.isUnstable)
    }
}
