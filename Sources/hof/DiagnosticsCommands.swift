import AppKit
import Foundation
import GestureCore
import PlatformBackends
import Runtime

/// `hof permissions`: what this process has been granted. Reads only, unless `--request`.
@MainActor
func permissionsCommand(_ options: Options) {
    let checks = SystemPermissionChecks()
    if options.has("--request") {
        let missing = checks.snapshot().missing
        if missing.isEmpty { print("Nothing to request.") } else { checks.request(missing) }
    }
    print(permissionReport(checks.snapshot()))
}

func permissionReport(_ s: PermissionSnapshot) -> String {
    Permission.allCases.map { p in
        let label = switch p {
        case .accessibility: "Accessibility (AXIsProcessTrusted)"
        case .inputMonitoring: "Input Monitoring (CGPreflightListenEventAccess)"
        case .postEvents: "Post events (CGPreflightPostEventAccess)"
        }
        return "  \(s[p] == .granted ? "✓" : "✗") \(label)"
    }.joined(separator: "\n")
}

/// `hof probe`: moves the pointer one pixel and back through IOHIDPostEvent and waits for the echo.
@MainActor
func probeCommand(_ options: Options) async {
    print("Injector probe: \(await runProbe(ignoringPreflight: options.has("--force")))")
}

/// Posts the probe. `ignoringPreflight` posts even when Accessibility looks missing, to measure what
/// really happens without it.
@MainActor
func runProbe(ignoringPreflight: Bool) async -> ProbeResult {
    let injector = IOHIDInjector()
    do { try injector.open() } catch { return .postFailed(-1) }
    defer { injector.close() }
    let thread = TapThread()
    thread.start {}
    defer { thread.stop() }
    let listener = MoveEchoTap(runLoop: thread.runLoop!)
    let snapshot = SystemPermissionChecks().snapshot()
    let permitted = ignoringPreflight || snapshot.accessibility == .granted
    let canListen = ignoringPreflight || snapshot.inputMonitoring == .granted
    return await InjectorProbe(timeout: .milliseconds(200)).run(injector: injector, listener: listener,
                                                                flags: SharedFlags(), permitted: permitted,
                                                                canListen: canListen)
}

/// Posts a five-pixel relative move, reads the cursor position, and moves back. Reading the cursor needs
/// no permission, so this tells whether posting works even when the probe cannot listen.
@MainActor
func cursorMoveTest() async -> String {
    let injector = IOHIDInjector()
    do { try injector.open() } catch { return "injector did not open: \(error)" }
    defer { injector.close() }
    func location() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
    for dx: Int32 in [5, -5] {                         // the other way if the cursor sits at an edge
        let before = location()
        let rc = injector.move(dx: dx, dy: 0, held: nil)
        try? await Task.sleep(for: .milliseconds(60))
        let after = location()
        if rc != 0 { return "posting returned \(rc)" }
        if after != before {
            _ = injector.move(dx: -dx, dy: 0, held: nil)
            return "yes, moved \(Int((after.x - before.x).rounded())) px for \(dx) posted"
        }
    }
    return "no: posted without error, but the cursor did not move"
}

/// `hof check`: the permission isolation report. Run from the bundle so the grants are the app's own.
/// Tries each capability for real instead of trusting the preflight calls.
@MainActor
func checkCommand(_ options: Options) async {
    let checks = SystemPermissionChecks()
    if options.has("--request") { checks.request(Permission.allCases) }
    var lines: [String] = []
    lines.append("hof check, \(Date().formatted(date: .numeric, time: .standard))")
    lines.append("bundle \(Bundle.main.bundleIdentifier ?? "none (run from a terminal: the terminal's grants apply)"), pid \(getpid())")
    lines.append("preflight:")
    lines.append(permissionReport(checks.snapshot()))

    // The gate: a real HID-level default tap, installed with acting off, so it passes every event.
    let thread = TapThread()
    thread.start {}
    let tap = EventTap(flags: ActivationFlags()) { _ in false }
    do throws(TapError) {
        try tap.install(on: thread.runLoop!)
        lines.append("event gate (HID default tap): installs")
        tap.uninstall()
    } catch {
        lines.append("event gate (HID default tap): fails, \(error)")
    }
    thread.stop()

    let probe = await runProbe(ignoringPreflight: true)
    lines.append("posting, echo heard by a listening tap (needs Input Monitoring to listen): \(probe)")
    lines.append("posting, cursor actually moved (needs no permission to observe): \(await cursorMoveTest())")

    let report = lines.joined(separator: "\n")
    print(report)
    if let out = options.values["--out"] {
        try? (report + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}
