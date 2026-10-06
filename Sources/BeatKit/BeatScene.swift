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
    /// Each cell's distance from the middle, 0…1: the order a drop reaches them in.
    let dropOrder: [Float]

    public init(plan: BeatPlan, layout: GridLayout, settings: BeatSettings, cornerScale: Float = 1, focals: [SIMD2<Float>] = []) {
        self.plan = plan
        self.layout = layout
        self.settings = settings
        self.cornerScale = max(cornerScale, 0.05)
        self.focals = focals
        dropOrder = layout.count > 0 ? layout.distances(from: layout.cells[layout.centreCell].centre) : []
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

        // A featured slide, and how far forward it is: stepping out of its
        // cell, or held where it hangs while the camera moves in on it.
        var heroCell: Int? = nil
        var heroCard: CardPose? = nil
        var zoom: (cell: Int, progress: HeroProgress)? = nil
        var focus: Float = 0
        for (k, f) in plan.features.enumerated() where t > f.liftOff - 0.01 && t < f.end + 0.01 {
            let p = heroProgress(f, at: t)
            focus = max(focus, p.amount)
            let slide = min(f.slide, items.count - 1)
            if let c = f.cell, s.featureStyle == .zoom {
                zoom = (c, p)
            } else if let c = f.cell {
                heroCell = c
                // It leaves its cell as the cell shows it now, so nothing jumps.
                let presented = cell(c, at: t, poseTime: poseTime, reverseBlend: reverseBlend, beat: beat, inhale: inhale, focus: 0,
                                     kick: kick, ctx: ctx).first
                heroCard = hero(slide: slide, from: c, presented: presented, progress: p, kick: kick, ctx: ctx, occurrence: c)
            } else {
                heroCard = hero(slide: slide, from: nil, presented: nil, progress: p, kick: kick, ctx: ctx, occurrence: 100_000 + k)
            }
        }

        // A drop's weave, or the shape the grid re-forms into.
        let moment = plan.moment(at: t)
        var shape: [Placement] = []
        if let m = moment, m.move.reforms, t >= m.time {
            let aspects = (0..<n).map { items[min(plan.slide(cell: $0, at: t).slide, items.count - 1)].aspect }
            let since = beat - plan.beatPosition(at: m.time)
            let through = Float((t - m.time) / max(m.leave - m.time, 1e-3))
            shape = Shapes.placements(m.move, layout: layout, aspects: aspects, cover: plan.intro.coverCell, beats: since, through: through)
        }

        var cards: [CardPose] = []
        cards.reserveCapacity(n + 1)
        var deepest: Float = 0
        for c in 0..<n {
            if c == heroCell, let h = heroCard { cards.append(h); continue }
            let featured = c == zoom?.cell
            let pieces = cell(c, at: t, poseTime: poseTime, reverseBlend: reverseBlend, beat: beat, inhale: inhale,
                              focus: featured ? 0 : focus, kick: kick, ctx: ctx, moment: moment, place: c < shape.count ? shape[c] : nil,
                              zoom: featured ? zoom?.progress : nil)
            for var card in pieces {
                card.layer = max(card.layer, 0)
                // Only cards that cast a shadow set where the shadows fall.
                if card.shadow > 0.01 { deepest = min(deepest, card.position.z) }
                cards.append(card)
            }
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
        var push = -d * plan.punch(at: t) * atmosphere + d * 0.02 * inhale * atmosphere
        if let z = zoom, z.progress.amount > 0.0005, let card = cards.first(where: { $0.occurrence == z.cell && $0.layer >= 10 }) {
            let view = Self.zoomCamera(on: card, amount: z.progress.amount, layout: layout)
            frame.camera.offset = view.offset
            frame.camera.target = view.target
            frame.camera.focusDistance = view.distance + card.position.z * (1 - z.progress.amount)
            // Closer in, the same lean moves the picture more, so it leans less.
            push *= view.distance / view.rest
        }
        frame.camera.offset.z += push
        frame.moodHints = moodHints(cards, camera: frame.camera, count: items.count)
        return frame
    }

    /// The camera moved in on `card` (`amount` 0 at rest … 1 in close): the card
    /// fills a slide held up to be read, centred in the feature box. It dollies
    /// straight in, evenly in scale, and never turns, so the grid stays square on.
    static func zoomCamera(on card: CardPose, amount a: Float, layout: GridLayout)
        -> (offset: SIMD3<Float>, target: SIMD3<Float>, distance: Float, rest: Float) {
        let d = GridLayout.eyeDistance
        let z = card.position.z
        let rest = d - z
        let big = layout.heroSize(aspect: card.size.x / max(card.size.y, 1e-5))
        let near = min(max(card.size.y * d / max(big.y, 1e-5), 0.12), rest)
        let r = expf(mix(logf(rest), logf(near), min(max(a, 0), 1)))
        let centre = SIMD2(card.position.x, card.position.y)
        let from = centre * d / rest
        let q = from + (layout.featureCentre - from) * min(max(a, 0), 1)
        let eye = centre - q * r / d
        return (SIMD3(eye.x, eye.y, z + r - d), SIMD3(eye.x, eye.y, 0), r, rest)
    }

    /// The slides setting the room's colour, as the camera shows them: each by
    /// its area on screen, nearer the middle counting for more, a card turned
    /// away not at all. So the room follows a zoom or a slide out front.
    func moodHints(_ cards: [CardPose], camera: StageCamera, count: Int) -> [MoodHint] {
        let d = GridLayout.eyeDistance
        let eye = SIMD3<Float>(0, 0, d) + camera.offset
        var weights = [Float](repeating: 0, count: count)
        for card in cards where card.opacity > 0.02 && !card.solid && card.media >= 0 && card.media < count {
            let k = d / max(eye.z - card.position.z, 0.05)
            let q = (SIMD2(card.position.x, card.position.y) - SIMD2(eye.x, eye.y)) * k / 0.33
            let facing = max(0, cosf(card.rotation.x) * cosf(card.rotation.y))
            weights[card.media] += expf(-(q.x * q.x + q.y * q.y)) * card.opacity * card.size.x * card.size.y * k * k * facing
        }
        return weights.indices.compactMap { weights[$0] > 1e-7 ? MoodHint(media: $0, weight: weights[$0]) : nil }
    }

    // MARK: Cells

    /// The card a cell shows at `t`, or the pieces it is cut into while it
    /// turns over, weaves or arrives; empty while it is off stage.
    func cell(_ c: Int, at t: Double, poseTime: Double, reverseBlend: Float, beat: Double, inhale: Float, focus: Float,
              kick: Float, ctx: SceneContext, moment: DropMoment? = nil, place: Placement? = nil, zoom: HeroProgress? = nil) -> [CardPose] {
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
        // Voices: a kick slide thumps (a stronger spring and a push back), a snare slide flicks.
        let voice = c < plan.intro.voices.count ? plan.intro.voices[c] : .low
        let voiced = s.mode == .voices
        var thump: Float = 0, flick: Float = 0
        if light.since < 0.6 {
            let x = Float(light.since)
            spring = light.last * expf(-x / 0.09) * sinf(2 * .pi * x / 0.2) / 0.574
            if voiced, voice == .low {
                spring *= 1.6
                thump = light.last * expf(-x / 0.06)
            } else if voiced, voice == .mid {
                flick = light.last * expf(-x / 0.1) * cosf(2 * .pi * x / 0.28)
            }
        }
        let bounce = s.motion.bounce
        var scale = mix(rest.scale, lit.scale, L) + (lit.scale - rest.scale) * bounce * spring
        var lift = mix(rest.lift, lit.lift, L) + (lit.lift - rest.lift) * bounce * spring - 0.012 * thump
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
            // With Feel, each card idles at its own pace.
            let rate = 1 + 0.25 * min(max(s.motion.feel, 0), 1) * (hash(c, 79) * 2 - 1)
            let beat = beat * Double(rate)
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

        // Size: the cell, scaled, opening towards the slide's own shape. A slide
        // much wider (or taller) than its cell opens to half as wide again and
        // gives up height for the rest, so it never sprawls over its row.
        var size = geometry.size * scale
        if open > 0.001 {
            var whole = size
            if itemAspect > size.x / size.y {
                whole.x = min(size.y * itemAspect, size.x * 1.5)
                whole.y = whole.x / itemAspect
            } else {
                whole.y = min(size.x / itemAspect, size.y * 1.5)
                whole.x = whole.y * itemAspect
            }
            size = SIMD2(mix(size.x, whole.x, open), mix(size.y, whole.y, open))
        }

        // Lean away from where the light came from, or a seeded way.
        var lean = light.lean
        if lean == .zero {
            let a = hash(c, 5) * 2 * .pi
            lean = SIMD2(cosf(a), sinf(a))
        }
        // Loose: each card a little turned, off its mark and smaller, as if pasted up by hand.
        if s.loose > 0.001 {
            let k = min(s.loose, 1)
            roll += (hash(c, 81) * 2 - 1) * 6 * .pi / 180 * k
            let room = layout.gap * 0.5 + 0.05 * min(geometry.size.x, geometry.size.y)
            offset += SIMD2(hash(c, 83) * 2 - 1, hash(c, 85) * 2 - 1) * room * k
            size *= 1 - 0.06 * k * hash(c, 87)
        }
        roll += flick * lean.x * 5 * .pi / 180
        var rotation = layout.wallRotation + SIMD3(-tilt * lean.y, tilt * lean.x, roll)
        var position = layout.place(SIMD3(geometry.centre.x + offset.x, geometry.centre.y + offset.y, 0))
        position.z += lift

        // Turning over to a new slide: a flip turns the card itself.
        let turning = s.turn == .flip ? nil : plan.turnover(cell: c, at: t)
        if turn != 0, turning == nil {
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

        // Other turns cut the card or lay one over it. They never meet the
        // intro, the ending or a drop, so nothing else moves it meanwhile.
        if let turning { return turnedOver(card, turning, ctx: ctx) }
        if let m = moment {
            if m.move == .weave { return weave(card, c: c, m, at: t, beat: beat) }
            if m.move.reforms { card = reformed(card, c: c, m, place: place, at: t, inhale: inhale, grow: scale / max(rest.scale, 0.05)) }
        }
        if let zoom { card = zoomed(card, geometry: geometry, amount: zoom.amount, kick: kick) }

        // Arriving and leaving.
        return entrance(card, c: c, geometry: geometry, at: poseTime, reverse: reverseBlend > 0, kick: kick, ctx: ctx, real: t)
    }

    /// Shows `slide` on `card`: its picture, shape and focal point.
    func show(_ card: inout CardPose, _ slide: Int, ctx: SceneContext) {
        let i = min(max(slide, 0), ctx.items.count - 1)
        card.media = i
        card.mediaAspect = ctx.items[i].aspect
        card.focal = focal(i)
    }

    /// A cell part way through turning from one slide to the next, in the
    /// chosen style; whole, as either slide, at each end.
    func turnedOver(_ card: CardPose, _ turn: (from: Int, to: Int, progress: Float), ctx: SceneContext) -> [CardPose] {
        var old = card, new = card
        show(&old, turn.from, ctx: ctx)
        show(&new, turn.to, ctx: ctx)
        let q = min(max(turn.progress, 0), 1)
        switch settings.turn {
        case .flip:
            return [card]
        case .wipe:
            // The new slide wipes across the old from the left, catching the light as it goes.
            let e = Ease.inOutCubic(q)
            if e <= 0.001 { return [old] }
            if e >= 0.999 { return [new] }
            new.reveal = e
            new.glow += 0.2 * sinf(.pi * e)
            return [old, new]
        case .page:
            // The old slide lifts from its right edge and turns away like a
            // page, bending as paper does, over the new one.
            let e = Ease.inOutCubic(q)
            if e <= 0.001 { return [old] }
            if e >= 0.999 { return [new] }
            var page = Pieces.hinged(old, angle: -e * (.pi / 2 + 0.25))
            page.flex = 0.55
            page.curl = 0.6 * sinf(.pi * e)
            page.opacity *= 1 - Ease.smooth((e - 0.82) / 0.18)
            let under = 0.72 + 0.28 * e
            new.color = SIMD4(new.color.x * under, new.color.y * under, new.color.z * under, new.color.w)
            return [new, page]
        case .blinds:
            // Slats turn over one after another down the card, old face to new.
            let k = Pieces.slats(card)
            let lag = 0.5 / Float(k)
            let olds = Pieces.strips(old, count: k), news = Pieces.strips(new, count: k)
            return (0..<k).map { i in
                let qi = min(max((q - Float(i) * lag) / (1 - Float(k - 1) * lag), 0), 1)
                let a = Ease.inOutCubic(qi) * .pi
                var slat = a < .pi / 2 ? olds[i] : news[i]
                slat.rotation.x += a < .pi / 2 ? a : a - .pi
                return slat
            }
        }
    }

    /// Threads a weave cuts a card into: about 10 px each at 1080, fewer on a big grid.
    func threads(for card: CardPose) -> Int {
        let k = Int((card.size.y / max(10 * layout.px, 1e-5)).rounded())
        return max(min(k, 14, 640 / max(layout.count, 1)), 3)
    }

    /// A drop's weave: over the bar before, the card comes apart into threads
    /// that slide apart and flutter; as the drop's light reaches it, they knit
    /// back together with a snap. Whole before and after.
    func weave(_ card: CardPose, c: Int, _ m: DropMoment, at t: Double, beat: Double) -> [CardPose] {
        let period = plan.period
        let knit = m.time + Double(c < dropOrder.count ? dropOrder[c] : 0) * period / 2
        let rise = (m.start + period * 0.5, m.time - period * 0.25)
        var tear: Float, pull: Float
        if t < knit - 0.03 {
            tear = 0.9 * Ease.inOutCubic(Float((t - rise.0) / max(rise.1 - rise.0, 1e-3)))
            pull = tear
        } else {
            let p = Float((t - (knit - 0.03)) / (period * 0.45))
            tear = 0.9 * (1 - Ease.outCubic(p))
            pull = 0.9 * (1 - back(p, 1.6))
        }
        // Its shadow fades before it comes apart and returns once it is whole.
        var whole = card
        let away = smoothstep(Float(m.start), Float(m.start + period * 0.5), Float(t))
            * (1 - smoothstep(Float(knit + period * 0.45), Float(knit + period * 1.2), Float(t)))
        whole.shadow *= 1 - away
        if tear < 0.002, abs(pull) < 0.002 { return [whole] }
        let k = threads(for: card)
        let h = card.size.y / Float(k)
        return Pieces.strips(whole, count: k).enumerated().map { b, strip in
            var piece = strip
            let r = hash(c * 131 + b, 61)
            let side: Float = b % 2 == 0 ? -1 : 1
            let dx = side * (0.05 + 0.12 * r) * card.size.x * pull * abs(pull)
            let dy = sinf(2 * .pi * Float(beat) * 0.5 + Float(b) * 0.9 + r * 6) * 0.3 * h * tear
            piece.position += turned(SIMD3(dx, dy, 0.003 * r * tear), by: card.rotation)
            piece.band = Pieces.thread(tear: tear, salt: hash(c * 53 + b, 67))
            piece.shadow = 0
            return piece
        }
    }

    /// A card leaving its cell for the drop's shape: drawn in with the grid
    /// over the breath before, out on the hit as the light reaches it, held
    /// while the shape moves with the music, home together on the downbeat.
    func reformed(_ card: CardPose, c: Int, _ m: DropMoment, place: Placement?, at t: Double, inhale: Float, grow: Float) -> CardPose {
        var card = card
        // Breathing in, the grid draws together; on the hit it lets go.
        let draw = t < m.time ? 0.06 * inhale : 0.06 * (1 - Ease.outCubic(Float((t - m.time) / 0.12)))
        if draw > 0.0001 {
            let centre = layout.safeCentre
            card.position.x = centre.x + (card.position.x - centre.x) * (1 - draw)
            card.position.y = centre.y + (card.position.y - centre.y) * (1 - draw)
            card.size *= 1 - draw / 2
        }
        guard t >= m.time, let place else { return card }
        let go = m.time + Double(c < dropOrder.count ? dropOrder[c] : 0) * plan.period / 2
        let a: Float = t < m.leave ? back(Float((t - go) / m.flyOut), 1.1) : 1 - Ease.place(Float((t - m.leave) / m.flyHome))
        guard abs(a) > 0.0005 else { return card }
        let a0 = min(max(a, 0), 1)
        card.position = mix3(card.position, place.position, a)
        card.position.z += 0.06 * sinf(.pi * a0)
        card.rotation = mix3(card.rotation, place.rotation, a)
        let own = SIMD2(place.width, place.width / max(card.mediaAspect, 0.05)) * grow
        card.size = SIMD2(max(mix(card.size.x, own.x, a), 0.001), max(mix(card.size.y, own.y, a), 0.001))
        let shade = mix(1, place.shade, a0)
        card.color = SIMD4(card.color.x * shade, card.color.y * shade, card.color.z * shade, card.color.w)
        card.opacity *= mix(1, place.opacity, a0)
        card.shadow *= mix(1, place.shadow, a0)
        card.blur += place.blur * a0
        card.corner = corner(for: card.size)
        card.layer = 2
        return card
    }

    /// The featured card as the camera moves in on it: opened to its slide's
    /// own shape inside its cell, lit, turned square on and lifted clear.
    func zoomed(_ card: CardPose, geometry: GridLayout.Cell, amount a: Float, kick: Float) -> CardPose {
        guard a > 0.0005 else { return card }
        var card = card
        let s = settings
        let aspect = max(card.mediaAspect, 0.05)
        let box = geometry.size
        let own = aspect > box.x / max(box.y, 1e-5) ? SIMD2(box.x, box.x / aspect) : SIMD2(box.y * aspect, box.y)
        let grow = 1 + 0.015 * kick * a
        card.size = SIMD2(mix(card.size.x, own.x * grow, a), mix(card.size.y, own.y * grow, a))
        card.position = mix3(card.position, layout.place(SIMD3(geometry.centre.x, geometry.centre.y, 0)) + SIMD3(0, 0, 0.02), a)
        card.rotation *= 1 - a
        let lit = max(s.lit.brightness, 1)
        let target = SIMD4<Float>(lit * lit, lit * lit, lit * lit, 1)
        card.color += (target - card.color) * a
        card.saturation = mix(card.saturation, max(s.lit.colour, 1), a)
        card.glow = mix(card.glow, s.lit.glow * 0.3, a)
        card.blur *= 1 - a
        card.opacity = mix(card.opacity, 1, a)
        card.shadow = mix(card.shadow, max(s.lit.shadow, 1) * 1.4, a)
        card.corner = corner(for: card.size)
        card.layer = 10
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

    /// The card on its way in or out at `t`, in pieces for some entrances;
    /// empty while it is off stage.
    func entrance(_ card: CardPose, c: Int, geometry: GridLayout.Cell, at t: Double, reverse: Bool, kick: Float,
                  ctx: SceneContext, real: Double) -> [CardPose] {
        let intro = plan.intro
        let outro = plan.outro
        let isCover = c == intro.coverCell
        var card = card
        if !reverse {
            switch outro.kind {
            case .close:
                // Leaving in reverse, the cover rising to hold the end.
                if isCover, real > outro.coverRise {
                    let p = Float(min(1, (real - outro.coverRise) / outro.flight))
                    return [coverHero(card, geometry: geometry, amount: Ease.place(p), kick: kick, push: Float((real - outro.coverRise) / 3), ctx: ctx)]
                }
                let leave = outro.leaves[c]
                if real >= leave {
                    let p = Float((real - leave) / outro.flight)
                    if p >= 1 { return [] }
                    return flight(card, c: c, geometry: geometry, progress: 1 - p, ctx: ctx)
                }
            case .leave:
                // Emptying the way it filled; with a cold open the cover rises to meet frame 0.
                if isCover, outro.coverHolds, real > outro.coverRise {
                    let p = Float(min(1, (real - outro.coverRise) / max(outro.flight, 0.1)))
                    return [coverHero(card, geometry: geometry, amount: Ease.place(p), kick: 0, push: 0, ctx: ctx)]
                }
                let leave = outro.leaves[c]
                if real >= leave - 0.15 { return departure(card, c: c, geometry: geometry, since: real - leave, flight: outro.flights[c]) }
            case .curtainCall:
                if isCover {
                    // The cover steps forward, takes the last bow on the final downbeat, and holds.
                    if real > outro.coverRise {
                        let rise = min(plan.period * 3, 1.4)
                        let p = Float(min(1, (real - outro.coverRise) / rise))
                        let hero = coverHero(card, geometry: geometry, amount: Ease.place(p), kick: kick * (1 - p), push: 0, ctx: ctx)
                        return [bowed(hero, c: c, since: real - outro.end, depth: 1)]
                    }
                } else {
                    card = bowed(card, c: c, since: real - outro.bows[c], depth: 0.8)
                    let leave = outro.leaves[c]
                    if real >= leave - 0.12 { return curtainExit(card, c: c, since: real - leave, flight: outro.flights[c]) }
                }
            case .driftAway:
                if isCover {
                    // The cover rises to the middle and stays, glowing faintly and growing over the last bar.
                    if real > outro.coverRise {
                        let p = Float(min(1, (real - outro.coverRise) / 1.6))
                        var hero = coverHero(card, geometry: geometry, amount: Ease.inOutCubic(p), kick: kick * (1 - p), push: 0, ctx: ctx)
                        let grow = Ease.smooth(Float((real - (plan.length - plan.period * 4)) / (plan.period * 4)))
                        hero.size *= 1 + 0.03 * grow
                        hero.glow += 0.03 + 0.09 * grow
                        hero.corner = corner(for: hero.size)
                        return [hero]
                    }
                } else if real >= outro.leaves[c] {
                    return drift(card, c: c, since: real - outro.leaves[c], flight: outro.flights[c])
                }
            default:
                break
            }
        }
        if intro.coldOpen, isCover, t < intro.end {
            // Frame 0 is the cover, large and lit; it goes back to its cell as the grid arrives.
            let p: Float = t < intro.coverMove ? 0 : Float((t - intro.coverMove) / max(intro.end - intro.coverMove, 1e-3))
            return [coverHero(card, geometry: geometry, amount: 1 - Ease.place(p), kick: kick, push: Float(t / max(intro.coverMove, 0.3)), ctx: ctx)]
        }
        let land = intro.landings[c]
        // By sound: a kick slide lands with a squash, a hat slide with a glint.
        if settings.intro.entrance == .voices, t >= land, t - land < 0.2, !(intro.coldOpen && isCover) {
            card = landed(card, c: c, since: Float(t - land))
        }
        if t >= intro.end { return [card] }
        let flightTime = c < intro.flights.count ? intro.flights[c] : intro.flight
        let begin = land - flightTime
        if t < begin { return [] }
        if t >= land { return [card] }
        return flight(card, c: c, geometry: geometry, progress: Float((t - begin) / flightTime), ctx: ctx)
    }

    /// The moment after a slide comes in by sound: a kick slide squashes 6 % and recovers in a
    /// tenth of a second; a hat slide catches a glint.
    func landed(_ card: CardPose, c: Int, since x: Float) -> CardPose {
        var card = card
        switch plan.intro.voices[c] {
        case .low:
            let k = 0.06 * (1 - Ease.smooth(x / 0.1))
            let h = card.size.y
            card.size.y *= 1 - k
            card.size.x *= 1 + k * 0.5
            card.position.y -= h * k * 0.5
        case .high:
            card.glow += 0.45 * expf(-x / 0.08)
        case .mid:
            break
        }
        return card
    }

    /// A card leaving on its beat the way its sound does: a kick slide gathers a little, then
    /// drops away with a turn that lags behind; a snare slide flicks out sideways; a hat slide
    /// pops off, shrinking with a glint. `since` is the time since its beat; before it, it gathers.
    func departure(_ card: CardPose, c: Int, geometry: GridLayout.Cell, since x: Double, flight: Double) -> [CardPose] {
        var card = card
        let voice = plan.intro.voices[c]
        let vary = 1 + 0.3 * min(max(settings.motion.feel, 0), 1) * (hash(c, 91) * 2 - 1)
        let side: Float = geometry.centre.x >= 0 ? 1 : -1
        card.layer = 2 + Float(plan.outro.rank[c]) * 0.001
        if x < 0 {
            // Anticipation, over the moment before the beat.
            let a = Ease.smooth(Float((x + 0.15) / 0.15))
            switch voice {
            case .low:
                card.position.y += 0.008 * a
                card.position.z += 0.01 * a
            case .mid:
                card.position.x -= side * 0.008 * a
                card.rotation.z += side * 0.03 * a
            case .high:
                card.size *= 1 + 0.04 * a
            }
            return [card]
        }
        let p = Float(x / max(flight, 0.05))
        if p >= 1 { return [] }
        switch voice {
        case .low:
            // A fall that gathers speed; the turn lags behind it.
            let e = p * p
            let lag = max(0, p - 0.2) / 0.8
            card.position.y += 0.008 * (1 - Ease.outCubic(p * 4)) - e * (card.position.y + 0.5 + card.size.y)
            card.position.z -= e * 0.08
            card.rotation.x += lag * lag * 0.8 * vary
            card.rotation.z += side * lag * lag * 0.3 * vary
            card.opacity *= 1 - Ease.smooth((p - 0.7) / 0.3)
        case .mid:
            let e = powf(p, 2.2)
            card.position.x += side * e * (geometry.size.x * 2.5 + 0.15)
            card.rotation.z -= side * e * 0.35 * vary
            card.rotation.y += side * e * 0.5
            card.opacity *= 1 - Ease.smooth((p - 0.55) / 0.45)
        case .high:
            let k: Float = p < 0.25 ? 1 + 0.12 * Ease.outCubic(p / 0.25) : 1.12 * (1 - powf((p - 0.25) / 0.75, 2))
            card.size *= max(k, 0.001)
            card.glow += 0.6 * sinf(.pi * min(p * 1.5, 1))
            card.opacity *= 1 - Ease.smooth((p - 0.75) / 0.25)
        }
        card.shadow *= 1 - p
        card.corner = corner(for: card.size)
        return [card]
    }

    /// A bow: a small rise, a forward tip peaking on the beat, and back up with a
    /// little overshoot, exactly square again half a second later.
    func bowed(_ card: CardPose, c: Int, since x: Double, depth: Float) -> CardPose {
        guard x > -0.45, x < 0.5 else { return card }
        var card = card
        let vary = 1 + 0.3 * min(max(settings.motion.feel, 0), 1) * (hash(c, 93) * 2 - 1)
        let rise = x < -0.2 ? Ease.smooth(Float((x + 0.45) / 0.25)) : 1 - Ease.smooth(Float((x + 0.2) / 0.4))
        let tip: Float = x < 0 ? Ease.inOutCubic(Float((x + 0.3) / 0.3)) : 1 - back(Float(x / 0.5), 1.2)
        let d = depth * vary
        card.position.z += 0.012 * rise * d
        card.position.y += 0.005 * rise * d - 0.012 * tip * d
        card.rotation.x += 0.38 * tip * d
        card.glow += 0.12 * max(tip, 0) * d
        return card
    }

    /// A card leaving downwards in a curtain call, gathering speed, tipping back as it goes.
    func curtainExit(_ card: CardPose, c: Int, since x: Double, flight: Double) -> [CardPose] {
        var card = card
        card.layer = 2 + Float(plan.outro.rank[c]) * 0.001
        if x < 0 {
            card.position.y += 0.006 * Ease.smooth(Float((x + 0.12) / 0.12))
            return [card]
        }
        let p = Float(x / max(flight, 0.05))
        if p >= 1 { return [] }
        let e = p * p
        card.position.y += 0.006 * (1 - Ease.outCubic(p * 4)) - e * (card.position.y + 0.5 + card.size.y)
        card.rotation.x -= e * 0.45
        card.rotation.z += (hash(c, 95) * 2 - 1) * 0.25 * e
        card.opacity *= 1 - Ease.smooth((p - 0.75) / 0.25)
        card.shadow *= 1 - p
        return [card]
    }

    /// A card lifting away like paper in a draught: rising and leaning out on a slow sway,
    /// turning gently, receding and softening until it is gone.
    func drift(_ card: CardPose, c: Int, since x: Double, flight: Double) -> [CardPose] {
        var card = card
        card.layer = 2 + Float(plan.outro.rank[c]) * 0.001
        let p = Float(x / max(flight, 0.05))
        if p >= 1 { return [] }
        let up = Ease.inOutCubic(p)
        let dir: Float = card.position.x >= layout.safeCentre.x ? 1 : -1
        let sway = sinf(2 * .pi * p * 1.2 + hash(c, 101) * 2 * .pi) - sinf(hash(c, 101) * 2 * .pi)
        card.position.y += up * 0.32
        card.position.x += dir * up * 0.1 + sway * 0.025 * Ease.smooth(p * 3)
        card.position.z -= up * 0.3
        card.rotation.z += sway * 0.1 * Ease.smooth(p * 3) + dir * up * 0.2
        card.rotation.y += dir * up * 0.35
        card.blur += up * 10
        card.opacity *= 1 - Ease.smooth((p - 0.3) / 0.7)
        card.shadow *= 1 - up
        let soft = 1 - 0.3 * up
        card.color = SIMD4(card.color.x * soft, card.color.y * soft, card.color.z * soft, card.color.w)
        return [card]
    }

    /// The cover between its cell (0) and held up large (1).
    func coverHero(_ card: CardPose, geometry: GridLayout.Cell, amount: Float, kick: Float, push: Float, ctx: SceneContext) -> CardPose {
        var card = card
        let aspect = card.mediaAspect
        // Sized as the camera sees it, a little in front of the grid.
        let k = Self.seen(0.06)
        let big = layout.heroSize(aspect: aspect) / k
        let centre = SIMD3(layout.featureCentre.x / k, layout.featureCentre.y / k, Float(0.06))
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

    /// A card in flight to its cell, 0 off stage, 1 landed: whole, or in the
    /// slats, threads or page some entrances cut it into.
    func flight(_ card: CardPose, c: Int, geometry: GridLayout.Cell, progress p: Float, ctx: SceneContext) -> [CardPose] {
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
        case .blinds:
            // Slats turn face on one after another, top to bottom.
            let k = Pieces.slats(card)
            let lag = 0.45 / Float(k)
            return Pieces.strips(card, count: k).enumerated().map { i, strip in
                var slat = strip
                let q = min(max((p - Float(i) * lag) / (1 - Float(k - 1) * lag), 0), 1)
                slat.rotation.x += (1 - back(q, 0.9)) * .pi / 2
                slat.opacity *= min(1, q / 0.15)
                return slat
            }
        case .page:
            // Laid down from its left edge, bending as paper does on the way.
            var page = Pieces.hinged(card, angle: -(1 - back(p, 0.5)) * .pi / 2)
            page.flex = 0.55
            page.curl = 0.5 * sinf(.pi * p) * (1 - p)
            page.opacity *= min(1, p / 0.12)
            return [page]
        case .voices:
            // Each comes in the way its sound does, landing exactly on its slot.
            let feel = min(max(settings.motion.feel, 0), 1)
            let vary = 1 + 0.3 * feel * (hash(c, 97) * 2 - 1)
            switch plan.intro.voices[c] {
            case .low:
                // Falls in from just above and in front, gathering speed; its shadow firms as it nears.
                let e = p * p
                card.position.y += (1 - e) * 0.16 * vary
                card.position.z += (1 - e) * 0.12
                card.position.x += sinf(.pi * p) * 0.02 * feel * side
                card.rotation.x += (1 - e) * 0.15 * vary
                card.shadow *= 0.4 + 0.6 * e
                fade(0.12)
            case .mid:
                // Snaps in from the side its cell is nearer, turning a little, with a 10 % overshoot.
                let toward: Float = geometry.centre.x >= 0 ? 1 : -1
                let e = back(p, 1.7 * vary)
                card.position.x += toward * (1 - e) * (geometry.size.x * 1.5 + 0.02)
                card.position.y += sinf(.pi * p) * 0.015 * feel
                card.rotation.z += toward * (1 - e) * 7 * .pi / 180 * vary
                fade(0.15)
            case .high:
                // Pops up from 40 % with a quick overshoot.
                let e = back(p, 2.2 * vary)
                card.size *= max(0.4 + 0.6 * e, 0.05)
                card.position.z += (1 - Ease.outCubic(p)) * 0.02
                card.glow += 0.3 * (1 - p)
                fade(0.1)
            }
        case .weave:
            // Threads slide in from either side and knit together.
            let k = threads(for: card)
            return Pieces.strips(card, count: k).enumerated().map { b, strip in
                var piece = strip
                let r = hash(c * 131 + b, 71)
                let q = min(max((p - r * 0.25) / 0.75, 0), 1)
                let side: Float = b % 2 == 0 ? -1 : 1
                piece.position += turned(SIMD3(side * (1 - back(q, 1.0)) * card.size.x * (0.7 + 0.5 * r), 0, 0), by: card.rotation)
                piece.band = Pieces.thread(tear: 1 - Ease.smooth(q * 1.15), salt: hash(c * 53 + b, 73))
                piece.opacity *= min(1, q / 0.2)
                piece.shadow = 0
                return piece
            }
        }
        return [card]
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

    /// A slide out front. `presented` is its cell's card as the grid shows it
    /// now (lit or resting, leaning, opened): it starts from exactly that.
    func hero(slide: Int, from cell: Int?, presented: CardPose? = nil, progress p: HeroProgress, kick: Float, ctx: SceneContext,
              occurrence: Int) -> CardPose {
        let aspect = ctx.items[slide].aspect
        let s = settings
        let spot = s.spotlight
        let big = layout.heroSize(aspect: aspect)
        let geometry = cell.map { layout.cells[$0] }
        let home = presented?.position ?? geometry.map { layout.place(SIMD3($0.centre.x, $0.centre.y, 0)) } ?? layout.place(.zero)
        let homeSize = presented?.size ?? (geometry?.size ?? big * 0.3) * s.rest.scale
        // Worked out as the camera sees it, so lifting it towards the lens never
        // makes it bigger than planned: from its cell to the middle of the feature box,
        // centred across and kept inside it.
        let homeSeen = SIMD2(home.x, home.y) * Self.seen(home.z), homeSizeSeen = homeSize * Self.seen(home.z)
        var y = mix(homeSeen.y, layout.featureCentre.y, spot ? 0.85 : 0.6)
        let room = max(layout.featureSize.y / 2 - big.y / 2, 0)
        y = min(max(y, layout.featureCentre.y - room), layout.featureCentre.y + room)
        let seen = homeSeen + (SIMD2(layout.featureCentre.x, y) - homeSeen) * p.position
        let z = mix(home.z, 0.25, p.lift)
        let k = Self.seen(z)
        let grow = 1 + 0.015 * kick * p.amount
        let size = (homeSizeSeen + (big - homeSizeSeen) * p.position) * grow / k
        var card = CardPose(media: slide, occurrence: occurrence, position: SIMD3(seen.x / k, seen.y / k, z),
                            rotation: (presented?.rotation ?? layout.wallRotation) * (1 - p.amount),
                            size: SIMD2(max(size.x, 0.001), max(size.y, 0.001)))
        card.mediaAspect = aspect
        card.fit = .fill
        card.focal = focal(slide)
        let b = max(s.lit.brightness, 1)
        let from = presented?.color ?? SIMD4(SIMD3(repeating: powf(s.rest.brightness, 2)), 1)
        card.color = from + (SIMD4(b * b, b * b, b * b, 1) - from) * p.amount
        card.saturation = mix(presented?.saturation ?? s.rest.colour, max(s.lit.colour, 1), p.amount)
        card.glow = mix(presented?.glow ?? 0, s.lit.glow * 0.4, p.amount)
        card.shadow = mix(presented?.shadow ?? s.rest.shadow, max(s.lit.shadow, 1) * 2, p.amount)
        card.blur = (presented?.blur ?? 0) * (1 - p.amount)
        card.opacity = geometry == nil ? min(1, p.amount * 1.5) : mix(presented?.opacity ?? 1, 1, p.amount)
        card.corner = corner(for: card.size)
        card.layer = 10
        return card
    }

    // MARK: Helpers

    /// How much larger the resting camera shows something `z` in front of the
    /// canvas than the same thing on it.
    static func seen(_ z: Float) -> Float {
        let d = GridLayout.eyeDistance
        return d / max(d - z, 0.2)
    }

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
