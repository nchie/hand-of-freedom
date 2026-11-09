import AppKit
import Foundation

/// Installs the Hand of Freedom addon, which draws the marker, into the game's AddOns folder.
public struct AddonInstaller: Sendable {
    public static let folderName = "HandOfFreedom"

    public enum State: Sendable, Equatable {
        /// The app has no copy of the addon (run from a plain build rather than the bundle).
        case notBundled
        /// The game is not installed where macOS can find it.
        case gameNotFound
        case notInstalled
        /// Installed, but a different version than the app's.
        case outdated
        case installed
    }

    /// The addon folder shipped with the app.
    public var bundled: URL?
    /// The game's `Interface/AddOns` folder.
    public var addOns: URL?

    public init(bundled: URL?, addOns: URL?) {
        self.bundled = bundled
        self.addOns = addOns
    }

    /// The app's copy (Contents/Resources/Addon/HandOfFreedom) and the AddOns folder of the game,
    /// found from the running game or from Launch Services.
    public static func forApp(bundleIdentifier: String = Profile.worldOfWarcraftBundleID) -> AddonInstaller {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Addon/\(folderName)", isDirectory: true)
        let game = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        let addOns = game?.deletingLastPathComponent().appendingPathComponent("Interface/AddOns", isDirectory: true)
        return AddonInstaller(bundled: bundled, addOns: addOns)
    }

    public var target: URL? { addOns?.appendingPathComponent(Self.folderName, isDirectory: true) }

    public var state: State {
        guard let bundled, let ours = Self.version(in: bundled) else { return .notBundled }
        guard let addOns, FileManager.default.fileExists(atPath: addOns.deletingLastPathComponent().path) else { return .gameNotFound }
        guard let target, let theirs = Self.version(in: target) else { return .notInstalled }
        return theirs == ours ? .installed : .outdated
    }

    /// Copies the app's addon over whatever is installed.
    public func install() throws {
        guard let bundled, let addOns, let target else { throw CocoaError(.fileNoSuchFile) }
        let fm = FileManager.default
        try fm.createDirectory(at: addOns, withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: bundled, to: target)
    }

    /// The `## Version:` line of the folder's .toc file.
    static func version(in folder: URL) -> String? {
        let toc = folder.appendingPathComponent("\(folderName).toc")
        guard let text = try? String(contentsOf: toc, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("## Version:") {
            return line.dropFirst("## Version:".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
