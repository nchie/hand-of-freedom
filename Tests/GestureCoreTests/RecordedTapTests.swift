import Testing
import GestureCore

/// Two-finger taps copied frame for frame from real recordings, each of which sent a right-click before
/// the lift-off guard and the 0.5 mm drag threshold. Rows: id, phase, x mm, y mm, normalized x, y, size,
/// major axis mm, minor axis mm. Empty rows are frames with no contacts.
@Suite("Recorded taps")
struct RecordedTapTests {
    typealias Row = (Int32, UInt8, Float, Float, Float, Float, Float, Float, Float)

    static func run(_ frames: [[Row]], config: EngineConfig = .default) -> [String] {
        var engine = GestureEngine()
        var events: [String] = []
        for (n, rows) in frames.enumerated() {
            var frame = TouchFrame(sequence: Int32(n))
            for r in rows {
                frame.append(Contact(id: r.0, phase: ContactPhase(rawValue: r.1)!, positionMM: SIMD2(r.2, r.3),
                                     normalized: SIMD2(r.4, r.5), size: r.6, majorAxisMM: r.7, minorAxisMM: r.8))
            }
            let out = engine.process(frame, config: config, targetActive: true)
            if let b = out.release { events.append("-\(b)") }
            if let b = out.press { events.append("+\(b)") }
        }
        return events
    }

    /// Button events and the length of all movement sent, at the default config.
    static func totalMove(_ frames: [[Row]]) -> (events: [String], pixels: Float) {
        var engine = GestureEngine()
        var events: [String] = []
        var pixels: Float = 0
        for (n, rows) in frames.enumerated() {
            var frame = TouchFrame(sequence: Int32(n))
            for r in rows {
                frame.append(Contact(id: r.0, phase: ContactPhase(rawValue: r.1)!, positionMM: SIMD2(r.2, r.3),
                                     normalized: SIMD2(r.4, r.5), size: r.6, majorAxisMM: r.7, minorAxisMM: r.8))
            }
            let out = engine.process(frame, config: .default, targetActive: true)
            if let b = out.release { events.append("-\(b)") }
            if let b = out.press { events.append("+\(b)") }
            let m = SIMD2<Float>(Float(out.movePx.x), Float(out.movePx.y))
            pixels += (m * m).sum().squareRoot()
        }
        return (events, pixels)
    }

    /// The settings these taps were recorded with, which pressed right on every one of them.
    static let before = EngineConfig.default.with {
        $0.thresholds.dragStartMM = 0.4
        $0.thresholds.liftOffSizeRatio = 0
    }

    /// Fingers shrink to a third of their size while lifting, and their centres slide 0.4 mm.
    static let twoFingerTapThatRollsOff: [[Row]] = [
        [(1, 3, 9.64, 26.46, 0.5572, 0.3732, 0.8672, 10.08, 7.64), (11, 1, 12.06, 43.67, 0.5768, 0.6019, 0.7344, 8.45, 7.5)],
        [(1, 4, 9.49, 26.69, 0.5560, 0.3763, 0.9062, 9.67, 7.93), (11, 3, 12.08, 43.94, 0.5770, 0.6055, 1.0586, 8.68, 7.89)],
        [(1, 4, 9.52, 26.71, 0.5562, 0.3766, 0.9062, 9.42, 8.09), (11, 4, 12.02, 43.99, 0.5765, 0.6062, 1.0430, 8.91, 8.09)],
        [(1, 4, 9.48, 26.72, 0.5559, 0.3767, 0.9297, 9.21, 8.26), (11, 4, 12.06, 43.96, 0.5768, 0.6058, 1.0352, 8.95, 8.26)],
        [(1, 4, 9.49, 26.72, 0.5560, 0.3767, 0.9414, 9.22, 8.33), (11, 4, 12.09, 44.03, 0.5771, 0.6067, 1.0547, 9.05, 8.37)],
        [(1, 4, 9.46, 26.73, 0.5557, 0.3768, 0.9336, 9.22, 8.41), (11, 4, 12.09, 44.05, 0.5771, 0.6070, 1.0508, 9.18, 8.46)],
        [(1, 4, 9.46, 26.73, 0.5557, 0.3768, 0.9219, 9.24, 8.45), (11, 4, 12.09, 44.08, 0.5771, 0.6074, 1.0430, 9.24, 8.54)],
        [(1, 4, 9.46, 26.74, 0.5557, 0.3770, 0.8906, 9.1, 8.44), (11, 4, 12.12, 44.12, 0.5773, 0.6079, 1.0156, 9.13, 8.57)],
        [(1, 4, 9.49, 26.8, 0.5560, 0.3778, 0.8633, 9.03, 8.35), (11, 4, 12.16, 44.18, 0.5776, 0.6087, 0.9727, 9.06, 8.55)],
        [(1, 4, 9.55, 26.89, 0.5564, 0.3790, 0.7773, 9.01, 8.26), (11, 4, 12.2, 44.28, 0.5780, 0.6100, 0.8594, 9.02, 8.57)],
        [(1, 4, 9.63, 27.04, 0.5571, 0.3809, 0.5938, 9.26, 7.94), (11, 4, 12.27, 44.43, 0.5785, 0.6120, 0.6484, 9.02, 8.65)],
        [(1, 4, 9.68, 27.27, 0.5575, 0.3840, 0.3320, 9.4, 7.54), (11, 4, 12.31, 44.6, 0.5789, 0.6143, 0.3477, 9.04, 8.75)],
        [(1, 5, 9.69, 27.49, 0.5576, 0.3869, 0.1172, 9.67, 7.4), (11, 5, 12.31, 44.76, 0.5789, 0.6164, 0.1211, 9.16, 8.96)],
        [(1, 7, 9.69, 27.49, 0.5576, 0.3869, 0.0000, 0.0, 0.0), (11, 7, 12.31, 44.76, 0.5789, 0.6164, 0.0000, 0.0, 0.0)],
        [],
    ]

    /// Held still for 120 ms while the contacts settle after landing and creep 0.4 mm.
    static let twoFingerTapThatSettles: [[Row]] = [
        [(4, 1, 24.4, 33.29, 0.6771, 0.4640, 0.5078, 7.43, 6.85), (9, 3, 29.01, 53.09, 0.7145, 0.7271, 0.8828, 8.76, 7.59)],
        [(4, 3, 24.14, 33.29, 0.6750, 0.4640, 0.8750, 8.53, 7.86), (9, 4, 28.76, 53.36, 0.7125, 0.7307, 0.9023, 8.58, 7.67)],
        [(4, 4, 23.99, 33.15, 0.6737, 0.4621, 0.8438, 8.55, 7.83), (9, 4, 28.6, 53.22, 0.7112, 0.7288, 0.9609, 8.81, 7.91)],
        [(4, 4, 23.89, 33.17, 0.6729, 0.4624, 0.8594, 8.53, 7.78), (9, 4, 28.5, 53.23, 0.7104, 0.7289, 0.9805, 8.95, 8.01)],
        [(4, 4, 23.81, 33.18, 0.6723, 0.4625, 0.8789, 8.5, 7.75), (9, 4, 28.46, 53.24, 0.7100, 0.7291, 0.9922, 9.06, 8.06)],
        [(4, 4, 23.76, 33.18, 0.6719, 0.4625, 0.8828, 8.5, 7.72), (9, 4, 28.4, 53.26, 0.7096, 0.7293, 0.9961, 9.12, 8.05)],
        [(4, 4, 23.71, 33.18, 0.6715, 0.4625, 0.8984, 8.48, 7.71), (9, 4, 28.36, 53.27, 0.7092, 0.7295, 1.0039, 9.14, 8.09)],
        [(4, 4, 23.68, 33.16, 0.6712, 0.4623, 0.9258, 8.5, 7.79), (9, 4, 28.34, 53.27, 0.7091, 0.7295, 1.0195, 9.19, 8.15)],
        [(4, 4, 23.66, 33.14, 0.6711, 0.4620, 0.9375, 8.54, 7.84), (9, 4, 28.33, 53.27, 0.7090, 0.7295, 1.0273, 9.19, 8.2)],
        [(4, 4, 23.65, 33.13, 0.6710, 0.4619, 0.9531, 8.56, 7.85), (9, 4, 28.32, 53.27, 0.7089, 0.7295, 1.0352, 9.24, 8.22)],
        [(4, 4, 23.64, 33.11, 0.6709, 0.4616, 0.9609, 8.58, 7.82), (9, 4, 28.32, 53.26, 0.7089, 0.7293, 1.0391, 9.23, 8.23)],
        [(4, 4, 23.63, 33.11, 0.6708, 0.4616, 0.9648, 8.57, 7.76), (9, 4, 28.32, 53.26, 0.7089, 0.7293, 1.0430, 9.22, 8.27)],
        [(4, 4, 23.62, 33.1, 0.6707, 0.4615, 0.9688, 8.56, 7.78), (9, 4, 28.32, 53.25, 0.7089, 0.7292, 1.0430, 9.22, 8.26)],
        [(4, 4, 23.62, 33.09, 0.6707, 0.4613, 0.9844, 8.61, 7.83), (9, 4, 28.33, 53.25, 0.7090, 0.7292, 1.0469, 9.24, 8.27)],
        [(4, 4, 23.61, 33.08, 0.6706, 0.4612, 0.9766, 8.61, 7.9), (9, 4, 28.33, 53.23, 0.7090, 0.7289, 1.0391, 9.3, 8.34)],
        [(4, 4, 23.6, 33.06, 0.6706, 0.4609, 0.9766, 8.69, 7.92), (9, 4, 28.34, 53.21, 0.7091, 0.7287, 1.0195, 9.31, 8.33)],
        [(4, 4, 23.62, 33.06, 0.6707, 0.4609, 0.9609, 8.71, 7.88), (9, 4, 28.36, 53.18, 0.7092, 0.7283, 0.9453, 9.23, 8.23)],
        [(4, 4, 23.66, 33.07, 0.6711, 0.4611, 0.9609, 8.83, 8.02), (9, 4, 28.39, 53.16, 0.7095, 0.7280, 0.7500, 8.81, 7.93)],
        [(4, 4, 23.71, 33.07, 0.6715, 0.4611, 0.9258, 8.96, 8.08), (9, 4, 28.38, 53.12, 0.7094, 0.7275, 0.4258, 8.59, 7.75)],
        [(4, 4, 23.78, 33.06, 0.6720, 0.4609, 0.8594, 9.01, 8.1), (9, 5, 28.18, 53.16, 0.7078, 0.7280, 0.1289, 8.53, 7.91)],
        [(4, 4, 23.87, 33.04, 0.6728, 0.4607, 0.7031, 8.88, 8.04), (9, 7, 28.18, 53.16, 0.7078, 0.7280, 0.0000, 0.0, 0.0)],
        [(4, 4, 23.97, 32.99, 0.6736, 0.4600, 0.3906, 8.78, 8.03)],
        [(4, 5, 24.05, 33.01, 0.6742, 0.4603, 0.1250, 8.69, 7.92)],
        [(4, 7, 24.05, 33.01, 0.6742, 0.4603, 0.0000, 0.0, 0.0)],
    ]

    /// A quick tap during the in-game session that sent a right-click.
    static let quickTwoFingerTapInGame: [[Row]] = [
        [(3, 3, 21.22, 21.23, 0.6512, 0.3037, 0.4922, 9.55, 7.26), (7, 3, 25.77, 44.72, 0.6882, 0.6159, 0.5234, 8.29, 7.53)],
        [(3, 4, 20.92, 21.38, 0.6488, 0.3057, 0.7578, 9.26, 7.65), (7, 4, 25.53, 44.99, 0.6862, 0.6195, 0.7266, 8.55, 7.86)],
        [(3, 4, 20.73, 21.47, 0.6473, 0.3069, 0.7734, 9.06, 7.8), (7, 4, 25.38, 45.15, 0.6850, 0.6216, 0.7031, 8.71, 8.04)],
        [(3, 4, 20.66, 21.52, 0.6467, 0.3076, 0.7227, 8.94, 7.91), (7, 4, 25.3, 45.32, 0.6844, 0.6238, 0.5391, 8.59, 8.0)],
        [(3, 4, 20.66, 21.52, 0.6467, 0.3076, 0.7266, 8.74, 8.03), (7, 4, 25.09, 45.68, 0.6827, 0.6286, 0.2344, 8.57, 7.92)],
        [(3, 4, 20.68, 21.49, 0.6468, 0.3072, 0.7070, 8.64, 8.01), (7, 7, 25.09, 45.68, 0.6827, 0.6286, 0.0000, 0.0, 0.0)],
        [(3, 4, 20.73, 21.47, 0.6473, 0.3069, 0.6328, 8.62, 8.0)],
        [(3, 4, 20.92, 21.47, 0.6488, 0.3069, 0.6094, 8.51, 8.06)],
        [(3, 4, 21.21, 21.44, 0.6512, 0.3065, 0.6211, 8.6, 8.05)],
        [(3, 4, 21.59, 21.36, 0.6542, 0.3055, 0.6445, 8.44, 7.95)],
    ]

    @Test func twoFingerTapThatRollsOffSendsNothing() {
        #expect(Self.run(Self.twoFingerTapThatRollsOff, config: Self.before) == ["+right", "-right"])
        #expect(Self.run(Self.twoFingerTapThatRollsOff).isEmpty)
    }

    @Test func twoFingerTapThatSettlesSendsNothing() {
        #expect(Self.run(Self.twoFingerTapThatSettles, config: Self.before) == ["+right", "-right"])
        #expect(Self.run(Self.twoFingerTapThatSettles).isEmpty)
    }

    @Test func quickTwoFingerTapInGameSendsNothing() {
        #expect(Self.run(Self.quickTwoFingerTapInGame, config: Self.before) == ["+right", "-right"])
        #expect(Self.run(Self.quickTwoFingerTapInGame).isEmpty)
    }
}
