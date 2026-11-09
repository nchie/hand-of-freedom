import GestureCore
import PlatformBackends

/// Where automatic scrolling over game windows stands, for the settings UI.
public enum MarkerStatus: Sendable, Equatable {
    /// The setting is off.
    case off
    /// The app needs Screen Recording to read the marker.
    case needsScreenRecording
    /// On, but the tool is not acting in the game right now.
    case waitingForGame
    case starting
    /// The capture could not start; it is retried every few seconds.
    case failed(String)
    /// Capturing, but the marker is not in the picture: the addon is missing, disabled or not loaded yet.
    case notSeen
    case seen(MarkerState)
}

extension MarkerState {
    /// What a gesture starting over this does.
    public var route: GestureRoute {
        switch self {
        case .world: .drive
        case .scrollable: .scroll
        case .window: .ignore
        }
    }

    init(route: GestureRoute) {
        self = switch route {
        case .drive: .world
        case .scroll: .scrollable
        case .ignore: .window
        }
    }
}
