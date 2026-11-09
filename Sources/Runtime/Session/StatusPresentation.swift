import GestureCore

/// What the menu bar shows for a status: an SF Symbol, whether it is dimmed, and one line of text. Pure.
public struct StatusPresentation: Sendable, Equatable {
    public enum Symbol: String, Sendable {
        case attention = "exclamationmark.triangle.fill"
        case disabled = "hand.raised.slash"
        case waiting = "hand.point.up.left"
        case ready = "hand.point.up.left.fill"
        case dragging = "hand.draw.fill"
    }

    public var symbol: Symbol
    public var dimmed: Bool
    public var headline: String
    /// Something the user has to fix; the menu offers the welcome window.
    public var needsAttention: Bool { symbol == .attention }

    public init(symbol: Symbol, dimmed: Bool, headline: String) {
        self.symbol = symbol
        self.dimmed = dimmed
        self.headline = headline
    }

    /// `targetName` names the app the tool waits for when no profile matches the frontmost app.
    public static func make(_ s: PipelineStatus, phase: EngineState.Phase, targetName: String) -> StatusPresentation {
        if s.blockers.contains(.disabled) { return .init(symbol: .disabled, dimmed: false, headline: "Disabled") }
        if s.blockers.contains(where: { if case .missingPermission = $0 { true } else { false } }) {
            return .init(symbol: .attention, dimmed: false, headline: "Accessibility permission needed")
        }
        if s.blockers.contains(.injectorUnavailable) {
            return .init(symbol: .attention, dimmed: false, headline: "Can't send mouse input. Check Accessibility.")
        }
        if s.blockers.contains(.gateNotInstalled) {
            return .init(symbol: .attention, dimmed: false, headline: "Can't hold back trackpad scrolling. Check Accessibility.")
        }
        if s.trackpadDataSuspicious {
            return .init(symbol: .attention, dimmed: false, headline: "Trackpad data looks wrong on this macOS build")
        }
        if s.tapUnstable {
            return .init(symbol: .attention, dimmed: false, headline: "macOS keeps interrupting the trackpad. Check Accessibility.")
        }
        if s.asleep { return .init(symbol: .waiting, dimmed: true, headline: "Asleep") }
        if !s.active { return .init(symbol: .waiting, dimmed: true, headline: "Waiting for \(targetName)") }
        if s.touchStalled { return .init(symbol: .ready, dimmed: false, headline: "Trackpad stopped reporting; button released") }
        if case .dragging(let button, let members) = phase {
            return .init(symbol: .dragging, dimmed: false, headline: "Dragging \(button), \(members) fingers")
        }
        return .init(symbol: .ready, dimmed: false, headline: "Ready in \(s.profileName ?? targetName)")
    }
}
