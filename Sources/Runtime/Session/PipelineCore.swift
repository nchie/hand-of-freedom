import Foundation
import GestureCore
import PlatformBackends

/// The touch-to-injection wiring every front end shares: source → hot loop → injector, ring → writer.
/// Created once per process; the touch source and hot loop live until exit.
public final class PipelineCore: @unchecked Sendable {
    public let flags = SharedFlags()
    public let ring = SPSCRing<TraceEvent>(capacityPowerOfTwo: 4096)
    public let mailbox: ConfigMailbox<EngineConfig>
    public let injector: any Injector
    public let hotLoop: HotLoop
    public let source: any TouchSource
    public let t0 = MachTime.nowNanos()
    private var writer: TraceWriter?
    private var reportedThread = false

    public init(config: EngineConfig, injector: any Injector, source: (any TouchSource)? = nil) throws {
        mailbox = ConfigMailbox(config)
        self.injector = injector
        hotLoop = HotLoop(injector: injector, flags: flags, mailbox: mailbox, ring: ring, initialConfig: config)
        self.source = try source ?? MultitouchSource()
    }

    /// Starts draining the ring on the writer queue and then the touch source.
    public func start(onEvent: @escaping @Sendable (TraceEvent) -> Void) throws(TouchSourceError) {
        let w = TraceWriter(ring: ring, handler: onEvent)
        w.start()
        writer = w
        try source.start(sink: hotLoop)
    }

    public var writerQueue: DispatchQueue? { writer?.queue }

    public func stop() {
        source.stop()
        writer?.stop()
    }

    /// The callback thread's scheduling, once the first frame has sampled it.
    public var threadReport: (qos: String, precedence: Int32, timeConstraint: Bool)? {
        let qos = flags.callbackQoS.load(ordering: .relaxed)
        guard flags.frameCount.load(ordering: .relaxed) > 0 else { return nil }
        return (ThreadInfo.qosName(qos), flags.callbackPrecedence.load(ordering: .relaxed),
                flags.callbackTimeConstraint.load(ordering: .relaxed))
    }

    public func seconds(_ entry: UInt64) -> Double { TraceCodec.seconds(entry, since: t0) }

    public func header(tool: String, config: EngineConfig) -> TraceHeader {
        TraceHeader(tool: tool, devices: source.devices, config: config, t0Nanos: t0)
    }
}
