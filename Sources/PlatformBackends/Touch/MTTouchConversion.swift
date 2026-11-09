import CMultitouchSupport
import GestureCore

public enum MTTouchConversion {
    /// nil when the data is implausible, which is what a changed struct layout would look like.
    public static func contact(from t: MTTouch) -> Contact? {
        guard t.state >= 0, t.state <= 7, let phase = ContactPhase(rawValue: UInt8(t.state)) else { return nil }
        let values = [t.mm.pos.x, t.mm.pos.y, t.mm.vel.x, t.mm.vel.y, t.normalized.pos.x, t.normalized.pos.y,
                      t.size, t.majorAxis, t.minorAxis, t.angle]
        guard values.allSatisfy(\.isFinite) else { return nil }
        guard (-0.1...1.1).contains(t.normalized.pos.x), (-0.1...1.1).contains(t.normalized.pos.y),
              abs(t.mm.pos.x) < 300, abs(t.mm.pos.y) < 300, t.size >= 0, t.size < 100 else { return nil }
        return Contact(id: Int32(t.identifier), phase: phase,
                       positionMM: SIMD2(t.mm.pos.x, t.mm.pos.y), velocityMM: SIMD2(t.mm.vel.x, t.mm.vel.y),
                       normalized: SIMD2(t.normalized.pos.x, t.normalized.pos.y),
                       size: t.size, majorAxisMM: t.majorAxis, minorAxisMM: t.minorAxis, angle: t.angle)
    }
}
