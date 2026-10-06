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
    /// Grid, or a collage of slides at their own shapes. A collage's rows and
    /// columns are where its cells fall, so modes that read them still work.
    public let arrangement: Arrangement
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
    /// The box a slide held up to be read stays inside: the safe box, and with
    /// Safe margins also clear of the platform's buttons and caption, so a
    /// featured or zoomed slide is never under them though the grid may be.
    public let featureCentre: SIMD2<Float>
    public let featureSize: SIMD2<Float>
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
    /// these shares of its height, such as for a caption. `aspects` are the
    /// slides' own shapes, in deck order: a collage gives each its own cell.
    public init(settings g: GridSettings, aspect: Float, slideAspect: Float, aspects: [Float] = [], clear: Clearance = .none) {
        self.aspect = aspect
        self.slideAspect = max(0.2, min(slideAspect, 5))
        px = min(aspect, 1) / 1080
        var inset = g.margins.insets(aspect: aspect)
        inset.top = max(inset.top, min(clear.top, 0.4))
        inset.bottom = max(inset.bottom, min(clear.bottom, 0.4))
        let ui = Margins.platform(aspect: aspect)
        // Clear keeps the whole grid off the platform's interface, the button
        // column on the right included; Safe keeps only a slide being read off it.
        var right = inset.side
        if g.margins == .clear {
            right = max(inset.side, ui.right)
            inset.top = max(inset.top, ui.top)
            inset.bottom = max(inset.bottom, ui.bottom)
        }
        let W = aspect * (1 - inset.side - right), H = 1 - inset.top - inset.bottom
        safeSize = SIMD2(W, H)
        safeCentre = SIMD2(aspect * (inset.side - right) / 2, (inset.bottom - inset.top) / 2)
        if g.margins.keepsClear {
            let r = max(right, ui.right), top = max(inset.top, ui.top), bottom = max(inset.bottom, ui.bottom)
            featureSize = SIMD2(aspect * (1 - inset.side - r), 1 - top - bottom)
            featureCentre = SIMD2(aspect * (inset.side - r) / 2, (bottom - top) / 2)
        } else {
            featureSize = safeSize
            featureCentre = safeCentre
        }

        var cells: [Cell] = []
        let gw: Float, gh: Float
        if g.arrangement == .collage, !aspects.isEmpty {
            // Every slide whole at its own shape, in justified rows or columns.
            let own = aspects.prefix(GridSettings.collageLimit).map { max(0.2, min($0, 5)) }
            let gap = min(g.gap * px, min(W, H) * 0.05)
            self.gap = gap
            let c = Self.collage(own, box: SIMD2(W, H), gap: gap)
            arrangement = .collage
            columns = c.columns
            rows = c.rows
            shape = .slide
            cellAspect = self.slideAspect
            for (i, f) in c.frames.enumerated() {
                cells.append(Cell(index: i, row: f.row, column: f.column, centre: f.centre, size: f.size))
            }
            gw = c.size.x
            gh = c.size.y
        } else {
            arrangement = .grid
            let cols = max(1, min(g.columns, 40)), rows = max(1, min(g.rows, 40))
            columns = cols
            self.rows = rows
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
            gw = Float(cols) * size.x + Float(cols - 1) * gap
            gh = Float(rows) * size.y + Float(rows - 1) * gap
            for r in 0..<rows {
                for c in 0..<cols {
                    let x = -gw / 2 + size.x / 2 + Float(c) * (size.x + gap)
                    let y = gh / 2 - size.y / 2 - Float(r) * (size.y + gap)
                    cells.append(Cell(index: r * cols + c, row: r, column: c, centre: SIMD2(x, y), size: size))
                }
            }
        }
        gridSize = SIMD2(gw, gh)
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
    /// wide, never wider than the feature box (less room for the kick's punch
    /// and the cover's push) nor taller than 60 % of it.
    public func heroSize(aspect a: Float, widthFraction: Float = 0.82) -> SIMD2<Float> {
        var w = min(self.aspect * widthFraction, featureSize.x * 0.94)
        var h = w / a
        let maxH = featureSize.y * 0.6
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

    /// "Fit my deck": a grid of up to 12 columns that holds `count` slides with less than a row
    /// spare. The slide-shaped grid with the widest cells that still covers
    /// three quarters of the box both ways; otherwise the filled grid that
    /// crops the least, if it keeps at least 65 % of each slide; otherwise
    /// the slide-shaped grid that covers the most of the box, so wide slides
    /// in a tall frame are never cut in half.
    public static func fit(count: Int, aspect: Float, slideAspect: Float, base: GridSettings,
                           clear: Clearance = .none) -> (columns: Int, rows: Int, shape: CellShape) {
        let n = max(1, count)
        var covering: (columns: Int, rows: Int, width: Float)?
        var filled: (columns: Int, rows: Int, crop: Float, width: Float)?
        var open: (columns: Int, rows: Int, area: Float)?
        for c in 1...12 where c <= n {
            let r = Int((Double(n) / Double(c)).rounded(.up))
            guard r <= 20 else { continue }
            var g = base
            g.columns = c
            g.rows = r
            g.shape = .slide
            let slide = GridLayout(settings: g, aspect: aspect, slideAspect: slideAspect, clear: clear)
            let cover = SIMD2(slide.gridSize.x / slide.safeSize.x, slide.gridSize.y / slide.safeSize.y)
            let w = slide.cells[0].size.x
            if min(cover.x, cover.y) >= 0.75, w > (covering?.width ?? 0) + 1e-5 { covering = (c, r, w) }
            if cover.x * cover.y > (open?.area ?? 0) + 1e-5 { open = (c, r, cover.x * cover.y) }
            g.shape = .fill
            let fill = GridLayout(settings: g, aspect: aspect, slideAspect: slideAspect, clear: clear)
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

extension GridLayout {
    struct CollageFrame {
        var centre: SIMD2<Float>
        var size: SIMD2<Float>
        var row: Int
        var column: Int
    }

    /// Slides of `aspects` (in deck order) laid out whole in `box`: split into
    /// rows of balanced width by an optimal linear partition, each row scaled
    /// to one width, the block scaled to fit and centred. Every row count is
    /// tried, and the same in columns; the layout covering the most of the
    /// box, with evenly sized rows, wins.
    static func collage(_ aspects: [Float], box: SIMD2<Float>, gap: Float)
        -> (frames: [CollageFrame], size: SIMD2<Float>, rows: Int, columns: Int) {
        let rows = justified(aspects, width: box.x, height: box.y, gap: gap)
        let cols = justified(aspects.map { 1 / $0 }, width: box.y, height: box.x, gap: gap)
        if let r = rows, cols == nil || r.score >= cols!.score - 1e-4 {
            let most = r.lines.map(\.count).max() ?? 1
            let frames = r.frames.map { f -> CollageFrame in
                let column = min(most - 1, max(0, Int(((f.centre.x + r.size.x / 2) / max(r.size.x, 1e-5)) * Float(most))))
                return CollageFrame(centre: f.centre, size: f.size, row: f.line, column: column)
            }
            return (frames, r.size, r.lines.count, most)
        }
        guard let c = cols else { return ([], .zero, 1, 1) }
        // Columns: lines run left to right, slides down each one.
        let most = c.lines.map(\.count).max() ?? 1
        let size = SIMD2(c.size.y, c.size.x)
        let frames = c.frames.map { f -> CollageFrame in
            let centre = SIMD2(-f.centre.y, -f.centre.x)
            let row = min(most - 1, max(0, Int(((size.y / 2 - centre.y) / max(size.y, 1e-5)) * Float(most))))
            return CollageFrame(centre: centre, size: SIMD2(f.size.y, f.size.x), row: row, column: f.line)
        }
        return (frames, size, most, c.lines.count)
    }

    private struct Justified {
        var frames: [(centre: SIMD2<Float>, size: SIMD2<Float>, line: Int)]
        var lines: [Range<Int>]
        var size: SIMD2<Float>
        var score: Float
    }

    /// The best justified rows for `a` in a `width` × `height` box.
    private static func justified(_ a: [Float], width W: Float, height H: Float, gap: Float) -> Justified? {
        let n = a.count
        guard n > 0, W > 0, H > 0 else { return nil }
        var prefix = [Float](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + a[i] }
        var best: Justified?
        for k in 1...min(n, 20) {
            let lines = partition(prefix, into: k)
            // The width every row is scaled to, so the block fits the box.
            var inverse: Float = 0, gaps: Float = 0
            for l in lines {
                let sum = prefix[l.upperBound] - prefix[l.lowerBound]
                inverse += 1 / sum
                gaps += Float(l.count - 1) / sum
            }
            let w = min(W, (H - Float(k - 1) * gap + gap * gaps) / max(inverse, 1e-6))
            guard w > 0 else { continue }
            var heights: [Float] = [], area: Float = 0
            for l in lines {
                let sum = prefix[l.upperBound] - prefix[l.lowerBound]
                let h = (w - Float(l.count - 1) * gap) / sum
                heights.append(h)
                area += h * h * sum
            }
            guard let lo = heights.min(), let hi = heights.max(), lo > 0 else { continue }
            let score = area / (W * H) - 0.08 * (1 - lo / hi)
            guard score > (best?.score ?? -.greatestFiniteMagnitude) else { continue }
            let total = heights.reduce(0, +) + Float(k - 1) * gap
            var frames: [(centre: SIMD2<Float>, size: SIMD2<Float>, line: Int)] = []
            var y = total / 2
            for (li, l) in lines.enumerated() {
                let h = heights[li]
                var x = -w / 2
                for i in l {
                    let wi = a[i] * h
                    frames.append((SIMD2(x + wi / 2, y - h / 2), SIMD2(wi, h), li))
                    x += wi + gap
                }
                y -= h + gap
            }
            best = Justified(frames: frames, lines: lines, size: SIMD2(w, total), score: score)
        }
        return best
    }

    /// Splits the sequence with running sums `prefix` into `k` runs whose sums
    /// are as even as they can be: least squares from the mean, by dynamic programming.
    private static func partition(_ prefix: [Float], into k: Int) -> [Range<Int>] {
        let n = prefix.count - 1
        guard k > 1, n > 1 else { return [0..<n] }
        let target = prefix[n] / Float(k)
        // cost[j][i]: the best for the first i items in j + 1 runs.
        var cost = [[Float]](repeating: [Float](repeating: .greatestFiniteMagnitude, count: n + 1), count: k)
        var cut = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: k)
        for i in 1...n {
            let d = prefix[i] - target
            cost[0][i] = d * d
        }
        for j in 1..<k {
            for i in (j + 1)...n {
                for l in j..<i {
                    let d = prefix[i] - prefix[l] - target
                    let c = cost[j - 1][l] + d * d
                    if c < cost[j][i] { cost[j][i] = c; cut[j][i] = l }
                }
            }
        }
        var bounds: [Int] = [n]
        var i = n
        for j in stride(from: k - 1, to: 0, by: -1) {
            i = cut[j][i]
            bounds.append(i)
        }
        bounds.append(0)
        bounds.reverse()
        return (0..<k).map { bounds[$0]..<bounds[$0 + 1] }
    }

    /// A deck whose shapes differ by more than 30 %, widest against narrowest.
    public static func isMixed(_ aspects: [Float]) -> Bool {
        guard let lo = aspects.min(), let hi = aspects.max(), lo > 0 else { return false }
        return hi / lo > 1.3
    }

    /// The share of the box the slides cover, whole.
    public var coverage: Float {
        let area = cells.reduce(Float(0)) { $0 + $1.size.x * $1.size.y }
        return area / max(safeSize.x * safeSize.y, 1e-6)
    }
}

@inline(__always) func simdLength(_ v: SIMD2<Float>) -> Float { (v.x * v.x + v.y * v.y).squareRoot() }

public extension GridSettings {
    /// How many cards a deck of `slides` gets: the grid's cells, or one for
    /// each slide (up to 100) in a collage.
    func cells(slides: Int) -> Int {
        arrangement == .collage ? min(max(slides, 1), Self.collageLimit) : cellCount
    }

    /// This grid refitted to a deck of `count` slides of `slideAspect` on a
    /// canvas of `aspect`. The shape stays Auto wherever Auto already lands on
    /// the fitted shape, so the grid keeps working across canvas formats.
    /// `clear` is the room a caption keeps at the top or foot of the frame.
    /// A deck of mixed shapes (`aspects`, widest over narrowest more than
    /// 30 % apart) of up to 100 slides becomes a collage; a deck of one shape
    /// keeps its grid. A big deck gets a finer gap and smaller corners.
    func fitted(count: Int, aspect: Float, slideAspect: Float, aspects: [Float] = [], clear: Clearance = .none) -> GridSettings {
        var g = self
        let n = max(1, count)
        if n >= 80 {
            g.gap = min(g.gap, 6)
            g.corner = min(g.corner, 4)
        } else if n >= 40 {
            g.gap = min(g.gap, 10)
            g.corner = min(g.corner, 8)
        }
        if aspects.count == count, count <= GridSettings.collageLimit, GridLayout.isMixed(aspects) {
            g.arrangement = .collage
            g.order = .reading
            let l = GridLayout(settings: g, aspect: aspect, slideAspect: slideAspect, aspects: aspects, clear: clear)
            g.columns = l.columns
            g.rows = l.rows
            g.shape = .auto
            return g
        }
        g.arrangement = .grid
        let f = GridLayout.fit(count: count, aspect: aspect, slideAspect: slideAspect, base: g, clear: clear)
        g.columns = f.columns
        g.rows = f.rows
        g.shape = .auto
        if GridLayout(settings: g, aspect: aspect, slideAspect: slideAspect, clear: clear).shape != f.shape { g.shape = f.shape }
        return g
    }
}
