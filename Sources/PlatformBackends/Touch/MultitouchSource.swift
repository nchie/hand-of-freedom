import CMultitouchSupport
import GestureCore
import Synchronization

/// Raw trackpad frames from the private MultitouchSupport framework.
///
/// Create one per process and keep it: the framework holds an unretained pointer to it, so it must
/// outlive every frame the framework may still have queued.
public final class MultitouchSource: TouchSource, @unchecked Sendable {
    /// Contacts dropped by the sanity checks. Non-zero suggests the private struct layout changed.
    public let suspiciousContacts = Atomic<Int32>(0)

    public private(set) var devices: [TouchDeviceInfo] = []
    private let gate = QuiescenceGate()
    // Set once on the first start, before any device is started, then only read from the callback.
    private var sink: (any TouchFrameSink)?
    private var started: [Int] = []

    public init() throws(TouchSourceError) {
        var err = [CChar](repeating: 0, count: 256)
        if mt_load(&err, err.count) != 0 {
            throw .frameworkUnavailable(String(decoding: err.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        refreshDevices()
    }

    private func refreshDevices() {
        let n = Int(mt_enumerate())
        devices = (0..<n).map { TouchDeviceInfo(index: $0, isBuiltIn: mt_device_is_builtin(Int32($0)) != 0) }
    }

    public func start(sink: any TouchFrameSink) throws(TouchSourceError) {
        if self.sink == nil { self.sink = sink }
        let targets = devices.filter(\.isBuiltIn)
        guard !targets.isEmpty else { throw .noBuiltInDevice }
        gate.open()
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for device in targets {
            let rc = mt_start(Int32(device.index), multitouchFrameCallback, refcon)
            if rc != 0 { throw .startFailed(rc) }
            started.append(device.index)
        }
    }

    public func stop() {
        for index in started { mt_stop(Int32(index)) }
        started.removeAll()
        gate.close()
    }

    public var rejectedContacts: Int32 { suspiciousContacts.load(ordering: .relaxed) }

    public func restart() throws(TouchSourceError) {
        stop()
        refreshDevices()
        guard let sink else { return }
        try start(sink: sink)
    }

    fileprivate func deliver(_ touches: UnsafePointer<MTTouch>?, _ count: Int32, _ timestamp: Double, _ sequence: Int32) {
        let entry = MachTime.nowNanos()
        guard gate.enter() else { return }
        defer { gate.exit() }
        var frame = TouchFrame(sequence: sequence, entryNanos: entry, deviceTimestamp: timestamp)
        var rejected: Int32 = 0
        if let touches {
            for i in 0..<Int(max(0, count)) {
                if let c = MTTouchConversion.contact(from: touches[i]) { frame.append(c) } else { rejected += 1 }
            }
        }
        if rejected > 0 { suspiciousContacts.add(rejected, ordering: .relaxed) }
        sink?.handle(frame)
    }
}

private let multitouchFrameCallback: mt_frame_fn = { refcon, touches, count, timestamp, frame in
    guard let refcon else { return }
    Unmanaged<MultitouchSource>.fromOpaque(refcon).takeUnretainedValue().deliver(touches, count, timestamp, frame)
}
