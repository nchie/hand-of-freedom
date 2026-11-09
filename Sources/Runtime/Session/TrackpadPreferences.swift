import CoreFoundation

/// macOS trackpad settings that clash with the tool's gestures.
public enum TrackpadConflict: Sendable, Equatable {
    /// Accessibility's three-finger drag turns three-finger swipes into real mouse drags, which the gate cannot stop.
    case threeFingerDrag
    /// Three-finger swipes switch spaces or open Mission Control. Harmless while the gate swallows gesture
    /// events; with that off, an orbit can trigger them.
    case threeFingerSwipes

    public var advice: String {
        switch self {
        case .threeFingerDrag:
            "Three-finger drag is on (System Settings > Accessibility > Pointer Control > Trackpad Options). It turns three-finger orbits into window drags; turn it off or map three fingers to Off."
        case .threeFingerSwipes:
            "Three-finger swipes open Mission Control or switch spaces, and swallowing gesture events is off, so an orbit can trigger them. Turn swallowing back on or move those gestures to four fingers (System Settings > Trackpad > More Gestures)."
        }
    }
}

public enum TrackpadPreferences {
    /// Pure: the conflicts in a trackpad preferences dictionary, given how the tool is set up.
    /// Keys from `com.apple.AppleMultitouchTrackpad`; a value of 2 for a swipe gesture means three fingers.
    public static func conflicts(in prefs: [String: Int], threeFingersMapped: Bool, swallowGestures: Bool) -> [TrackpadConflict] {
        guard threeFingersMapped else { return [] }
        var c: [TrackpadConflict] = []
        if prefs["TrackpadThreeFingerDrag"] == 1 { c.append(.threeFingerDrag) }
        let swipes = prefs["TrackpadThreeFingerHorizSwipeGesture"] == 2 || prefs["TrackpadThreeFingerVertSwipeGesture"] == 2
        if swipes && !swallowGestures { c.append(.threeFingerSwipes) }
        return c
    }

    /// The current user's trackpad preferences, built-in and Bluetooth domains merged.
    public static func current() -> [String: Int] {
        let keys = ["TrackpadThreeFingerDrag", "TrackpadThreeFingerHorizSwipeGesture", "TrackpadThreeFingerVertSwipeGesture"]
        var out: [String: Int] = [:]
        for domain in ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
            for key in keys where out[key] == nil {
                if let v = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Int { out[key] = v }
            }
        }
        return out
    }
}
