import Foundation
import Testing
import GestureCore
import Runtime

@MainActor
@Suite("Settings")
struct SettingsTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hof-settings-\(UUID().uuidString)")
    var url: URL { dir.appendingPathComponent("settings.json") }

    @Test func firstRunHasOneWorldOfWarcraftProfile() {
        let store = SettingsStore(url: url)
        #expect(store.settings == .firstRun())
        #expect(store.settings.profiles.map(\.bundleIdentifiers) == [[Profile.worldOfWarcraftBundleID]])
        #expect(store.lastLoadProblem == nil)
    }

    @Test func changesAreSavedAndReloaded() async throws {
        let store = SettingsStore(url: url, debounce: .milliseconds(1))
        store.update { $0.primaryProfile.engine.pointer.pxPerMM = 14 }
        store.flush()
        let again = SettingsStore(url: url)
        #expect(again.settings.primaryProfile.engine.pointer.pxPerMM == 14)
    }

    @Test func invalidUpdatesAreRejected() {
        let store = SettingsStore(url: url)
        #expect(!store.update { $0.primaryProfile.engine.pointer.pxPerMM = 0 })
        #expect(store.settings == .firstRun())
    }

    @Test func aBrokenFileIsBackedUpAndReplaced() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let store = SettingsStore(url: url)
        #expect(store.settings == .firstRun())
        #expect(store.lastLoadProblem != nil)
        #expect(try String(contentsOf: url.appendingPathExtension("bak"), encoding: .utf8) == "{ not json")
    }

    @Test func aFutureSchemaIsNotTrusted() throws {
        var s = Settings.firstRun()
        s.schemaVersion = 2
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(s).write(to: url)
        let store = SettingsStore(url: url)
        #expect(store.settings == .firstRun())
        #expect(store.lastLoadProblem?.contains("schema") == true)
    }

    @Test func resolverPicksTheFirstEnabledProfileForTheApp() {
        var s = Settings.firstRun()
        let wow = s.profiles[0]
        var other = Profile(name: "Other", bundleIdentifiers: ["com.example.game"])
        #expect(ProfileResolver().resolve(bundleID: Profile.worldOfWarcraftBundleID, in: s) == wow)
        #expect(ProfileResolver().resolve(bundleID: "com.apple.finder", in: s) == nil)
        #expect(ProfileResolver().resolve(bundleID: nil, in: s) == nil)
        s.profiles[0].enabled = false
        #expect(ProfileResolver().resolve(bundleID: Profile.worldOfWarcraftBundleID, in: s) == nil)
        other.enabled = true
        s.profiles.append(other)
        s.actInAllApps = true
        #expect(ProfileResolver().resolve(bundleID: "com.apple.finder", in: s) == other)
    }
}
