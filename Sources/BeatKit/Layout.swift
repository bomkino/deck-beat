import Foundation

/// Where every cell sits on a canvas, in world units: the canvas is 1 tall and
/// `aspect` wide, centred on the origin, +y up.
public struct GridLayout: Sendable {
    public struct Cell: Sendable {
        public var index: Int
        public var row: Int
        public var column: Int
        /// Centre on the flat grid, before any wall turn.
        public var centre: SIMD2<Float>
        public var size: SIMD2<Float>
    }

    public let aspect: Float
    public let columns: Int
    public let rows: Int
    public let cells: [Cell]
    /// The shape used, after Auto is resolved.
    public let shape: CellShape
    public let cellAspect: Float
    /// The slides' usual shape (w / h).
    public let slideAspect: Float
    /// The box the grid sits in: centre and size.
    public let safeCentre: SIMD2<Float>
    public let safeSize: SIMD2<Float>
    public let gridSize: SIMD2<Float>
    public let gap: Float
    /// World units per pixel at 1080 on the short side.
    public let px: Float
    /// Wall turn in radians (pitch, yaw), and the scale that fits the turned
    /// wall back inside the safe box.
    public let wallPitch: Float
    public let wallYaw: Float
    public let wallScale: Float

    /// Distance from the eye to the canvas plane for the stage's default 35° lens.
    public static let eyeDistance: Float = 0.5 / Float(tan(35.0 * Double.pi / 360))

    public init(settings g: GridSettings, aspect: Float, slideAspect: Float) {
        self.aspect = aspect
        let cols = max(1, min(g.columns, 40)), rows = max(1, min(g.rows, 40))
        columns = cols
        self.rows = rows
        self.slideAspect = max(0.2, min(slideAspect, 5))
        px = min(aspect, 1) / 1080
        let inset = g.margins.insets(aspect: aspect)
        let W = aspect * (1 - 2 * inset.side), H = 1 - inset.top - inset.bottom
        safeSize = SIMD2(W, H)
        safeCentre = SIMD2(0, (inset.bottom - inset.top) / 2)
        // Never let the gaps eat more than a third of the box.
        let gap = min(g.gap * px, W / Float(cols) * 0.33, H / Float(rows) * 0.33)
        self.gap = gap
        let fillW = (W - Float(cols - 1) * gap) / Float(cols)
        let fillH = (H - Float(rows - 1) * gap) / Float(rows)

        func fitted(_ a: Float) -> SIMD2<Float> {
            let w = min(fillW, fillH * a)
            return SIMD2(w, w / a)
        }
        func coverage(_ size: SIMD2<Float>) -> Float {
            let gw = Float(cols) * size.x + Float(cols - 1) * gap, gh = Float(rows) * size.y + Float(rows - 1) * gap
            return min(gw / W, gh / H)
        }
        var shape = g.shape
        // Slide-shaped cells when they still cover three quarters of the box both ways.
        if shape == .auto { shape = coverage(fitted(self.slideAspect)) >= 0.75 ? .slide : .fill }
        self.shape = shape
        let size: SIMD2<Float>
        switch shape {
        case .slide, .auto: size = fitted(self.slideAspect)
        case .square: size = fitted(1)
        case .fill: size = SIMD2(fillW, fillH)
        }
        cellAspect = size.x / max(size.y, 1e-5)
        let gw = Float(cols) * size.x + Float(cols - 1) * gap, gh = Float(rows) * size.y + Float(rows - 1) * gap
        gridSize = SIMD2(gw, gh)
        var cells: [Cell] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let x = -gw / 2 + size.x / 2 + Float(c) * (size.x + gap)
                let y = gh / 2 - size.y / 2 - Float(r) * (size.y + gap)
                cells.append(Cell(index: r * cols + c, row: r, column: c, centre: SIMD2(x, y), size: size))
            }
        }
        self.cells = cells
        wallPitch = g.wall.pitch * .pi / 180
        wallYaw = g.wall.yaw * .pi / 180
        if g.wall.isFlat {
            wallScale = 1
        } else {
            // Fit the turned wall's corners, as the camera sees them, inside the box.
            var scale: Float = 1
            for _ in 0..<3 {
                var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
                for corner in [SIMD2<Float>(-gw / 2, -gh / 2), SIMD2(gw / 2, -gh / 2), SIMD2(-gw / 2, gh / 2), SIMD2(gw / 2, gh / 2)] {
                    let p = Self.turn(SIMD3(corner.x * scale, corner.y * scale, 0), pitch: wallPitch, yaw: wallYaw)
                    let k = Self.eyeDistance / (Self.eyeDistance - p.z)
                    let q = SIMD2(p.x * k, p.y * k)
                    lo = SIMD2(min(lo.x, q.x), min(lo.y, q.y))
                    hi = SIMD2(max(hi.x, q.x), max(hi.y, q.y))
                }
                let span = hi - lo
                scale *= min(W / max(span.x, 1e-5), H / max(span.y, 1e-5), 1.25)
            }
            wallScale = scale
        }
    }

    public var count: Int { cells.count }

    /// Rotates a point about the grid's centre the way the stage turns a card:
    /// pitch about x first (positive tips the top away), then yaw about y
    /// (positive turns the right side away).
    public static func turn(_ p: SIMD3<Float>, pitch: Float, yaw: Float) -> SIMD3<Float> {
        let cy = cosf(yaw), sy = sinf(yaw), cp = cosf(pitch), sp = sinf(pitch)
        let y1 = p.y * cp + p.z * sp
        let z1 = -p.y * sp + p.z * cp
        let x2 = p.x * cy + z1 * sy
        let z2 = -p.x * sy + z1 * cy
        return SIMD3(x2, y1, z2)
    }

    /// A point given relative to the flat grid (x, y on it, z out of it), on
    /// the canvas: through the wall turn, scaled to fit, centred in the box.
    public func place(_ local: SIMD3<Float>) -> SIMD3<Float> {
        if wallPitch == 0, wallYaw == 0 { return SIMD3(local.x + safeCentre.x, local.y + safeCentre.y, local.z) }
        let p = Self.turn(local * wallScale, pitch: wallPitch, yaw: wallYaw)
        return SIMD3(p.x + safeCentre.x, p.y + safeCentre.y, p.z)
    }

    /// The card rotation (yaw, pitch, roll) a card lying on the wall takes.
    public var wallRotation: SIMD3<Float> { SIMD3(-wallPitch, wallYaw, 0) }

    /// Size of a slide of `aspect` held up to be read: 82 % of the canvas
    /// wide, never wider than the box nor taller than 60 % of it.
    public func heroSize(aspect a: Float, widthFraction: Float = 0.82) -> SIMD2<Float> {
        var w = min(self.aspect * widthFraction, safeSize.x)
        var h = w / a
        let maxH = safeSize.y * 0.6
        if h > maxH { h = maxH; w = h * a }
        return SIMD2(w, h)
    }

    /// The cell nearest the middle of the grid.
    public var centreCell: Int {
        cells.min { simdLength($0.centre) < simdLength($1.centre) }?.index ?? 0
    }

    /// How far each cell is from `origin`, 0 (there) … 1 (the far corner).
    public func distances(from origin: SIMD2<Float>) -> [Float] {
        let d = cells.map { simdLength($0.centre - origin) }
        let far = max(d.max() ?? 1, 1e-5)
        return d.map { $0 / far }
    }

    /// "Fit my deck": the slide-shaped grid with the widest cells that holds
    /// `count` slides with fewer than a row spare and still covers three
    /// quarters of the box both ways; otherwise a filled grid three to six
    /// columns wide.
    public static func fit(count: Int, aspect: Float, slideAspect: Float, base: GridSettings) -> (columns: Int, rows: Int, shape: CellShape) {
        let n = max(1, count)
        var best: (columns: Int, rows: Int)?
        var widest: Float = 0
        for c in 2...8 {
            let r = Int((Double(n) / Double(c)).rounded(.up))
            guard r <= 20, c * r - n <= c - 1 else { continue }
            var g = base
            g.columns = c
            g.rows = r
            g.shape = .slide
            let layout = GridLayout(settings: g, aspect: aspect, slideAspect: slideAspect)
            let cover = min(layout.gridSize.x / layout.safeSize.x, layout.gridSize.y / layout.safeSize.y)
            let w = layout.cells[0].size.x
            if cover >= 0.75, w > widest + 1e-5 { widest = w; best = (c, r) }
        }
        if let best { return (best.columns, best.rows, .slide) }
        let c = n <= 18 ? 3 : (n <= 36 ? 4 : (n <= 60 ? 5 : 6))
        return (c, min(20, Int((Double(n) / Double(c)).rounded(.up))), .fill)
    }
}

@inline(__always) func simdLength(_ v: SIMD2<Float>) -> Float { (v.x * v.x + v.y * v.y).squareRoot() }
