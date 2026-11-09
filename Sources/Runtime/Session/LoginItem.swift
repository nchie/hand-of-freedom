import ServiceManagement

/// Launch at login through SMAppService. `status` is the truth the UI shows, not the setting.
@MainActor
public enum LoginItem {
    public enum Status: Sendable, Equatable {
        case enabled
        /// Registered, but the user has to allow it in System Settings > General > Login Items.
        case requiresApproval
        case notRegistered
        /// The system cannot find the app, usually because the bundle moved.
        case notFound
    }

    public static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        default: .notRegistered
        }
    }

    /// Registers or unregisters, and returns the resulting status or the error message.
    public static func set(_ on: Bool) -> Result<Status, LoginItemError> {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return .success(status)
        } catch {
            return .failure(LoginItemError(message: error.localizedDescription))
        }
    }

    public static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

public struct LoginItemError: Error, Sendable, Equatable {
    public var message: String
}
