import GestureCore
import Runtime
import SwiftUI

/// First run and "Fix…": the Accessibility grant, a live finger readout, and the trackpad advisory.
struct WelcomeView: View {
    static let windowID = "welcome"
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = model.status
        VStack(alignment: .leading, spacing: 18) {
            Text("Hand of Freedom turns trackpad swipes into camera control in World of Warcraft: two fingers turn, three fingers orbit, pinch zooms. It acts only while the game is in front.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    row(granted: s.permissions.accessibility == .granted,
                        title: "Accessibility (required)",
                        detail: "Lets the tool post mouse input to the game and hold back the trackpad's own scrolling while it does.") {
                        Button("Grant…") { model.requestAccessibility() }
                    }
                    if s.permissions.accessibility == .granted && !s.tapInstalled {
                        row(granted: false, title: "Restart needed",
                            detail: "The permission is granted, but macOS applies it to a fresh launch.") {
                            Button("Relaunch") { model.relaunch() }
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("Try it") {
                TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                    let live = model.liveState
                    HStack {
                        Text("\(live.countedFingers)")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 44)
                        VStack(alignment: .leading) {
                            Text(live.countedFingers == 1 ? "finger counted" : "fingers counted")
                            Text(phaseText(live.phase)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(6)
                }
                Text("Rest a palm or thumb on the trackpad: it should not count. Nothing is sent to other apps.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], 6)
            }

            ForEach(Array(model.trackpadConflicts.enumerated()), id: \.offset) { _, conflict in
                Label(conflict.advice, systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Hand of Freedom lives in the menu bar as a hand icon. If you can't see it, it may be hidden under the notch: open Hand of Freedom again from Applications or Spotlight to show its settings.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Done") {
                    model.update { $0.completedOnboarding = true }
                    dismissWindow(id: Self.windowID)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear {
            let open = openWindow
            model.openWelcomeWindow = { open(id: Self.windowID); NSApp.activate() }
        }
    }

    private func row(granted: Bool, title: String, detail: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted { action() }
        }
    }
}

func phaseText(_ phase: EngineState.Phase) -> String {
    switch phase {
    case .idle: "idle"
    case .armed(let n): "\(n) fingers down, waiting for movement"
    case .dragging(let b, let n): "would hold \(b) with \(n) fingers"
    case .suspended: "lift all fingers to start again"
    case .scrolling: "scrolling the window under the pointer"
    case .ignoring: "over a game window, doing nothing"
    }
}
