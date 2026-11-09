/// What the Hand of Freedom addon reports about the mouse.
public enum MarkerState: UInt8, Sendable, Equatable, BitwiseCopyable {
    /// The 3D world: a swipe turns.
    case world
    /// A window that takes the mouse wheel: a swipe should scroll it.
    case scrollable
    /// Any other window.
    case window
}

/// Finds the addon's marker in a 32-bit BGRA image: three equal squares side by side, magenta, a state
/// colour, yellow (Addon/HandOfFreedom/HandOfFreedom.lua). Colours are matched loosely, so colour
/// management and blending at the squares' edges do not matter; the order and equal sizes make scenery an
/// unlikely match. Remembers where it last found the marker and looks there first.
public struct MarkerDecoder: Sendable {
    public struct Hit: Sendable, Equatable {
        /// Top-left pixel of the first square.
        public var x: Int
        public var y: Int
        /// Square size in pixels.
        public var cell: Int
        public var state: MarkerState

        public init(x: Int, y: Int, cell: Int, state: MarkerState) {
            self.x = x
            self.y = y
            self.cell = cell
            self.state = state
        }
    }

    enum Swatch { case magenta, yellow, green, blue, red, other }

    public private(set) var last: Hit?

    public init() {}

    public mutating func decode(_ pixels: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) -> Hit? {
        let image = Image(base: pixels, width: width, height: height, bytesPerRow: bytesPerRow)
        if let l = last, let state = image.check(x: l.x, y: l.y, cell: l.cell) {
            last = Hit(x: l.x, y: l.y, cell: l.cell, state: state)
            return last
        }
        last = image.search()
        return last
    }

    struct Image {
        let base: UnsafeRawPointer
        let width: Int
        let height: Int
        let bytesPerRow: Int

        func swatch(_ x: Int, _ y: Int) -> Swatch {
            guard x >= 0, y >= 0, x < width, y < height else { return .other }
            let p = base + y * bytesPerRow + x * 4
            let b = p.load(fromByteOffset: 0, as: UInt8.self)
            let g = p.load(fromByteOffset: 1, as: UInt8.self)
            let r = p.load(fromByteOffset: 2, as: UInt8.self)
            let hi: UInt8 = 170, lo: UInt8 = 85
            switch (r >= hi ? 1 : r <= lo ? 0 : -1, g >= hi ? 1 : g <= lo ? 0 : -1, b >= hi ? 1 : b <= lo ? 0 : -1) {
            case (1, 0, 1): return .magenta
            case (1, 1, 0): return .yellow
            case (0, 1, 0): return .green
            case (0, 0, 1): return .blue
            case (1, 0, 0): return .red
            default: return .other
            }
        }

        /// The state if a marker with its first square's top-left at (x, y) is there. Samples the middle
        /// half of every square.
        func check(x: Int, y: Int, cell: Int) -> MarkerState? {
            guard cell >= 2 else { return nil }
            var state: MarkerState?
            let inset = cell / 4, far = cell - 1 - cell / 4
            for k in 0..<3 {
                var seen: MarkerState?
                for (dx, dy) in [(inset, inset), (far, inset), (inset, far), (far, far), (cell / 2, cell / 2)] {
                    let s = swatch(x + k * cell + dx, y + dy)
                    switch k {
                    case 0: guard s == .magenta else { return nil }
                    case 2: guard s == .yellow else { return nil }
                    default:
                        let v: MarkerState
                        switch s {
                        case .green: v = .world
                        case .blue: v = .scrollable
                        case .red: v = .window
                        default: return nil
                        }
                        guard seen == nil || seen == v else { return nil }
                        seen = v
                    }
                }
                if k == 1 { state = seen }
            }
            return state
        }

        /// Scans for a magenta run and tries it as the first square.
        func search() -> Hit? {
            for y in 0..<height {
                var x = 0
                while x < width {
                    guard swatch(x, y) == .magenta else { x += 1; continue }
                    var end = x
                    while end < width, swatch(end, y) == .magenta { end += 1 }
                    let run = end - x
                    if run >= 2 {
                        var top = y
                        while top > 0, swatch(x + run / 2, top - 1) == .magenta { top -= 1 }
                        // Blended edges can shorten or lengthen the run by a pixel on each side.
                        for cell in [run, run + 1, run - 1, run + 2] where cell >= 2 {
                            for left in [x, x - 1] {
                                for t in [top, top - 1] {
                                    if let state = check(x: left, y: t, cell: cell) {
                                        return Hit(x: left, y: t, cell: cell, state: state)
                                    }
                                }
                            }
                        }
                    }
                    x = end
                }
            }
            return nil
        }
    }
}
