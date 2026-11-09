import Foundation
import GestureCore
import PlatformBackends

/// Keeps the last few seconds of the hot thread's events so a moment that felt wrong can be saved after
/// the fact, and optionally writes a whole session. Confined to the trace writer's queue: every method
/// must be called there.
public final class TraceRecorder: @unchecked Sendable {
    public enum Entry: Sendable {
        case event(TraceEvent)
        case config(EngineConfig, nanos: UInt64)
        case note(String, nanos: UInt64)

        var nanos: UInt64 {
            switch self {
            case .event(let e): e.entryNanos
            case .config(_, let n), .note(_, let n): n
            }
        }
    }

    public var windowNanos: UInt64
    private let t0: UInt64
    private let devices: [TouchDeviceInfo]
    private var entries: [Entry] = []
    private var start = 0
    /// State at the window's start, from what was pruned.
    private var configBefore: EngineConfig
    private var activeBefore = false
    private var routeBefore = GestureRoute.drive
    private var latestRoute = GestureRoute.drive
    private var session: TraceFile?

    /// `initialActive` is the activation state when the recorder starts, for a recorder started mid-run.
    public init(t0: UInt64, devices: [TouchDeviceInfo], initialConfig: EngineConfig, initialActive: Bool = false,
                windowSeconds: Double = 30) {
        self.t0 = t0
        self.devices = devices
        configBefore = initialConfig
        activeBefore = initialActive
        windowNanos = UInt64(max(1, windowSeconds) * 1e9)
    }

    public func record(_ event: TraceEvent) {
        if case .route(let r, _) = event { latestRoute = r }
        append(.event(event))
        session?.write(event)
    }

    /// A config the controller published. It reaches the hot thread on its next frame.
    public func recordConfig(_ config: EngineConfig, nanos: UInt64) {
        append(.config(config, nanos: nanos))
        session?.write(TraceCodec.configLine(config, tSeconds: TraceCodec.seconds(nanos, since: t0)))
    }

    public func recordNote(_ message: String, nanos: UInt64) {
        append(.note(message, nanos: nanos))
        session?.write(TraceCodec.noteLine(message, tSeconds: TraceCodec.seconds(nanos, since: t0)))
    }

    /// Entries currently in the window, oldest first.
    public var window: [Entry] { Array(entries[start...]) }

    // MARK: Clips

    /// Writes the window to `url`, starting at the first touch that began inside it, so a replay starts
    /// from the same empty-pad state the live engine was in. Returns false if nothing was touched.
    @discardableResult
    public func saveClip(to url: URL, tool: String = "Hand of Freedom clip", note: String? = nil) throws -> Bool {
        let w = window
        guard let first = Self.firstTouchStart(in: w) else { return false }
        var config = configBefore
        var active = activeBefore
        var route = routeBefore
        for entry in w[..<first] {
            switch entry {
            case .config(let c, _): config = c
            case .event(.flag(let a, _)): active = a
            case .event(.route(let r, _)): route = r
            default: break
            }
        }
        let startNanos = w[first].nanos
        let file = try TraceFile(url: url, header: TraceHeader(tool: tool, devices: devices, config: config, t0Nanos: t0))
        file.write(TraceCodec.flagLine(active: active, tSeconds: TraceCodec.seconds(startNanos, since: t0)))
        if route != .drive { file.write(TraceCodec.routeLine(route, tSeconds: TraceCodec.seconds(startNanos, since: t0))) }
        if let note { file.write(TraceCodec.noteLine(note, tSeconds: TraceCodec.seconds(startNanos, since: t0))) }
        for entry in w[first...] { write(entry, to: file) }
        file.close()
        return true
    }

    /// The first frame with contacts whose previous frame was empty, or that follows a gap: MultitouchSupport
    /// stops delivering frames when the pad is empty.
    static func firstTouchStart(in w: [Entry]) -> Int? {
        var previous: TouchFrame?
        for (i, entry) in w.enumerated() {
            guard case .event(.frame(let f)) = entry else { continue }
            defer { previous = f }
            guard f.count > 0 else { continue }
            guard let p = previous else { continue }           // may be the middle of a touch that began earlier
            if p.count == 0 || f.entryNanos &- p.entryNanos > 100_000_000 { return i }
        }
        return nil
    }

    // MARK: Sessions

    public var isRecordingSession: Bool { session != nil }

    public func startSession(to url: URL, config: EngineConfig, active: Bool) throws {
        stopSession()
        let file = try TraceFile(url: url, header: TraceHeader(tool: "Hand of Freedom session", devices: devices, config: config, t0Nanos: t0))
        let now = TraceCodec.seconds(MachTime.nowNanos(), since: t0)
        file.write(TraceCodec.flagLine(active: active, tSeconds: now))
        if latestRoute != .drive { file.write(TraceCodec.routeLine(latestRoute, tSeconds: now)) }
        session = file
    }

    public func stopSession() {
        session?.close()
        session = nil
    }

    // MARK: Storage

    private func append(_ entry: Entry) {
        entries.append(entry)
        let cutoff = entry.nanos &- min(entry.nanos, windowNanos)
        while start < entries.count, entries[start].nanos < cutoff {
            switch entries[start] {
            case .config(let c, _): configBefore = c
            case .event(.flag(let a, _)): activeBefore = a
            case .event(.route(let r, _)): routeBefore = r
            default: break
            }
            start += 1
        }
        if start > 4096 && start * 2 > entries.count {
            entries.removeFirst(start)
            start = 0
        }
    }

    private func write(_ entry: Entry, to file: TraceFile) {
        switch entry {
        case .event(let e): file.write(e)
        case .config(let c, let n): file.write(TraceCodec.configLine(c, tSeconds: TraceCodec.seconds(n, since: t0)))
        case .note(let m, let n): file.write(TraceCodec.noteLine(m, tSeconds: TraceCodec.seconds(n, since: t0)))
        }
    }
}

extension TraceEvent {
    /// The entry time of the frame this event belongs to.
    public var entryNanos: UInt64 {
        switch self {
        case .frame(let f): f.entryNanos
        case .output(_, let n, _), .inject(_, _, _, _, let n, _), .state(_, let n, _), .flag(_, let n), .route(_, let n), .reset(_, let n): n
        }
    }
}
