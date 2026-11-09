import Foundation
import GestureCore

struct Options {
    var positional: [String] = []
    var flags: Set<String> = []
    var values: [String: String] = [:]

    static let valued: Set<String> = ["--seconds", "--config", "--sens", "--record", "--out"]

    init(_ args: [String]) throws {
        var i = 0
        while i < args.count {
            let a = args[i]
            if Self.valued.contains(a) {
                guard i + 1 < args.count else { throw CLIError("\(a) needs a value") }
                values[a] = args[i + 1]
                i += 2
            } else if a.hasPrefix("--") {
                flags.insert(a)
                i += 1
            } else {
                positional.append(a)
                i += 1
            }
        }
    }

    func has(_ flag: String) -> Bool { flags.contains(flag) }

    var seconds: Double? { values["--seconds"].flatMap(Double.init) }

    /// Default config, or a JSON EngineConfig from --config, with --sens applied on top.
    func engineConfig() throws -> EngineConfig {
        var config = EngineConfig.default
        if let path = values["--config"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            config = try JSONDecoder().decode(EngineConfig.self, from: data)
        }
        if let s = values["--sens"] {
            guard let v = Float(s), v > 0 else { throw CLIError("--sens needs a positive number") }
            config.pointer.pxPerMM = v
        }
        return config
    }
}

struct CLIError: Error, CustomStringConvertible {
    var description: String
    init(_ d: String) { description = d }
}
