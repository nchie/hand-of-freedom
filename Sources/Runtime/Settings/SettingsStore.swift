import Foundation
import Observation

/// Loads, validates and saves settings. Observers see changes synchronously; the file write is debounced.
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: Settings
    /// Why the file on disk was not used, if it was not. The UI shows it once.
    public private(set) var lastLoadProblem: String?
    public private(set) var lastSaveError: String?

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// A decode failure or invalid content copies the file to `settings.json.bak` and starts from `firstRun()`.
    public init(url: URL = Settings.defaultURL, debounce: Duration = .milliseconds(250)) {
        self.url = url
        self.debounce = debounce
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            settings = .firstRun()
            return
        }
        do {
            let loaded = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
            let problems = loaded.problems
            guard problems.isEmpty else { throw SettingsError.invalid(problems.joined(separator: "; ")) }
            settings = loaded
        } catch {
            let backup = url.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
            lastLoadProblem = "Settings could not be read (\(error)). They were reset; the old file is \(backup.lastPathComponent)."
            settings = .firstRun()
        }
    }

    /// Validates, applies and schedules a save. An invalid result is rejected and nothing changes.
    @discardableResult
    public func update(_ mutate: (inout Settings) -> Void) -> Bool {
        var s = settings
        mutate(&s)
        guard s.problems.isEmpty else { return false }
        guard s != settings else { return true }
        settings = s
        scheduleSave()
        return true
    }

    /// Writes now instead of after the debounce. Before quitting.
    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        write()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let delay = debounce
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: url, options: .atomic)
            lastSaveError = nil
        } catch {
            lastSaveError = "\(error)"
        }
    }
}

enum SettingsError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self {
        case .invalid(let s): "invalid: \(s)"
        }
    }
}
