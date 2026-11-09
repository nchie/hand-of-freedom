/// Everything that decides whether the tool acts. Assembled on the main actor by `PipelineController`.
public struct ActivationInputs: Sendable, Equatable {
    public var enabled = true
    public var targetFrontmost = false
    public var injectorHealthy = true
    /// The event gate is part of acting: without it the trackpad's own scrolls reach the game too.
    public var tapRequired = true
    public var tapInstalled = false
    public var permissions = PermissionSnapshot.allGranted
    /// The grants posted input needs: Accessibility, as measured.
    public var postingRequires: [Permission] = [.accessibility]

    public init() {}
}

/// Why the tool is not acting, in the order a user should fix them.
public enum ActivationBlocker: Sendable, Equatable, CustomStringConvertible {
    case disabled
    case missingPermission(Permission)
    case injectorUnavailable
    case gateNotInstalled
    case targetNotFrontmost

    public var description: String {
        switch self {
        case .disabled: "disabled"
        case .missingPermission(let p): "\(p) permission missing"
        case .injectorUnavailable: "injector unavailable"
        case .gateNotInstalled: "event gate not installed"
        case .targetNotFrontmost: "game not frontmost"
        }
    }
}

/// The one definition of "acting". When it is false the gate passes every event and the engine injects
/// nothing, but keeps tracking. Pure.
public enum ActivationRule {
    public static func blockers(_ i: ActivationInputs) -> [ActivationBlocker] {
        var b: [ActivationBlocker] = []
        if !i.enabled { b.append(.disabled) }
        for p in i.postingRequires where i.permissions[p] != .granted { b.append(.missingPermission(p)) }
        if !i.injectorHealthy { b.append(.injectorUnavailable) }
        if i.tapRequired && !i.tapInstalled { b.append(.gateNotInstalled) }
        if !i.targetFrontmost { b.append(.targetNotFrontmost) }
        return b
    }

    public static func isActive(_ i: ActivationInputs) -> Bool { blockers(i).isEmpty }
}
