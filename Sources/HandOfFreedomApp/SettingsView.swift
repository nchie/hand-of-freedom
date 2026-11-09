import GestureCore
import Runtime
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings(model: model) }
            Tab("Gestures", systemImage: "hand.draw") { GestureSettings(model: model) }
            Tab("Diagnostics", systemImage: "stethoscope") { DiagnosticsView(model: model) }
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}

private struct GeneralSettings: View {
    let model: AppModel

    var body: some View {
        let s = model.status
        Form {
            Section("Status") {
                Label(model.presentation.headline, systemImage: model.presentation.symbol.rawValue)
                if let error = model.startError { Text(error).foregroundStyle(.red) }
                if s.permissions.accessibility != .granted {
                    HStack {
                        Text("Accessibility is required to post input to the game.")
                        Spacer()
                        Button("Grant…") { model.requestAccessibility() }
                    }
                } else if !s.tapInstalled {
                    HStack {
                        Text("Accessibility is granted, but macOS applies it to a fresh launch.")
                        Spacer()
                        Button("Relaunch") { model.relaunch() }
                    }
                }
                Text("Can't see the menu bar icon? It may be hidden under the notch. Open Hand of Freedom again from Applications or Spotlight to get back here.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Toggle("Enabled", isOn: model.binding(\.enabled))
            Toggle("Launch at login", isOn: Binding(get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                                                    set: { model.setLaunchAtLogin($0) }))
            if model.loginStatus == .requiresApproval {
                HStack {
                    Text("Allow Hand of Freedom in Login Items to finish.").foregroundStyle(.secondary)
                    Button("Open Login Items") { LoginItem.openSystemSettings() }
                }
            }
            if let e = model.loginError { Text(e).foregroundStyle(.red) }
            Toggle("Act in all apps", isOn: model.binding(\.actInAllApps))
            Text("For testing outside the game. Normally the tool acts only while World of Warcraft is frontmost.")
                .font(.callout).foregroundStyle(.secondary)
            if let problem = model.store.lastLoadProblem {
                Text(problem).font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GestureSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Camera") {
                LabeledContent("Sensitivity") {
                    Slider(value: model.doubleBinding(\AppSettings.primaryProfile.engine.pointer.pxPerMM), in: 4...30, step: 0.5)
                    Text(String(format: "%.1f", model.settings.primaryProfile.engine.pointer.pxPerMM)).monospacedDigit().frame(width: 34)
                }
                Toggle("Invert vertical", isOn: model.binding(\AppSettings.primaryProfile.engine.pointer.invertY))
            }
            Section("Fingers") {
                buttonPicker("Two fingers", \AppSettings.primaryProfile.engine.mapping.twoFingers)
                buttonPicker("Three fingers", \AppSettings.primaryProfile.engine.mapping.threeFingers)
                buttonPicker("Four fingers", \AppSettings.primaryProfile.engine.mapping.fourFingers)
                Text("Right turns the character, left orbits the camera. Four fingers are left to macOS by default.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Scrolling") {
                Toggle("Scroll game windows automatically", isOn: model.binding(\AppSettings.primaryProfile.gate.scrollOverWindows))
                Text("Over a window that scrolls, like the chat or a list, a two-finger swipe scrolls it; over other windows it does nothing. A small addon shows the app what is under the mouse in a few pixels hidden behind the notch.")
                    .font(.callout).foregroundStyle(.secondary)
                if model.settings.primaryProfile.gate.scrollOverWindows {
                    MarkerSetup(model: model)
                }
                Picker("Hold to scroll", selection: model.binding(\AppSettings.primaryProfile.gate.scrollModifier)) {
                    ForEach(ScrollModifier.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Hold this key as your fingers land to scroll the window under the pointer instead of turning. The game sees the key too, except Fn: with Shift held, for example, it gets a Shift-scroll.")
                    .font(.callout).foregroundStyle(.secondary)
                if model.settings.primaryProfile.gate.scrollModifier == .fn {
                    Text("If pressing Fn on its own opens the emoji picker or switches the input source, set “Press 🌐 key to” to “Do Nothing” in System Settings › Keyboard.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Pinch zoom") {
                Toggle("Pinch to zoom", isOn: model.binding(\AppSettings.primaryProfile.engine.zoom.enabled))
                LabeledContent("Zoom step") {
                    Slider(value: model.doubleBinding(\AppSettings.primaryProfile.engine.zoom.mmPerTick), in: 1.5...6, step: 0.25)
                    Text(String(format: "%.2f mm", model.settings.primaryProfile.engine.zoom.mmPerTick)).monospacedDigit().frame(width: 64)
                }
                Text("Finger spread per zoom step. Smaller zooms faster.").font(.callout).foregroundStyle(.secondary)
                Toggle("Invert zoom", isOn: model.binding(\AppSettings.primaryProfile.engine.zoom.invert))
            }
            Section("While the game is in front") {
                Toggle("Hold back trackpad scrolling", isOn: model.binding(\AppSettings.primaryProfile.gate.swallowTrackpadScroll))
                Toggle("Hold back system gestures", isOn: model.binding(\AppSettings.primaryProfile.gate.swallowGestureEvents))
                Text("Two-finger scrolling would otherwise scroll chat and zoom while you turn. Turning these off is for diagnosis.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Button("Reset Gestures to Defaults") {
                    model.update {
                        $0.primaryProfile.engine = .default
                        $0.primaryProfile.gate = GateConfig()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func buttonPicker(_ title: String, _ path: WritableKeyPath<AppSettings, ButtonChoice>) -> some View {
        Picker(title, selection: model.binding(path)) {
            Text("Off").tag(ButtonChoice.off)
            Text("Right button (turn)").tag(ButtonChoice.right)
            Text("Left button (orbit)").tag(ButtonChoice.left)
            Text("Middle button").tag(ButtonChoice.middle)
        }
    }
}

/// Recording for bug reports, its clips, and live engine and health details.
private struct DiagnosticsView: View {
    let model: AppModel
    @State private var clips: [URL] = []
    @State private var tick = 0
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        let recording = model.settings.diagnostics.recordForBugReports
        Form {
            Section("Bug reports") {
                Toggle("Record trackpad data for bug reports", isOn: model.binding(\.diagnostics.recordForBugReports))
                Text("Keeps the last \(model.settings.diagnostics.rollingSeconds) seconds of trackpad data in memory. When a gesture feels wrong in the game, press \(HotKey.saveClip.label) to save them as a clip you can attach to a bug report; a short sound confirms it. Nothing is written to disk until you save.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if recording {
                    if let problem = model.hotKeyProblem { Text(problem).foregroundStyle(.orange) }
                    HStack {
                        Button("Save Last \(model.settings.diagnostics.rollingSeconds) Seconds") { model.saveClip(); refreshSoon() }
                        Button(model.isRecordingSession ? "Stop Recording Session" : "Record Session") { model.toggleSession(); refreshSoon() }
                        Spacer()
                        Button("Show in Finder") { model.showClipsInFinder() }
                    }
                    if let message = model.lastClipMessage { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
            }
            if recording {
                Section("Recent clips") {
                    if clips.isEmpty {
                        Text("None yet.").foregroundStyle(.secondary)
                    }
                    ForEach(clips, id: \.self) { clip in
                        ClipRow(model: model, clip: clip)
                    }
                }
            }
            details
        }
        .formStyle(.grouped)
        .onAppear { clips = model.recentClips() }
        .onChange(of: model.lastClipMessage) { refreshSoon() }
        .onReceive(timer) { _ in tick &+= 1 }
    }

    /// Refreshed four times a second by `tick`.
    @ViewBuilder private var details: some View {
        let _ = tick
        let d = model.diagnostics
        let live = model.liveState
        let s = model.status
        Section("Now") {
            LabeledContent("Status", value: model.presentation.headline)
            LabeledContent("Fingers", value: "\(live.countedFingers) counted, \(live.rawTouching) touching")
            LabeledContent("Engine", value: phaseText(live.phase))
            LabeledContent("Frontmost app", value: s.frontmost ?? "none")
        }
        Section("Health") {
            LabeledContent("Accessibility", value: s.permissions.accessibility == .granted ? "granted" : "missing")
            LabeledContent("Mouse input", value: s.injector.isHealthy ? "working" : "failing")
            LabeledContent("Trackpad takeover", value: s.tapInstalled ? (s.tapUnstable ? "on, interrupted often" : "on") : "off")
            LabeledContent("Rejected trackpad contacts", value: "\(d.rejectedContacts)")
        }
        Section("Since launch") {
            LabeledContent("Trackpad frames", value: "\(d.frames)")
            LabeledContent("Worst frame", value: "\(d.worstFrameMicros) µs")
            LabeledContent("Callback thread", value: d.callbackThread)
            LabeledContent("Events held back", value: "\(d.swallowed)")
            LabeledContent("Takeover re-enabled", value: "\(d.reenables) times")
            LabeledContent("Trace events dropped", value: "\(d.ringDrops)")
        }
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            clips = model.recentClips()
        }
    }
}

private struct ClipRow: View {
    let model: AppModel
    let clip: URL
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clip.lastPathComponent.replacingOccurrences(of: ".hoftrace.jsonl", with: ""))
                .font(.callout.monospaced())
            TextField("What felt wrong, and what did you expect?", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .onSubmit { model.setNote(note, for: clip) }
        }
        .onAppear { note = model.note(for: clip) }
        .onDisappear { model.setNote(note, for: clip) }
        .onChange(of: note) { model.setNote(note, for: clip) }
    }
}

/// The addon, Screen Recording and the live marker reading, each with the button that fixes it.
private struct MarkerSetup: View {
    let model: AppModel

    var body: some View {
        LabeledContent("Addon") {
            Group {
                switch model.addonState {
                case .installed: Text("Installed")
                case .notInstalled: Button("Install") { model.installAddon() }
                case .outdated: Button("Update") { model.installAddon() }
                case .gameNotFound: Text("World of Warcraft not found").foregroundStyle(.orange)
                case .notBundled: Text("Not in this build").foregroundStyle(.orange)
                }
            }
            .onAppear { model.refreshAddonState() }
        }
        if let error = model.addonError { Text(error).font(.callout).foregroundStyle(.red) }
        LabeledContent("Screen Recording") {
            if model.status.marker == .needsScreenRecording {
                Button("Allow…") { model.requestScreenRecording() }
            } else {
                Text("Allowed")
            }
        }
        if model.status.marker == .needsScreenRecording {
            Text("Only a small strip at the top of the game's window is read, never the rest of the screen. If it still says Allow after you turned it on, quit and reopen Hand of Freedom.")
                .font(.callout).foregroundStyle(.secondary)
        }
        LabeledContent("Under the mouse", value: markerText)
        if model.status.marker == .notSeen {
            Text("The game shows no marker yet. Type /reload in the game, or turn on Hand of Freedom under AddOns at character select.")
                .font(.callout).foregroundStyle(.secondary)
                .onAppear { model.refreshAddonState() }
        }
    }

    private var markerText: String {
        switch model.status.marker {
        case .off, .needsScreenRecording: "—"
        case .waitingForGame: "Waiting for the game"
        case .starting: "Starting…"
        case .failed(let message): "Not reading: \(message)"
        case .notSeen: "No marker"
        case .seen(.world): "The world (turns)"
        case .seen(.scrollable): "A scrolling window (scrolls)"
        case .seen(.window): "A window (does nothing)"
        }
    }
}
