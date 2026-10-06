import Foundation

/// Where every cell sits on a canvas, in world units: the canvas is 1 tall and
/// `aspect` wide, centred on the origin, +y up.
/// Room kept clear at the top and bottom of the frame, as shares of its height.
public struct Clearance: Hashable, Sendable {
    public var top: Float
    public var bottom: Float

    public init(top: Float = 0, bottom: Float = 0) {
        self.top = top
        self.bottom = bottom
    }

    public static let none = Clearance()
}

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

    /// `clear` keeps the grid off the top and bottom of the frame by at least
    /// these shares of its height, such as for a caption.
    public init(settings g: GridSettings, aspect: Float, slideAspect: Float, clear: Clearance = .none) {
        self.aspect = aspect
        let cols = max(1, min(g.columns, 40)), rows = max(1, min(g.rows, 40))
        columns = cols
        self.rows = rows
        self.slideAspect = max(0.2, min(slideAspect, 5))
        px = min(aspect, 1) / 1080
        var inset = g.margins.insets(aspect: aspect)
        inset.top = max(inset.top, min(clear.top, 0.4))
        inset.bottom = max(inset.bottom, min(clear.bottom, 0.4))
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
        // Slide-shaped cells when they still cover three quarters of the box
        // both ways, or when filled cells would crop away most of each slide
        // (wide slides in a tall frame).
        if shape == .auto {
            shape = coverage(fitted(self.slideAspect)) >= 0.75 || Self.crop(cell: fillW / max(fillH, 1e-5), slide: self.slideAspect) > 0.4
                ? .slide : .fill
        }
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

    /// The share of a slide a filled cell of `cell` aspect crops away.
    public static func crop(cell: Float, slide: Float) -> Float {
        1 - min(cell / max(slide, 1e-5), slide / max(cell, 1e-5))
    }

    /// The share of each slide its cell crops away (0 for slide-shaped cells).
    public var crop: Float { shape == .fill ? Self.crop(cell: cellAspect, slide: slideAspect) : 0 }

    /// "Fit my deck": a grid that holds `count` slides with less than a row
    /// spare. The slide-shaped grid with the widest cells that still covers
    /// three quarters of the box both ways; otherwise the filled grid that
    /// crops the least, if it keeps at least 65 % of each slide; otherwise
    /// the slide-shaped grid that covers the most of the box, so wide slides
    /// in a tall frame are never cut in half.
    public static func fit(count: Int, aspect: Float, slideAspect: Float, base: GridSettings) -> (columns: Int, rows: Int, shape: CellShape) {
        let n = max(1, count)
        var covering: (columns: Int, rows: Int, width: Float)?
        var filled: (columns: Int, rows: Int, crop: Float, width: Float)?
        var open: (columns: Int, rows: Int, area: Float)?
        for c in 1...8 where c <= n {
            let r = Int((Double(n) / Double(c)).rounded(.up))
            guard r <= 20 else { continue }
            var g = base
            g.columns = c
            g.rows = r
            g.shape = .slide
            let slide = GridLayout(settings: g, aspect: aspect, slideAspect: slideAspect)
            let cover = SIMD2(slide.gridSize.x / slide.safeSize.x, slide.gridSize.y / slide.safeSize.y)
            let w = slide.cells[0].size.x
            if min(cover.x, cover.y) >= 0.75, w > (covering?.width ?? 0) + 1e-5 { covering = (c, r, w) }
            if cover.x * cover.y > (open?.area ?? 0) + 1e-5 { open = (c, r, cover.x * cover.y) }
            g.shape = .fill
            let fill = GridLayout(settings: g, aspect: aspect, slideAspect: slideAspect)
            let crop = fill.crop
            if crop <= 0.35, filled == nil || crop < filled!.crop - 0.02 || (crop < filled!.crop + 0.02 && fill.cells[0].size.x > filled!.width) {
                filled = (c, r, crop, fill.cells[0].size.x)
            }
        }
        if let covering { return (covering.columns, covering.rows, .slide) }
        if let filled { return (filled.columns, filled.rows, .fill) }
        if let open { return (open.columns, open.rows, .slide) }
        return (1, min(n, 20), .slide)
    }
}

@inline(__always) func simdLength(_ v: SIMD2<Float>) -> Float { (v.x * v.x + v.y * v.y).squareRoot() }

public extension GridSettings {
    /// This grid refitted to a deck of `count` slides of `slideAspect` on a
    /// canvas of `aspect`. The shape stays Auto wherever Auto already lands on
    /// the fitted shape, so the grid keeps working across canvas formats.
    func fitted(count: Int, aspect: Float, slideAspect: Float) -> GridSettings {
        let f = GridLayout.fit(count: count, aspect: aspect, slideAspect: slideAspect, base: self)
        var g = self
        g.columns = f.columns
        g.rows = f.rows
        g.shape = .auto
        if GridLayout(settings: g, aspect: aspect, slideAspect: slideAspect).shape != f.shape { g.shape = f.shape }
        return g
    }
}
