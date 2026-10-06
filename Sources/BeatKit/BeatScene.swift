import Foundation
import RenderCore
import StageKit

/// The grid of slides answering a song: a pure function of time over a
/// worked-out plan, so the preview is the export and scrubbing is exact.
public struct BeatScene: StageScene {
    public let id = "deck-beat"
    public let name = "Deck Beat"
    public let summary = "Slides in a grid, lit by the music."
    public var dials: [(DialKey, String)] { [] }
    public var defaults: SceneDials { SceneDials() }

    public let plan: BeatPlan
    public let layout: GridLayout
    public let settings: BeatSettings
    /// The look's corner factor (0.4 + 1.6 × corners), so corners come out in pixels.
    public let cornerScale: Float
    /// Where each slide is cropped around in a filled cell (0…1, y down).
    public let focals: [SIMD2<Float>]

    public init(plan: BeatPlan, layout: GridLayout, settings: BeatSettings, cornerScale: Float = 1, focals: [SIMD2<Float>] = []) {
        self.plan = plan
        self.layout = layout
        self.settings = settings
        self.cornerScale = max(cornerScale, 0.05)
        self.focals = focals
    }

    /// Where a filled cell crops a slide: left of centre, where a deck's titles
    /// start, and a little above the middle.
    public static let defaultFocal = SIMD2<Float>(0.38, 0.45)

    func focal(_ slide: Int) -> SIMD2<Float> { slide < focals.count ? focals[slide] : Self.defaultFocal }

    public func loopDuration(_ ctx: SceneContext) -> Double { plan.length }
    public func soundEvents(_ ctx: SceneContext) -> [SoundEvent] { [] }

    // MARK: Frame

    public func frame(at time: Double, _ ctx: SceneContext) -> StageFrame {
        var frame = StageFrame()
        frame.shadowsOnCards = false
        frame.fixedGround = true
        let items = ctx.items
        guard !items.isEmpty, plan.cells == layout.count else { return frame }
        // Longer exports play the clip again.
        let t = time > plan.length + 1e-6 ? wrap(time, plan.length) : max(time, 0)
        let n = layout.count
        let s = settings
        let atmosphere = s.atmosphere / 0.5
        let beat = plan.beatPosition(at: t)
        let inhale = plan.inhale(at: t)

        // The loop outro plays the intro backwards, so the last frame is the first.
        let outro = plan.outro
        var poseTime = t
        var reverseBlend: Float = 0
        if outro.kind == .loop, t > outro.start {
            poseTime = plan.length - t
            reverseBlend = smoothstep(Float(outro.start), Float(outro.start + plan.period * 2), Float(t))
        }
        let kick = BeatPlan.sample(plan.pulse, t) * (1 - reverseBlend)

        // A featured slide, and how far forward it is.
        var heroCell: Int? = nil
        var heroCard: CardPose? = nil
        var focus: Float = 0
        for (k, f) in plan.features.enumerated() where t > f.liftOff - 0.01 && t < f.end + 0.01 {
            let p = heroProgress(f, at: t)
            focus = max(focus, p.amount)
            let slide = min(f.slide, items.count - 1)
            if let c = f.cell {
                heroCell = c
                heroCard = hero(slide: slide, from: c, progress: p, kick: kick, ctx: ctx, occurrence: c)
            } else {
                heroCard = hero(slide: slide, from: nil, progress: p, kick: kick, ctx: ctx, occurrence: 100_000 + k)
            }
        }

        var cards: [CardPose] = []
        cards.reserveCapacity(n + 1)
        var deepest: Float = 0
        for c in 0..<n {
            if c == heroCell, let h = heroCard { cards.append(h); continue }
            guard var card = cell(c, at: t, poseTime: poseTime, reverseBlend: reverseBlend, beat: beat, inhale: inhale,
                                  focus: focus, kick: kick, ctx: ctx) else { continue }
            card.layer = max(card.layer, 0)
            deepest = min(deepest, card.position.z)
            cards.append(card)
        }
        if heroCell == nil, let h = heroCard { cards.append(h) }
        frame.cards = cards
        frame.groundZ = min(-0.05, deepest - 0.04)
        if s.grid.wall.reflection > 0.001 {
            frame.reflection = s.grid.wall.reflection
            let bottom = layout.place(SIMD3(0, -layout.gridSize.y / 2, 0)).y
            frame.floorY = bottom - layout.gap
        }
        // The camera leans in on loud downbeats and drops, and draws back for the breath before a drop.
        let d = GridLayout.eyeDistance
        frame.camera.offset.z = -d * plan.punch(at: t) * atmosphere + d * 0.02 * inhale * atmosphere
        return frame
    }

    // MARK: Cells

    func cell(_ c: Int, at t: Double, poseTime: Double, reverseBlend: Float, beat: Double, inhale: Float, focus: Float,
              kick: Float, ctx: SceneContext) -> CardPose? {
        let s = settings
        let plan = self.plan
        let geometry = layout.cells[c]
        let (slide0, turn) = plan.slide(cell: c, at: t)
        let slide = min(slide0, ctx.items.count - 1)
        let itemAspect = ctx.items[slide].aspect
        let rest = s.rest, lit = s.lit

        // How lit it is.
        var light = plan.light(cell: c, at: t)
        if !plan.levels.isEmpty { light.level = 1 - (1 - light.level) * (1 - meter(geometry, at: t)) }
        let intro = plan.intro
        let isCover = intro.coldOpen && c == intro.coverCell
        if reverseBlend > 0 {
            // Looping back: the lights fade over to the intro's, played backwards.
            var back = plan.light(cell: c, at: poseTime)
            if isCover, poseTime < intro.end { back.level = 1 }
            light.level = mix(light.level, back.level, reverseBlend)
            light.glint *= 1 - reverseBlend
        }
        if isCover, t < intro.end { light.level = 1 }
        // Behind a featured slide the music plays quieter.
        if focus > 0 { light.level *= 1 - 0.6 * focus }
        // Lights out: one by one the slides go dark; the end card comes up last and holds.
        var dark: Float = 0
        let outro = plan.outro
        if outro.kind == .lightsOut, reverseBlend == 0 {
            if c == intro.coverCell {
                light.level = max(light.level, smoothstep(Float(outro.end - outro.fade), Float(outro.end), Float(t)))
            } else {
                dark = smoothstep(Float(outro.leaves[c]), Float(outro.leaves[c] + outro.fade), Float(t))
                light.level *= 1 - dark
            }
        }
        let L = min(max(light.level, 0), 1)
        let e7 = powf(L, 0.7), e2 = L * L

        // A spring after each hit: size and lift overshoot, then settle.
        var spring: Float = 0
        if light.since < 0.6 {
            let x = Float(light.since)
            spring = light.last * expf(-x / 0.09) * sinf(2 * .pi * x / 0.2) / 0.574
        }
        let bounce = s.motion.bounce
        var scale = mix(rest.scale, lit.scale, L) + (lit.scale - rest.scale) * bounce * spring
        var lift = mix(rest.lift, lit.lift, L) + (lit.lift - rest.lift) * bounce * spring
        var bright = mix(rest.brightness * (1 - 0.25 * inhale), lit.brightness, e7)
        let colour = mix(rest.colour, lit.colour, e7)
        let glow = mix(rest.glow, lit.glow, e2) + light.glint * 0.35
        let opacity = mix(rest.opacity, lit.opacity, L)
        var blur = mix(rest.blur, lit.blur, e7)
        let tilt = mix(rest.tilt, lit.tilt, L) * .pi / 180
        let shadow = mix(rest.shadow, lit.shadow, L)
        let open = layout.shape == .fill ? mix(rest.open, lit.open, L) : 0

        // A slide out front pulls attention from the rest.
        if focus > 0 {
            let k: Float = s.spotlight ? 0.6 : 0.4
            bright *= 1 - focus * k
            blur += focus * (s.spotlight ? 6 : 4)
            lift *= 1 - focus * (s.spotlight ? 1 : 0.5)
        }
        if dark > 0 {
            bright *= 1 - dark
            blur *= 1 - dark
        }

        // Slow movement at rest.
        var offset = SIMD2<Float>.zero
        var roll: Float = 0
        let idle = s.motion.idleAmount * (1 - L)
        if idle > 0.001 {
            let phase = 2 * Float.pi * Float(beat / 8) - 2 * .pi * Float(c) / Float(max(layout.count, 1))
            switch s.motion.idle {
            case .breathe:
                scale += idle * 0.03 * sinf(phase)
                bright *= 1 + idle * 0.15 * sinf(phase)
            case .float:
                let seed = hash(c, 17) * 2 * .pi
                offset = SIMD2(cosf(Float(beat / 16) * 2 * .pi + seed) * 0.006, sinf(Float(beat / 16) * 2 * .pi + seed * 1.3) * 0.012) * idle
            case .sway:
                roll = sinf(Float(beat / 16) * 2 * .pi + Float(c) * 0.7) * 3 * .pi / 180 * idle
            case .off:
                break
            }
        }

        // Size: the cell, scaled, opening towards the slide's own shape.
        var size = geometry.size * scale
        if open > 0.001 {
            let a = geometry.size.x / geometry.size.y
            if itemAspect > a { size.x = mix(size.x, size.y * itemAspect, open) } else { size.y = mix(size.y, size.x / itemAspect, open) }
        }

        // Lean away from where the light came from, or a seeded way.
        var lean = light.lean
        if lean == .zero {
            let a = hash(c, 5) * 2 * .pi
            lean = SIMD2(cosf(a), sinf(a))
        }
        var rotation = layout.wallRotation + SIMD3(-tilt * lean.y, tilt * lean.x, roll)
        var position = layout.place(SIMD3(geometry.centre.x + offset.x, geometry.centre.y + offset.y, 0))
        position.z += lift

        // Turning over to a new slide.
        if turn != 0 {
            let p = Ease.inOutCubic(abs(turn))
            rotation.y += (turn < 0 ? (1 - p) : -(1 - p)) * .pi / 2
        }

        var card = CardPose(media: slide, occurrence: c, position: position, rotation: rotation, size: size, opacity: opacity)
        card.mediaAspect = itemAspect
        card.fit = .fill
        card.focal = focal(slide)
        card.saturation = colour
        card.color = SIMD4(SIMD3(repeating: powf(max(bright, 0), 2)) * gel(L), 1)
        card.glow = glow
        card.blur = blur
        card.shadow = shadow
        card.corner = corner(for: size)
        card.layer = L > 0.08 ? 1 : 0

        // Arriving and leaving.
        if let moved = entrance(card, c: c, geometry: geometry, at: poseTime, reverse: reverseBlend > 0, kick: kick, ctx: ctx, real: t) {
            card = moved
        } else {
            return nil
        }
        return card
    }

    /// The equaliser's level for a cell.
    func meter(_ g: GridLayout.Cell, at t: Double) -> Float {
        let column = min(g.column, plan.levels.count - 1)
        let rows = Float(layout.rows)
        let fill = BeatPlan.sample(plan.levels[column], t)
        let peak = BeatPlan.sample(plan.peaks[column], t)
        if settings.fromMiddle {
            let middle = (rows - 1) / 2
            let d = abs(Float(g.row) - middle)
            let reach = fill / rows * (middle + 0.5)
            var e = min(max(reach - d + 0.5, 0), 1)
            let peakReach = peak / rows * (middle + 0.5)
            if peakReach > 0.6, Int(peakReach - 0.5 + 0.5) == Int(d + 0.5) { e = max(e, 0.5) }
            return e
        }
        let fromBottom = rows - 1 - Float(g.row)
        var e = min(max(fill - fromBottom, 0), 1)
        if peak > 0.6, Int(peak - 0.001) == Int(fromBottom) { e = max(e, 0.5) }
        return e
    }

    func corner(for size: SIMD2<Float>) -> Float {
        let r = settings.grid.corner * layout.px
        return min(r / max(cornerScale * min(size.x, size.y), 1e-5), 0.5)
    }

    // MARK: Intro and outro

    /// The card on its way in or out at `t`, or nil while it is off stage.
    func entrance(_ card: CardPose, c: Int, geometry: GridLayout.Cell, at t: Double, reverse: Bool, kick: Float,
                  ctx: SceneContext, real: Double) -> CardPose? {
        let intro = plan.intro
        let outro = plan.outro
        // Close: leaving in reverse, the cover rising to hold the end.
        if outro.kind == .close, !reverse {
            if c == intro.coverCell, real > outro.coverRise {
                let p = Float(min(1, (real - outro.coverRise) / outro.flight))
                return coverHero(card, geometry: geometry, amount: Ease.place(p), kick: kick, push: Float((real - outro.coverRise) / 3), ctx: ctx)
            }
            let leave = outro.leaves[c]
            if real >= leave {
                let p = Float((real - leave) / outro.flight)
                if p >= 1 { return nil }
                return flight(card, c: c, geometry: geometry, progress: 1 - p, ctx: ctx)
            }
        }
        if t >= intro.end { return card }
        if intro.coldOpen, c == intro.coverCell {
            // Frame 0 is the cover, large and lit; it goes back to its cell as the grid arrives.
            let p: Float = t < intro.coverMove ? 0 : Float((t - intro.coverMove) / max(intro.end - intro.coverMove, 1e-3))
            return coverHero(card, geometry: geometry, amount: 1 - Ease.place(p), kick: kick, push: Float(t / max(intro.coverMove, 0.3)), ctx: ctx)
        }
        let land = intro.landings[c]
        let begin = land - intro.flight
        if t < begin { return nil }
        if t >= land { return card }
        return flight(card, c: c, geometry: geometry, progress: Float((t - begin) / intro.flight), ctx: ctx)
    }

    /// The cover between its cell (0) and held up large (1).
    func coverHero(_ card: CardPose, geometry: GridLayout.Cell, amount: Float, kick: Float, push: Float, ctx: SceneContext) -> CardPose {
        var card = card
        let aspect = card.mediaAspect
        let big = layout.heroSize(aspect: aspect)
        let centre = SIMD3(layout.safeCentre.x, layout.safeCentre.y, Float(0.06))
        // From frame 1 it is already moving: a slow push in, and a punch on the kick.
        let grow = 1 + 0.03 * min(max(push, 0), 1) + 0.015 * kick
        let a = min(max(amount, 0), 1)
        card.position = mix3(card.position, centre, a)
        card.size = SIMD2(mix(card.size.x, big.x * grow, a), mix(card.size.y, big.y * grow, a))
        card.rotation = card.rotation * (1 - a)
        card.color = SIMD4(SIMD3(repeating: mix(card.color.x, powf(settings.lit.brightness, 2), a)), 1)
        card.saturation = mix(card.saturation, settings.lit.colour, a)
        card.blur *= 1 - a
        card.opacity = mix(card.opacity, 1, a)
        card.shadow = mix(card.shadow, 1.4, a)
        card.corner = corner(for: card.size)
        if a > 0.001 { card.layer = 3 }
        return card
    }

    /// A card in flight to its cell: 0 off stage, 1 landed.
    func flight(_ card: CardPose, c: Int, geometry: GridLayout.Cell, progress p: Float, ctx: SceneContext) -> CardPose {
        var card = card
        let p = min(max(p, 0), 1)
        let target = card.position
        let side: Float = hash(c, 31) < 0.5 ? -1 : 1
        card.layer = 2
        func fade(_ span: Float) { card.opacity *= min(1, p / max(span, 1e-3)) }
        switch settings.intro.entrance {
        case .deal:
            // From a stack behind the cover (or below the grid), arcing into place.
            let origin: SIMD3<Float> = plan.intro.coldOpen
                ? SIMD3(layout.safeCentre.x, layout.safeCentre.y, 0.02)
                : layout.place(SIMD3(0, -layout.gridSize.y * 0.62, 0.02))
            let e = back(p, 1.2)
            card.position = mix3(origin, target, e)
            card.position.z += sinf(.pi * min(p, 1)) * 0.08
            card.rotation.z += side * (1 - Ease.outCubic(p)) * 8 * .pi / 180
            card.size *= mix(0.86, 1, Ease.outCubic(p))
            if !plan.intro.coldOpen { fade(0.2) }
        case .rise:
            let e = back(p, 1.05)
            card.position.y += (1 - e) * -0.06
            card.size *= mix(0.92, 1, e)
            card.blur += (1 - Ease.outCubic(p)) * 8
            fade(0.35)
        case .depth:
            let e = Ease.outCubic(p)
            card.position.z += (1 - e) * -0.8
            card.blur += (1 - e) * 16
            fade(0.4)
        case .flip:
            let e = back(p, 0.9)
            card.rotation.y += (1 - e) * .pi / 2 * (geometry.column % 2 == 0 ? 1 : -1)
            fade(0.1)
        case .drop:
            card.position.y += (1 - bounceOut(p)) * 0.55
            fade(0.15)
        case .assemble:
            let e = back(p, 1.0)
            let scatter = SIMD3(hash(c, 41) * 2 - 1, hash(c, 43) * 2 - 1, hash(c, 47) * 0.3) * SIMD3(0.45, 0.5, 0.2)
            card.position += (scatter + SIMD3(card.position.x, card.position.y, 0) * 0.5) * (1 - e)
            card.rotation.z += (hash(c, 53) * 2 - 1) * 25 * .pi / 180 * (1 - e)
            fade(0.3)
        case .unfold:
            card.fold = 1 - Ease.outCubic(p)
            card.reveal = Ease.inOutCubic(min(1, p * 1.2))
            card.foldPhase = 0
            fade(0.15)
        }
        return card
    }

    // MARK: Feature moments

    struct HeroProgress {
        /// 0 in the grid, 1 out front (may overshoot).
        var position: Float
        /// How much attention it holds, 0…1.
        var amount: Float
        var lift: Float
    }

    func heroProgress(_ f: FeatureMoment, at t: Double) -> HeroProgress {
        if t < f.land {
            let p = Float(min(max((t - f.liftOff) / max(f.land - f.liftOff, 1e-3), 0), 1))
            // It rises before it travels.
            return HeroProgress(position: back(p, 1.05), amount: Ease.smooth(p), lift: Ease.outCubic(min(1, p * 1.4)))
        }
        if t < f.leave { return HeroProgress(position: 1, amount: 1, lift: 1) }
        let p = Float(min(max((t - f.leave) / max(f.end - f.leave, 1e-3), 0), 1))
        let e = Ease.place(p)
        return HeroProgress(position: 1 - e, amount: 1 - Ease.smooth(p), lift: 1 - Ease.inOutCubic(max(0, p * 1.3 - 0.3)))
    }

    func hero(slide: Int, from cell: Int?, progress p: HeroProgress, kick: Float, ctx: SceneContext, occurrence: Int) -> CardPose {
        let aspect = ctx.items[slide].aspect
        let s = settings
        let spot = s.spotlight
        let big = layout.heroSize(aspect: aspect)
        let geometry = cell.map { layout.cells[$0] }
        let home = geometry.map { layout.place(SIMD3($0.centre.x, $0.centre.y, 0)) } ?? layout.place(.zero)
        let homeSize = geometry?.size ?? big * 0.3
        // Centred across, and most of the way from its cell to the middle of the box, kept inside it.
        var y = mix(home.y, layout.safeCentre.y, spot ? 0.85 : 0.6)
        let room = max(layout.safeSize.y / 2 - big.y / 2, 0)
        y = min(max(y, layout.safeCentre.y - room), layout.safeCentre.y + room)
        let out = SIMD3(layout.safeCentre.x, y, 0)
        var position = mix3(home, out, p.position)
        position.z = 0.25 * p.lift
        let grow = 1 + 0.015 * kick * p.amount
        let size = SIMD2(mix(homeSize.x * s.rest.scale, big.x, p.position), mix(homeSize.y * s.rest.scale, big.y, p.position)) * grow
        var card = CardPose(media: slide, occurrence: occurrence, position: position,
                            rotation: layout.wallRotation * (1 - p.amount), size: SIMD2(max(size.x, 0.001), max(size.y, 0.001)))
        card.mediaAspect = aspect
        card.fit = .fill
        card.focal = focal(slide)
        let b = mix(s.rest.brightness, max(s.lit.brightness, 1), p.amount)
        card.color = SIMD4(SIMD3(repeating: powf(b, 2)), 1)
        card.saturation = mix(s.rest.colour, max(s.lit.colour, 1), p.amount)
        card.glow = s.lit.glow * 0.4 * p.amount
        card.shadow = mix(s.rest.shadow, max(s.lit.shadow, 1) * 2, p.amount)
        card.opacity = geometry == nil ? min(1, p.amount * 1.5) : 1
        card.corner = corner(for: card.size)
        card.layer = 10
        return card
    }

    // MARK: Helpers

    /// The gel over a slide lit by `L`, as a linear multiplier.
    func gel(_ L: Float) -> SIMD3<Float> {
        let rest = settings.rest, lit = settings.lit
        guard rest.tint > 0.001 || lit.tint > 0.001 else { return SIMD3(repeating: 1) }
        let a = mix3(SIMD3(repeating: 1), RGB(hex: rest.tintColour).linear, min(max(rest.tint, 0), 1))
        let b = mix3(SIMD3(repeating: 1), RGB(hex: lit.tintColour).linear, min(max(lit.tint, 0), 1))
        return mix3(a, b, L)
    }

    func hash(_ i: Int, _ salt: UInt32) -> Float { Hash.unit(i, salt &+ settings.seed &* 7919) }
}

@inline(__always) func mix3(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

/// Ease out with overshoot: `s` 1.0 is about 5 %, 1.7 about 10 %.
@inline(__always) func back(_ x: Float, _ s: Float) -> Float {
    let p = min(max(x, 0), 1) - 1
    return 1 + (s + 1) * p * p * p + s * p * p
}

/// Falling and bouncing once.
@inline(__always) func bounceOut(_ x: Float) -> Float {
    let p = min(max(x, 0), 1)
    if p < 0.72 { let q = p / 0.72; return q * q }
    let q = (p - 0.86) / 0.14
    return 1 - 0.08 * (1 - q * q)
}
