import Testing
import PlatformBackends

@Suite("Marker decoder")
struct MarkerDecoderTests {
    /// A BGRA image filled with a dull, slightly noisy background.
    struct Canvas {
        let width: Int, height: Int
        var bytes: [UInt8]
        var bytesPerRow: Int { width * 4 + 16 }       // padded rows, as capture buffers often are

        init(width: Int = 320, height: Int = 120) {
            self.width = width
            self.height = height
            bytes = []
            bytes = [UInt8](repeating: 0, count: (width * 4 + 16) * height)
            for y in 0..<height { for x in 0..<width { set(x, y, (60 &+ UInt8((x * 7 + y * 3) % 40), 90, 120)) } }
        }

        mutating func set(_ x: Int, _ y: Int, _ rgb: (UInt8, UInt8, UInt8)) {
            let i = y * bytesPerRow + x * 4
            bytes[i] = rgb.2; bytes[i + 1] = rgb.1; bytes[i + 2] = rgb.0; bytes[i + 3] = 255
        }

        mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ rgb: (UInt8, UInt8, UInt8)) {
            for yy in y..<y + h { for xx in x..<x + w { set(xx, yy, rgb) } }
        }

        /// The addon's three squares. `soften` blends the outer pixel ring of each square halfway to grey.
        mutating func marker(x: Int, y: Int, cell: Int, state: (UInt8, UInt8, UInt8), soften: Bool = false) {
            let colors = [(UInt8(255), UInt8(0), UInt8(255)), state, (255, 255, 0)]
            for (k, c) in colors.enumerated() {
                fill(x + k * cell, y, cell, cell, c)
                guard soften else { continue }
                func half(_ v: UInt8) -> UInt8 { UInt8((Int(v) + 128) / 2) }
                for i in 0..<cell {
                    for (xx, yy) in [(x + k * cell + i, y), (x + k * cell + i, y + cell - 1)] { set(xx, yy, (half(c.0), half(c.1), half(c.2))) }
                }
            }
        }

        func decode(_ d: inout MarkerDecoder) -> MarkerDecoder.Hit? {
            bytes.withUnsafeBytes { d.decode($0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow) }
        }
    }

    static let green: (UInt8, UInt8, UInt8) = (0, 255, 0)
    static let blue: (UInt8, UInt8, UInt8) = (0, 0, 255)
    static let red: (UInt8, UInt8, UInt8) = (255, 0, 0)

    @Test(arguments: [4, 8])
    func everyStateDecodes(cell: Int) {
        for (color, state) in [(Self.green, MarkerState.world), (Self.blue, .scrollable), (Self.red, .window)] {
            var c = Canvas()
            c.marker(x: 148, y: 0, cell: cell, state: color)
            var d = MarkerDecoder()
            #expect(c.decode(&d) == MarkerDecoder.Hit(x: 148, y: 0, cell: cell, state: state))
        }
    }

    @Test func colourShiftsAndSoftEdgesStillDecode() {
        var c = Canvas()
        c.marker(x: 101, y: 57, cell: 8, state: (30, 220, 40), soften: true)
        var d = MarkerDecoder()
        #expect(c.decode(&d)?.state == .world)
    }

    @Test func aStateChangeIsReadAtTheRememberedPlace() {
        var c = Canvas()
        c.marker(x: 148, y: 0, cell: 4, state: Self.green)
        var d = MarkerDecoder()
        #expect(c.decode(&d)?.state == .world)
        c.marker(x: 148, y: 0, cell: 4, state: Self.blue)
        #expect(c.decode(&d)?.state == .scrollable)
        #expect(d.last?.x == 148)
    }

    @Test func aMovedMarkerIsFoundAgain() {
        var c = Canvas()
        c.marker(x: 148, y: 0, cell: 4, state: Self.green)
        var d = MarkerDecoder()
        _ = c.decode(&d)
        c = Canvas()
        c.marker(x: 120, y: 30, cell: 12, state: Self.red)          // after a change of window or scale
        #expect(c.decode(&d) == MarkerDecoder.Hit(x: 120, y: 30, cell: 12, state: .window))
    }

    @Test func noMarkerIsNil() {
        var c = Canvas()
        var d = MarkerDecoder()
        #expect(c.decode(&d) == nil)
        // Scenery with the right colours in the wrong shape.
        c.fill(10, 10, 40, 20, (255, 0, 255))
        c.fill(50, 10, 40, 20, (0, 255, 0))
        c.fill(90, 10, 10, 20, (255, 255, 0))
        c.fill(200, 40, 4, 4, (255, 0, 255))
        c.fill(204, 40, 4, 4, (128, 128, 128))
        c.fill(208, 40, 4, 4, (255, 255, 0))
        #expect(c.decode(&d) == nil)
    }
}
