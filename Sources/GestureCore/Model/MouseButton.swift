public enum MouseButton: UInt8, Sendable, Codable, CaseIterable, BitwiseCopyable {
    case left = 0, right = 1, middle = 2
}

/// What a finger count maps to. Explicit so a settings file always states every count; `off` is visible.
public enum ButtonChoice: String, Sendable, Codable, CaseIterable, BitwiseCopyable {
    case off, left, right, middle

    public var button: MouseButton? {
        switch self {
        case .off: nil
        case .left: .left
        case .right: .right
        case .middle: .middle
        }
    }
}
