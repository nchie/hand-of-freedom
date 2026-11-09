import Foundation
import GestureCore
import PlatformBackends

/// First line of every trace. Everything needed to replay it and to read it in a bug report.
public struct TraceHeader: Codable, Sendable, Equatable {
    public var k = "header"
    public var v = 1
    public var tool: String
    public var app: String
    public var os: String
    public var model: String
    public var devices: [TouchDeviceInfo]
    public var config: EngineConfig
    /// mach nanoseconds that `t` in every other line is measured from.
    public var t0Nanos: UInt64

    public init(tool: String, devices: [TouchDeviceInfo], config: EngineConfig, t0Nanos: UInt64) {
        self.tool = tool
        self.app = SystemInfo.appVersion
        self.os = SystemInfo.osVersion
        self.model = SystemInfo.model
        self.devices = devices
        self.config = config
        self.t0Nanos = t0Nanos
    }
}

public enum SystemInfo {
    public static let appVersion = "0.6.0-dev"

    public static var osVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }

    public static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
