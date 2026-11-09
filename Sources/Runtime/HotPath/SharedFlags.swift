import PlatformBackends
import Synchronization

public enum ResetRequest: UInt8, Sendable, BitwiseCopyable {
    case none = 0
    /// Release now and suspend the engine until the pad is clear.
    case abort = 1
    /// As abort, then forget every contact. Before a touch source restart.
    case abortAndForget = 2
}

/// Everything shared between the hot thread and the rest of the process. Every field is an atomic.
public final class SharedFlags: Sendable {
    public let activation: ActivationFlags
    /// A ResetRequest, raised with max() by other threads and taken by the next frame.
    public let resetRequested = Atomic<UInt8>(0)
    /// EngineState.packed after the last frame. Polled by UI and the watchdog.
    public let packedState = Atomic<UInt64>(0)
    /// mach nanoseconds of the last frame.
    public let lastFrameNanos = Atomic<UInt64>(0)
    /// Worst time spent in one frame since the last reset of this counter.
    public let frameCostMaxNanos = Atomic<UInt64>(0)
    public let frameCount = Atomic<UInt64>(0)
    /// qos_class_t of the touch callback thread, sampled on the first frame. 0 until known.
    public let callbackQoS = Atomic<UInt32>(0)
    public let callbackPrecedence = Atomic<Int32>(-1)
    public let callbackTimeConstraint = Atomic<Bool>(false)

    public init(activation: ActivationFlags = ActivationFlags()) {
        self.activation = activation
    }

    public func requestReset(_ request: ResetRequest) {
        var current = resetRequested.load(ordering: .relaxed)
        while current < request.rawValue {
            let (exchanged, original) = resetRequested.compareExchange(expected: current, desired: request.rawValue,
                                                                       ordering: .acquiringAndReleasing)
            if exchanged { return }
            current = original
        }
    }

    @inline(__always) func recordFrameCost(_ nanos: UInt64) {
        var current = frameCostMaxNanos.load(ordering: .relaxed)
        while nanos > current {
            let (exchanged, original) = frameCostMaxNanos.compareExchange(expected: current, desired: nanos, ordering: .relaxed)
            if exchanged { return }
            current = original
        }
    }
}
