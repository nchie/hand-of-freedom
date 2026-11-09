import Dispatch
import Foundation

/// Drains the hot thread's ring on a utility queue and hands each event to `handler` there.
/// The only consumer of the ring.
public final class TraceWriter: @unchecked Sendable {
    private let ring: SPSCRing<TraceEvent>
    public let queue: DispatchQueue
    private let handler: @Sendable (TraceEvent) -> Void
    private var timer: DispatchSourceTimer?

    public init(ring: SPSCRing<TraceEvent>, queue: DispatchQueue = DispatchQueue(label: "hof.trace-writer", qos: .utility),
                handler: @escaping @Sendable (TraceEvent) -> Void) {
        self.ring = ring
        self.queue = queue
        self.handler = handler
    }

    public func start(intervalMilliseconds: Int = 50) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(intervalMilliseconds))
        t.setEventHandler { [self] in drain() }
        t.resume()
        timer = t
    }

    /// Stops the timer and drains what is left, synchronously.
    public func stop() {
        timer?.cancel()
        timer = nil
        queue.sync { drain() }
    }

    private func drain() {
        while let event = ring.pop() { handler(event) }
    }
}

/// A trace file being written. Use only from the writer queue.
public final class TraceFile: @unchecked Sendable {
    public let url: URL
    public let header: TraceHeader
    private let handle: FileHandle
    private var buffer = Data()

    public init(url: URL, header: TraceHeader) throws {
        self.url = url
        self.header = header
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        write(TraceCodec.headerLine(header))
    }

    public func write(_ line: String) {
        buffer.append(contentsOf: line.utf8)
        buffer.append(0x0A)
        if buffer.count > 64 * 1024 { flush() }
    }

    public func write(_ event: TraceEvent) {
        write(TraceCodec.line(event, t0: header.t0Nanos))
    }

    public func seconds(since entry: UInt64) -> Double { TraceCodec.seconds(entry, since: header.t0Nanos) }

    public func flush() {
        guard !buffer.isEmpty else { return }
        try? handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    public func close() {
        flush()
        try? handle.close()
    }
}
