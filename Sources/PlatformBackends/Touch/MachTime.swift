import Darwin

/// Monotonic nanoseconds from mach_absolute_time. Allocation-free, safe on the hot path.
public enum MachTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    @inline(__always) public static func nowNanos() -> UInt64 {
        let t = mach_absolute_time()
        let tb = timebase
        return tb.numer == tb.denom ? t : t / UInt64(tb.denom) * UInt64(tb.numer) + t % UInt64(tb.denom) * UInt64(tb.numer) / UInt64(tb.denom)
    }
}
