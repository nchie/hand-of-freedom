import Foundation
import GestureCore

/// A key that, held while fingers land, leaves the gesture to macOS so the window under the pointer scrolls.
public enum ScrollModifier: String, Sendable, Equatable, Codable, CaseIterable {
    case none, fn, control, option, command, shift

    /// The CGEventFlags bit the key sets.
    public var mask: UInt64 {
        switch self {
        case .none: 0
        case .shift: 0x0002_0000
        case .control: 0x0004_0000
        case .option: 0x0008_0000
        case .command: 0x0010_0000
        case .fn: 0x0080_0000
        }
    }

    public var title: String {
        switch self {
        case .none: "None"
        case .fn: "Fn (Globe)"
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        case .shift: "Shift"
        }
    }
}

/// What the event gate swallows while the tool acts in a profile's app, and when it lets scrolling through.
public struct GateConfig: Sendable, Equatable, Codable {
    /// The trackpad's own two-finger scrolls (chat scrolling, native zoom). Swallowed so they do not fight the turn.
    public var swallowTrackpadScroll = true
    /// System gesture events (swipe, magnify, rotate).
    public var swallowGestureEvents = true
    /// Held while fingers land, routes the gesture to macOS scrolling instead of a drag.
    public var scrollModifier = ScrollModifier.none
    /// Reads the Hand of Freedom addon's marker to scroll game windows that take the mouse wheel, and to do
    /// nothing over other windows. Needs the addon and Screen Recording.
    public var scrollOverWindows = false

    public init() {}

    private enum CodingKeys: String, CodingKey { case swallowTrackpadScroll, swallowGestureEvents, scrollModifier, scrollOverWindows }

    /// Keys missing from an older file keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GateConfig()
        swallowTrackpadScroll = try c.decodeIfPresent(Bool.self, forKey: .swallowTrackpadScroll) ?? d.swallowTrackpadScroll
        swallowGestureEvents = try c.decodeIfPresent(Bool.self, forKey: .swallowGestureEvents) ?? d.swallowGestureEvents
        scrollModifier = (try? c.decodeIfPresent(ScrollModifier.self, forKey: .scrollModifier)) ?? d.scrollModifier
        scrollOverWindows = try c.decodeIfPresent(Bool.self, forKey: .scrollOverWindows) ?? d.scrollOverWindows
    }
}

/// Which apps the tool acts in, and how.
public struct Profile: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleIdentifiers: [String]
    public var enabled: Bool
    public var engine: EngineConfig
    public var gate: GateConfig

    public init(id: UUID = UUID(), name: String, bundleIdentifiers: [String], enabled: Bool = true,
                engine: EngineConfig = .default, gate: GateConfig = GateConfig()) {
        self.id = id
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.enabled = enabled
        self.engine = engine
        self.gate = gate
    }

    public static let worldOfWarcraftBundleID = "com.blizzard.worldofwarcraft"
    /// Fixed, so a reset produces the same profile.
    public static let worldOfWarcraftID = UUID(uuidString: "5B1D6C0E-4E57-4C2B-9F3A-0B57A7C0FFEE")!
}

public struct DiagnosticsSettings: Codable, Sendable, Equatable {
    /// Keeps the last `rollingSeconds` of trackpad data in memory so a moment can be saved as a clip for a
    /// bug report, and enables the save shortcut and session recording. Off unless the user turns it on.
    public var recordForBugReports = false
    public var rollingSeconds = 30
    public var verboseLogging = false

    public init() {}

    private enum CodingKeys: String, CodingKey { case recordForBugReports, rollingSeconds, verboseLogging }

    /// Keys missing from an older file keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DiagnosticsSettings()
        recordForBugReports = try c.decodeIfPresent(Bool.self, forKey: .recordForBugReports) ?? d.recordForBugReports
        rollingSeconds = try c.decodeIfPresent(Int.self, forKey: .rollingSeconds) ?? d.rollingSeconds
        verboseLogging = try c.decodeIfPresent(Bool.self, forKey: .verboseLogging) ?? d.verboseLogging
    }
}

public struct Settings: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = Settings.currentSchemaVersion
    public var enabled = true
    public var launchAtLogin = false
    /// A debug aid: act in whatever app is frontmost, with the first enabled profile.
    public var actInAllApps = false
    public var profiles: [Profile] = []
    public var diagnostics = DiagnosticsSettings()
    /// The trackpad-settings advisory was shown once and dismissed.
    public var dismissedTrackpadAdvisory = false
    /// The welcome window was finished once. It opens again on its own only when a required grant is missing.
    public var completedOnboarding = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, enabled, launchAtLogin, actInAllApps, profiles, diagnostics, dismissedTrackpadAdvisory, completedOnboarding
    }

    /// Top-level keys missing from an older file keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        actInAllApps = try c.decodeIfPresent(Bool.self, forKey: .actInAllApps) ?? d.actInAllApps
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? d.profiles
        diagnostics = try c.decodeIfPresent(DiagnosticsSettings.self, forKey: .diagnostics) ?? d.diagnostics
        dismissedTrackpadAdvisory = try c.decodeIfPresent(Bool.self, forKey: .dismissedTrackpadAdvisory) ?? d.dismissedTrackpadAdvisory
        completedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .completedOnboarding) ?? d.completedOnboarding
    }

    /// One profile for World of Warcraft with the default engine.
    public static func firstRun() -> Settings {
        var s = Settings()
        s.profiles = [Profile(id: Profile.worldOfWarcraftID, name: "World of Warcraft",
                              bundleIdentifiers: [Profile.worldOfWarcraftBundleID])]
        return s
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hand of Freedom", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// Problems that make a settings value unusable. Empty means valid.
    public var problems: [String] {
        var p: [String] = []
        if schemaVersion != Self.currentSchemaVersion { p.append("schema version \(schemaVersion), expected \(Self.currentSchemaVersion)") }
        for profile in profiles {
            let e = profile.engine
            if !(e.pointer.pxPerMM > 0 && e.pointer.pxPerMM <= 100) { p.append("\(profile.name): sensitivity out of range") }
            if !(e.zoom.mmPerTick > 0) { p.append("\(profile.name): zoom step must be positive") }
            if !(e.thresholds.dragStartMM > 0) { p.append("\(profile.name): drag start must be positive") }
        }
        return p
    }

    /// The profile the settings UI edits: the first one. Created if missing.
    public var primaryProfile: Profile {
        get { profiles.first ?? Settings.firstRun().profiles[0] }
        set {
            if profiles.isEmpty { profiles = [newValue] } else { profiles[0] = newValue }
        }
    }
}

/// Bundle identifier to profile. Pure.
public struct ProfileResolver: Sendable {
    public init() {}

    /// The first enabled profile listing the identifier; with `actInAllApps`, the first enabled profile for any app.
    public func resolve(bundleID: String?, in settings: Settings) -> Profile? {
        let enabled = settings.profiles.filter(\.enabled)
        if settings.actInAllApps { return enabled.first }
        guard let id = bundleID else { return nil }
        return enabled.first { $0.bundleIdentifiers.contains(id) }
    }
}
