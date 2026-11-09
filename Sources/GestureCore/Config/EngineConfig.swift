/// Which button a drag with a given number of fingers holds.
public struct ButtonMapping: Sendable, Equatable, Codable, BitwiseCopyable {
    public var twoFingers: ButtonChoice = .right
    public var threeFingers: ButtonChoice = .left
    /// Four fingers belong to macOS by default.
    public var fourFingers: ButtonChoice = .off

    public init() {}

    public func button(for count: Int32) -> MouseButton? {
        switch count {
        case 2: twoFingers.button
        case 3: threeFingers.button
        case 4: fourFingers.button
        default: nil
        }
    }
}

public struct PointerConfig: Sendable, Equatable, Codable, BitwiseCopyable {
    /// Sensitivity: screen pixels per millimetre of finger travel.
    public var pxPerMM: Float = 10
    /// Per-frame magnitude clamp, a safety net against bad data.
    public var maxStepPx: Float = 60
    /// Extra inversion on top of the pad-y-up to screen-y-down flip.
    public var invertY: Bool = false

    public init() {}
}

public struct ZoomConfig: Sendable, Equatable, Codable, BitwiseCopyable {
    public var enabled: Bool = true
    /// Change in finger spread per scroll tick.
    public var mmPerTick: Float = 3.0
    /// Distance between spread and its baseline needed before zoom engages.
    public var deadBandMM: Float = 1.5
    /// Per-frame fraction the idle baseline moves toward the current spread, so slow drift is absorbed.
    public var baselineLeak: Float = 0.1
    /// Per-frame spread change below which the spread counts as still.
    public var jitterFloorMM: Float = 0.15
    /// Consecutive still frames that end an engaged zoom.
    public var disengageFrames: Int32 = 12
    /// false: fingers apart = zoom in = positive ticks.
    public var invert: Bool = false

    public init() {}
}

public struct Thresholds: Sendable, Equatable, Codable, BitwiseCopyable {
    /// Finger travel before the button goes down. A distance, never a time, so taps stay taps.
    /// 0.4 mm let two still fingers settling after landing cross it, which sent a right-click on a tap.
    public var dragStartMM: Float = 0.5
    /// A drag member may be missing this many frames (a dropout) without ending the drag.
    public var ghostFrames: Int32 = 2
    /// A touching contact below this fraction of its peak size is rolling off the pad. Its centre slides
    /// toward the fingertip as it shrinks, so frames with such a contact never count toward `dragStartMM`.
    /// That keeps a two-finger tap from turning into a right-click.
    public var liftOffSizeRatio: Float = 0.7
    /// A contact reported as approaching (starting, hovering or making) for at most this many frames holds
    /// back a press whose button it would change when it lands, such as a third finger turning a right drag
    /// into a left one. A finger that keeps hovering longer stops holding anything back.
    public var landingLookaheadFrames: Int32 = 3

    public init() {}

    private enum CodingKeys: String, CodingKey { case dragStartMM, ghostFrames, liftOffSizeRatio, landingLookaheadFrames }

    /// Missing keys keep their defaults, so recordings and config files from before a field existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Thresholds()
        dragStartMM = try c.decodeIfPresent(Float.self, forKey: .dragStartMM) ?? d.dragStartMM
        ghostFrames = try c.decodeIfPresent(Int32.self, forKey: .ghostFrames) ?? d.ghostFrames
        liftOffSizeRatio = try c.decodeIfPresent(Float.self, forKey: .liftOffSizeRatio) ?? d.liftOffSizeRatio
        landingLookaheadFrames = try c.decodeIfPresent(Int32.self, forKey: .landingLookaheadFrames) ?? d.landingLookaheadFrames
    }
}

/// Palm and thumb heuristics, calibrated from recordings.
public struct RejectionConfig: Sendable, Equatable, Codable, BitwiseCopyable {
    public var palmMinSize: Float = 2.5
    public var palmMinMajorAxisMM: Float = 14
    /// Frames after landing during which a drag member may still turn out to be a palm, ending the drag.
    /// Every other contact is checked for palm shape for as long as it touches.
    public var palmGrowthFrames: Int32 = 10
    /// Normalized y below which a landing contact is in the thumb zone.
    public var thumbZoneBottom: Float = 0.15
    /// Normalized distance from the left or right edge that is also thumb zone.
    public var thumbZoneSide: Float = 0.06
    /// Landings further apart than this many frames are separate landing groups.
    public var thumbLateLandingFrames: Int32 = 15
    /// A thumb candidate that travels this far with the fingers becomes a finger.
    public var thumbPromoteTravelMM: Float = 1.0

    public init() {}

    func isInThumbZone(_ normalized: SIMD2<Float>) -> Bool {
        normalized.y < thumbZoneBottom || normalized.x < thumbZoneSide || normalized.x > 1 - thumbZoneSide
    }
}

public struct EngineConfig: Sendable, Equatable, Codable, BitwiseCopyable {
    public var mapping = ButtonMapping()
    public var pointer = PointerConfig()
    public var zoom = ZoomConfig()
    public var thresholds = Thresholds()
    public var rejection = RejectionConfig()

    public init() {}

    public static let `default` = EngineConfig()
}
