import Foundation
import GestureCore

/// Facts about a recording: frame rates, threads, lift phases, and the distributions rejection
/// thresholds are tuned from (`hof replay --stats`).
public struct TraceStats: Sendable {
    public struct Summary: Sendable {
        public var count = 0
        public var min: Float = 0, p10: Float = 0, p50: Float = 0, p90: Float = 0, max: Float = 0
        init(_ values: [Float]) {
            guard !values.isEmpty else { return }
            let s = values.sorted()
            func q(_ p: Double) -> Float { s[Swift.min(s.count - 1, Int(Double(s.count - 1) * p))] }
            count = s.count; min = s[0]; p10 = q(0.1); p50 = q(0.5); p90 = q(0.9); max = s[s.count - 1]
        }
        public var text: String {
            count == 0 ? "n/a" : String(format: "n=%d min %.2f  p10 %.2f  median %.2f  p90 %.2f  max %.2f", count, min, p10, p50, max == 0 ? 0 : p90, max)
        }
    }

    public var frames = 0
    public var framesWithContacts = 0
    public var emptyFrames = 0
    /// Empty frames that directly follow a frame with contacts.
    public var emptyFramesAfterContacts = 0
    public var durationSeconds = 0.0
    public var activeRateHz = 0.0
    public var maxGapMsWhileTouching = 0.0
    public var callbackQoS: String? = nil
    public var callbackPrecedence: Int? = nil
    public var callbackTimeConstraint: Bool? = nil
    /// Phases before a contact first touches, e.g. "making", counted per contact.
    public var landingSequences: [String: Int] = [:]
    /// Phases after a contact last touches, e.g. "breaking,leaving", or "vanished" when it just disappears.
    public var liftSequences: [String: Int] = [:]
    /// Frames a contact stayed reported after its last touching frame.
    public var framesReportedAfterLift: [Int: Int] = [:]
    public var sizeTouching = Summary([])
    public var majorAxisTouching = Summary([])
    public var minorAxisTouching = Summary([])
    public var maxSizePerContact = Summary([])
    public var contacts = 0

    /// Splits a trace at its note lines, for recordings made with `hof record --guided`.
    public static func segments(_ trace: Trace) -> [(title: String, start: Double, trace: Trace)] {
        var result: [(String, Double, Trace)] = []
        var title = "(before the first note)"
        var start = 0.0
        var current: [TraceRecord] = []
        for record in trace.records {
            if case .note(let message, let t) = record {
                if current.contains(where: { if case .frame = $0 { true } else { false } }) {
                    result.append((title, start, Trace(header: trace.header, records: current)))
                }
                title = message
                start = t
                current = []
            } else {
                current.append(record)
            }
        }
        if current.contains(where: { if case .frame = $0 { true } else { false } }) {
            result.append((title, start, Trace(header: trace.header, records: current)))
        }
        return result
    }

    public static func compute(_ trace: Trace) -> TraceStats {
        var stats = TraceStats()
        var sequences: [Int32: [ContactPhase]] = [:]
        var order: [Int32] = []
        var sizes: [Float] = [], majors: [Float] = [], minors: [Float] = []
        var maxSize: [Int32: Float] = [:]
        var lastT: Double? = nil
        var activeTime = 0.0, activeFrames = 0
        var previousHadContacts = false
        var firstT: Double? = nil

        for record in trace.records {
            switch record {
            case .sys(let qos, let precedence, let tc):
                stats.callbackQoS = qos
                stats.callbackPrecedence = precedence
                stats.callbackTimeConstraint = tc
            case .frame(let f, let t):
                stats.frames += 1
                if firstT == nil { firstT = t }
                if f.count == 0 {
                    stats.emptyFrames += 1
                    if previousHadContacts { stats.emptyFramesAfterContacts += 1 }
                } else {
                    stats.framesWithContacts += 1
                    if let lastT, previousHadContacts {
                        let gap = t - lastT
                        stats.maxGapMsWhileTouching = Swift.max(stats.maxGapMsWhileTouching, gap * 1000)
                        if gap < 0.1 { activeTime += gap; activeFrames += 1 }
                    }
                }
                for i in 0..<f.count {
                    let c = f[i]
                    if sequences[c.id] == nil { order.append(c.id) }
                    sequences[c.id, default: []].append(c.phase)
                    if c.phase == .touching {
                        sizes.append(c.size); majors.append(c.majorAxisMM); minors.append(c.minorAxisMM)
                        maxSize[c.id] = Swift.max(maxSize[c.id] ?? 0, c.size)
                    }
                }
                previousHadContacts = f.count > 0
                lastT = t
            default:
                break
            }
        }

        stats.durationSeconds = (lastT ?? 0) - (firstT ?? 0)
        stats.activeRateHz = activeTime > 0 ? Double(activeFrames) / activeTime : 0
        stats.contacts = order.count
        for id in order {
            let seq = sequences[id] ?? []
            guard let first = seq.firstIndex(of: .touching), let last = seq.lastIndex(of: .touching) else {
                stats.landingSequences["never touched: " + collapse(seq), default: 0] += 1
                continue
            }
            stats.landingSequences[collapse(Array(seq[..<first])).isEmpty ? "(touching at once)" : collapse(Array(seq[..<first])), default: 0] += 1
            let tail = Array(seq[(last + 1)...])
            stats.liftSequences[tail.isEmpty ? "vanished" : collapse(tail), default: 0] += 1
            stats.framesReportedAfterLift[tail.count, default: 0] += 1
        }
        stats.sizeTouching = Summary(sizes)
        stats.majorAxisTouching = Summary(majors)
        stats.minorAxisTouching = Summary(minors)
        stats.maxSizePerContact = Summary(Array(maxSize.values))
        return stats
    }

    private static func collapse(_ phases: [ContactPhase]) -> String {
        var out: [String] = []
        for p in phases where out.last != "\(p)" { out.append("\(p)") }
        return out.joined(separator: ",")
    }

    public var report: String {
        func dict<K: Comparable>(_ d: [K: Int]) -> String {
            d.sorted { $0.key < $1.key }.map { "    \($0.key): \($0.value)" }.joined(separator: "\n")
        }
        return """
        frames: \(frames) (\(framesWithContacts) with contacts, \(emptyFrames) empty, \(emptyFramesAfterContacts) empty right after contacts)
        duration: \(String(format: "%.1f", durationSeconds)) s, frame rate while touching: \(String(format: "%.1f", activeRateHz)) Hz, worst gap while touching: \(String(format: "%.1f", maxGapMsWhileTouching)) ms
        callback thread: QoS \(callbackQoS ?? "unknown"), precedence \(callbackPrecedence.map(String.init) ?? "unknown"), real-time policy \(callbackTimeConstraint.map { $0 ? "yes" : "no" } ?? "unknown")
        contacts: \(contacts)
        landing phase sequences:
        \(dict(landingSequences))
        lift phase sequences:
        \(dict(liftSequences))
        frames still reported after the last touching frame:
        \(dict(framesReportedAfterLift))
        size while touching: \(sizeTouching.text)
        max size per contact: \(maxSizePerContact.text)
        major axis while touching: \(majorAxisTouching.text)
        minor axis while touching: \(minorAxisTouching.text)
        """
    }
}
