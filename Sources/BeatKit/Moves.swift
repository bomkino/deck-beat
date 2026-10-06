import Foundation
import StageKit

// Cards cut into pieces, and grids that leave their cells: the shapes a drop
// re-forms into, slats and pages for turning a card over, threads for a weave.
// Pure functions of their inputs, like everything the scene draws.

/// `v` turned the way the stage turns a card by `r`: yaw (y), then pitch (x),
/// then roll (z), so a point on a card lands where the renderer draws it.
@inline(__always) func turned(_ v: SIMD3<Float>, by r: SIMD3<Float>) -> SIMD3<Float> {
    let cz = cosf(r.z), sz = sinf(r.z)
    var p = SIMD3(v.x * cz - v.y * sz, v.x * sz + v.y * cz, v.z)
    let cx = cosf(r.x), sx = sinf(r.x)
    p = SIMD3(p.x, p.y * cx - p.z * sx, p.y * sx + p.z * cx)
    let cy = cosf(r.y), sy = sinf(r.y)
    return SIMD3(p.x * cy + p.z * sy, p.y, -p.x * sy + p.z * cy)
}

enum Pieces {
    /// `card` cut across into `count` strips, top to bottom, each where it lies
    /// on the whole card. Each strip keeps the whole card's corners and media.
    static func strips(_ card: CardPose, count: Int) -> [CardPose] {
        let k = max(count, 1)
        let h = card.size.y / Float(k)
        let c = card.crop
        var out: [CardPose] = []
        out.reserveCapacity(k)
        for i in 0..<k {
            var piece = card
            let v0 = Float(i) / Float(k), v1 = Float(i + 1) / Float(k)
            piece.crop = SIMD4(c.x, c.y + (c.w - c.y) * v0, c.z, c.y + (c.w - c.y) * v1)
            piece.size = SIMD2(card.size.x, h)
            piece.position = card.position + turned(SIMD3(0, card.size.y / 2 - (Float(i) + 0.5) * h, 0), by: card.rotation)
            out.append(piece)
        }
        return out
    }

    /// `card` turned about its left edge by `angle`; a negative angle lifts its
    /// right edge towards the camera, as a page is turned.
    static func hinged(_ card: CardPose, angle: Float) -> CardPose {
        var c = card
        let hinge = SIMD3<Float>(-card.size.x / 2, 0, 0)
        let pin = card.position + turned(hinge, by: card.rotation)
        c.rotation.y += angle
        c.position = pin - turned(hinge, by: c.rotation)
        return c
    }

    /// Slats for blinds: more on a squarer card, so each stays a slat.
    static func slats(_ card: CardPose) -> Int {
        min(max(Int((card.size.y / max(card.size.x, 1e-5) * 9).rounded()), 3), 7)
    }

    /// A loose thread's band: its core narrows and the shade gathers as it tears (0…1).
    static func thread(tear: Float, salt: Float) -> SIMD4<Float> {
        SIMD4(mix(0.85, 0.2 + 0.12 * salt, Ease.smooth(tear / 0.85)), Ease.smooth((tear - 0.02) / 0.25), tear * 0.4, tear * 0.18)
    }
}

/// Where a card goes in the shape a grid re-forms into on a drop.
struct Placement {
    var position: SIMD3<Float>
    var rotation: SIMD3<Float>
    /// Width in world units; the card takes its slide's own shape.
    var width: Float
    /// Multiplies its light, its opacity and its shadow; adds softness in pixels.
    var shade: Float = 1
    var opacity: Float = 1
    var shadow: Float = 1
    var blur: Float = 0
}

enum Shapes {
    /// The shape for every cell at `beats` after the drop, `through` 0…1 of
    /// the hold. `aspects` is each cell's slide shape; `cover` the cover's cell.
    static func placements(_ move: DropMove, layout: GridLayout, aspects: [Float], cover: Int, beats: Double,
                           through: Float) -> [Placement] {
        let n = layout.count
        guard n > 0, aspects.count == n else { return [] }
        let W = layout.safeSize.x, H = layout.safeSize.y
        let centre = SIMD3(layout.safeCentre.x, layout.safeCentre.y, 0)
        let typical = max(layout.slideAspect, 0.2)
        let b = max(beats, 0)
        // A step on each beat, quick off the beat and settled by its second sixteenth.
        let tick = Float(b.rounded(.down)) + Ease.inOutCubic(Float(b - b.rounded(.down)) / 0.4)
        // A bump on each beat, for the parts that breathe with the bass.
        let bump = expf(-Float(b - b.rounded(.down)) * 6)
        var out = [Placement](repeating: Placement(position: centre, rotation: .zero, width: 0.1), count: n)

        switch move {
        case .strip:
            // One column down a tall frame (a row across a wide one), turned a
            // little like film on a reel, stepping along one slide per beat.
            let vertical = layout.aspect < 1
            let yaw: Float = vertical ? 0.3 : 0.12, pitch: Float = vertical ? 0.1 : 0.28
            let w = vertical ? min(W * 0.8, H * 0.26 * typical) : min(W * 0.26, H * 0.62 * typical)
            let h = w / typical
            let gap = max(layout.gap * 1.5, (vertical ? h : w) * 0.08)
            let step = (vertical ? h : w) + gap
            let scroll = Float(n - 1) / 2 + tick
            for c in 0..<n {
                let along = (Float(c) - scroll) * step
                let local = vertical ? SIMD3<Float>(0, -along, 0) : SIMD3<Float>(along, 0, 0)
                let p = GridLayout.turn(local, pitch: pitch, yaw: yaw)
                out[c] = Placement(position: centre + p, rotation: SIMD3(-pitch, yaw, 0), width: w)
            }

        case .fan:
            // A hand of cards from a pivot below, the cover on top in the middle,
            // opening a little on each beat and swaying over two bars.
            let w = min(W * 0.56, H * 0.34 * typical)
            let h = w / typical
            let radius = h * 1.9
            let spread = min(2.3, 0.18 * Float(max(n - 1, 0)) + 0.3)
            // Deal order across the hand: reading order, the cover moved to the middle.
            var order = Array(0..<n).filter { $0 != cover }
            order.insert(cover, at: min(order.count, n / 2))
            func angle(_ slot: Int, open: Float) -> Float {
                n > 1 ? (Float(slot) / Float(n - 1) - 0.5) * spread * open : 0
            }
            // Fit the hand at rest inside the box, so the breath never changes its size.
            var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
            for slot in 0..<n {
                let a = angle(slot, open: 1)
                let mid = SIMD2(radius * sinf(a), radius * cosf(a))
                for corner in [SIMD2<Float>(-w / 2, -h / 2), SIMD2(w / 2, -h / 2), SIMD2(-w / 2, h / 2), SIMD2(w / 2, h / 2)] {
                    let q = mid + SIMD2(corner.x * cosf(a) + corner.y * sinf(a), -corner.x * sinf(a) + corner.y * cosf(a))
                    lo = SIMD2(min(lo.x, q.x), min(lo.y, q.y))
                    hi = SIMD2(max(hi.x, q.x), max(hi.y, q.y))
                }
            }
            let span = hi - lo
            let k = min(W * 0.9 / max(span.x, 1e-5), H * 0.86 / max(span.y, 1e-5), 1)
            let middle = (lo + hi) / 2
            let sway = 0.05 * sinf(2 * .pi * Float(b) / 8)
            let open = 1 + 0.05 * bump
            for (slot, c) in order.enumerated() {
                let a = angle(slot, open: open) + sway
                let mid = (SIMD2(radius * sinf(a), radius * cosf(a)) - middle) * k
                // The middle of the hand on top, each side tucked under it.
                let z = 0.02 + 0.004 * (Float(n) / 2 - abs(Float(slot) - Float(n - 1) / 2))
                out[c] = Placement(position: centre + SIMD3(mid.x, mid.y, z), rotation: SIMD3(0, 0, -a), width: w * k)
            }

        case .tunnel:
            // The cover at the front, the rest on a spiral going back round it,
            // turning, the whole tunnel drifting towards the camera over the hold.
            // The spiral widens with depth, so its walls stay in view around the
            // cover and close in only gently towards the far end.
            let w = min(W * 0.62, H * 0.36 * typical)
            let d = GridLayout.eyeDistance
            let rim = SIMD2(W * 0.42, H * 0.3)
            let depth: Float = 0.24
            let order = layout.distances(from: layout.cells[layout.centreCell].centre).enumerated()
                .sorted { ($0.element, $0.offset != cover ? 1 : 0, $0.offset) < ($1.element, $1.offset != cover ? 1 : 0, $1.offset) }
                .map(\.offset)
            var ranked = order.filter { $0 != cover }
            ranked.insert(cover, at: 0)
            let spin = 2 * Float.pi * 0.05 * Float(b)
            let travel = depth * 0.9 * min(max(through, 0), 1)
            for (k, c) in ranked.enumerated() {
                let a = Float(k) * 2.39996 + spin
                let z = 0.04 - Float(k) * depth + travel
                // Where the card sits as seen from the camera, then pushed back to its depth.
                let near = d / max(d - z, 0.2)
                let seen = rim * min(1, Float(k) / 2) * (0.6 + 0.4 * near)
                let r = seen / near
                // Each card faces a little into the tunnel.
                let lean = 0.25 * min(1, Float(k) / 2)
                out[c] = Placement(position: centre + SIMD3(r.x * cosf(a), r.y * sinf(a), z),
                                   rotation: SIMD3(lean * sinf(a), -lean * cosf(a), 0), width: w,
                                   shade: 0.35 + 0.65 * expf(min(z, 0) * 0.5), opacity: 1 - Ease.smooth((z - 0.3) / 0.2),
                                   shadow: 0, blur: max(0, -z) * 2.5)
            }

        case .light, .weave:
            break
        }
        return out
    }
}
