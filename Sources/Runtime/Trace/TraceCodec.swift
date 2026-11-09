import Foundation
import GestureCore

/// JSON Lines encoding of traces. One object per line.
/// Floats are written in Swift's shortest round-trip form, so a frame decodes to exactly what was recorded.
public enum TraceCodec {
    public static func headerLine(_ header: TraceHeader) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(header)) ?? Data("{}".utf8), as: UTF8.self)
    }

    public static func line(_ event: TraceEvent, t0: UInt64) -> String {
        switch event {
        case .frame(let f):
            var contacts: [String] = []
            for i in 0..<f.count {
                let c = f[i]
                contacts.append("[\(c.id),\(c.phase.rawValue),\(c.positionMM.x),\(c.positionMM.y),\(c.velocityMM.x),\(c.velocityMM.y),"
                                + "\(c.normalized.x),\(c.normalized.y),\(c.size),\(c.majorAxisMM),\(c.minorAxisMM),\(c.angle)]")
            }
            return "{\"k\":\"frame\",\"t\":\(t(f.entryNanos, t0)),\"dev\":\(f.deviceTimestamp),\"seq\":\(f.sequence),\"c\":[\(contacts.joined(separator: ","))]}"

        case .output(let o, let entry, let us):
            var fields = ["\"k\":\"out\"", "\"t\":\(t(entry, t0))", "\"us\":\(us)"]
            if let b = o.release { fields.append("\"release\":\"\(b)\"") }
            if let b = o.press { fields.append("\"press\":\"\(b)\"") }
            if let b = o.held { fields.append("\"held\":\"\(b)\"") }
            if o.movePx != .zero { fields.append("\"move\":[\(o.movePx.x),\(o.movePx.y)]") }
            if o.scrollTicks != 0 { fields.append("\"scroll\":\(o.scrollTicks)") }
            return "{" + fields.joined(separator: ",") + "}"

        case .inject(let op, let button, let value, let rc, let entry, let us):
            var fields = ["\"k\":\"inj\"", "\"t\":\(t(entry, t0))", "\"us\":\(us)", "\"op\":\"\(op)\""]
            if let button { fields.append("\"b\":\"\(button)\"") }
            if op == .move { fields.append("\"v\":[\(value.x),\(value.y)]") }
            if op == .scroll { fields.append("\"v\":\(value.y)") }
            fields.append("\"rc\":\(rc)")
            return "{" + fields.joined(separator: ",") + "}"

        case .state(let tr, let entry, let us):
            return "{\"k\":\"state\",\"t\":\(t(entry, t0)),\"us\":\(us),\"from\":\"\(tr.from.traceName)\",\"to\":\"\(tr.to.traceName)\"}"

        case .flag(let active, let entry):
            return "{\"k\":\"flag\",\"t\":\(t(entry, t0)),\"targetActive\":\(active)}"

        case .route(let route, let entry):
            return routeLine(route, tSeconds: seconds(entry, since: t0))

        case .reset(let request, let entry):
            return "{\"k\":\"reset\",\"t\":\(t(entry, t0)),\"req\":\"\(request)\"}"
        }
    }

    public static func flagLine(active: Bool, tSeconds: Double) -> String {
        "{\"k\":\"flag\",\"t\":\(format(tSeconds)),\"targetActive\":\(active)}"
    }

    public static func routeLine(_ route: GestureRoute, tSeconds: Double) -> String {
        "{\"k\":\"route\",\"t\":\(format(tSeconds)),\"route\":\"\(route.traceName)\"}"
    }

    public static func sysLine(qos: String, precedence: Int32, timeConstraint: Bool, tSeconds: Double) -> String {
        "{\"k\":\"sys\",\"t\":\(format(tSeconds)),\"callbackQoS\":\"\(qos)\",\"precedence\":\(precedence),\"timeConstraint\":\(timeConstraint)}"
    }

    public static func configLine(_ config: EngineConfig, tSeconds: Double) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: (try? encoder.encode(config)) ?? Data("{}".utf8), as: UTF8.self)
        return "{\"k\":\"cfg\",\"t\":\(format(tSeconds)),\"config\":\(json)}"
    }

    public static func noteLine(_ message: String, tSeconds: Double) -> String {
        let escaped = (try? JSONSerialization.data(withJSONObject: [message], options: [.fragmentsAllowed]))
            .map { String(decoding: $0, as: UTF8.self).dropFirst().dropLast() } ?? "\"\""
        return "{\"k\":\"note\",\"t\":\(format(tSeconds)),\"msg\":\(escaped)}"
    }

    public static func seconds(_ entry: UInt64, since t0: UInt64) -> Double {
        Double(Int64(bitPattern: entry &- t0)) / 1e9
    }

    private static func t(_ entry: UInt64, _ t0: UInt64) -> String { format(seconds(entry, since: t0)) }

    private static func format(_ seconds: Double) -> String { String(format: "%.6f", seconds) }
}
