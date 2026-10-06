import BeatKit
import Foundation
import StageKit

/// What `beat-lab check` proves on the CPU: the demo song is heard right, the
/// grid fits the deck, every plan keeps its promises, and no frame of any
/// scene draws a broken card.
enum Checks {
    /// Runs every check, prints a line for each, and returns how many failed.
    static func run() -> Int {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String) {
            print("\(ok ? "ok  " : "FAIL") \(name): \(detail())")
            if !ok { failures += 1 }
        }

        // The demo groove: 120 BPM, its drop on bar 9 at 16 seconds.
        let stereo = DemoGroove.render()
        var mono = [Float](repeating: 0, count: stereo.count / 2)
        for i in mono.indices { mono[i] = 0.5 * (stereo[2 * i] + stereo[2 * i + 1]) }
        let a = SongAnalyzer.analyze(mono: mono, sampleRate: Double(DemoGroove.sampleRate))
        let dropAt = Double(DemoGroove.dropBar) * 4 * 60 / DemoGroove.bpm
        check("tempo", abs(a.tempo - DemoGroove.bpm) < 1.5, String(format: "%.2f BPM, confidence %.2f", a.tempo, a.confidence))
        check("drop", a.drops.contains { abs($0 - dropAt) < 0.3 }, "heard at \(a.drops.map { String(format: "%.2f", $0) }), expected \(dropAt)")
        let downs = a.beats.filter(\.isDownbeat).map(\.time)
        check("downbeats", downs.contains { abs($0 - dropAt) < 0.06 }, "\(downs.count) bars, one on the drop")

        // The grid: fit to the deck, cells within the safe area.
        let tall: Float = 1080.0 / 1920.0
        let fit15 = GridLayout.fit(count: 15, aspect: tall, slideAspect: 16.0 / 9.0, base: GridSettings())
        check("fit 15", fit15.columns * fit15.rows >= 15 && fit15.columns * fit15.rows - 15 < fit15.columns,
              "\(fit15.columns)×\(fit15.rows) \(fit15.shape.rawValue)")
        for n in [8, 24, 30, 60] {
            let f = GridLayout.fit(count: n, aspect: tall, slideAspect: 16.0 / 9.0, base: GridSettings())
            check("fit \(n)", f.columns * f.rows >= n && f.columns * f.rows - n < f.columns, "\(f.columns)×\(f.rows) \(f.shape.rawValue)")
        }
        let grid = GridLayout(settings: GridSettings(), aspect: tall, slideAspect: 16.0 / 9.0)
        // Cell centres are measured from the middle of the safe area.
        let inside = grid.cells.allSatisfy { c in
            abs(c.centre.x) + c.size.x / 2 <= grid.safeSize.x / 2 + 1e-4 && abs(c.centre.y) + c.size.y / 2 <= grid.safeSize.y / 2 + 1e-4
        }
        check("safe area", inside, "\(grid.columns)×\(grid.rows), cells \(Int(grid.cells[0].size.x * 1920))×\(Int(grid.cells[0].size.y * 1920)) px")

        // Every mode, ending, entrance and deck size: the plan's timing holds
        // and no frame draws a card that is not finite, sized and real.
        var badPoses = 0, badPlans = 0, configs = 0
        for mode in BeatMode.allCases {
            for outro in [Outro.loop, .close, .lightsOut, .none] {
                for entrance in Entrance.allCases {
                    for cold in [true, false] {
                        for slides in [8, 15, 30] {
                            var s = BeatSettings()
                            s.mode = mode
                            s.outro = outro
                            s.intro.entrance = entrance
                            s.intro.coldOpen = cold
                            if slides == 30 {
                                s.grid.wall = .angle
                                s.spotlight = true
                                s.feature = .twoBars
                                s.lit.tint = 0.2
                                s.lit.tintColour = "#FFB46B"
                            }
                            let layout = GridLayout(settings: s.grid, aspect: tall, slideAspect: 16.0 / 9.0)
                            let plan = Choreographer.plan(a, settings: s, layout: layout, slides: slides, clipStart: 0, clipLength: 30)
                            configs += 1
                            let landed = plan.intro.landings.allSatisfy { $0 >= -1e-6 && $0 <= plan.intro.end + 1e-6 }
                            let ends = plan.outro.start <= plan.length + 1e-6 && plan.outro.end <= plan.length + 1e-6
                                && plan.intro.end < plan.outro.start
                            if !landed || !ends {
                                badPlans += 1
                                if badPlans <= 3 {
                                    print("     plan \(mode) \(outro) \(entrance) cold \(cold) \(slides): intro \(plan.intro.end) outro \(plan.outro.start)…\(plan.outro.end) of \(plan.length)")
                                }
                            }
                            let scene = BeatScene(plan: plan, layout: layout, settings: s)
                            let ctx = context(slides, aspect: tall)
                            var t = 0.0
                            while t <= 30 {
                                for c in scene.frame(at: t, ctx).cards where !sound(c, slides: slides) {
                                    badPoses += 1
                                    if badPoses <= 3 { print("     pose \(mode) \(outro) \(entrance) t \(t): \(c.position) \(c.size) \(c.opacity)") }
                                }
                                t += 1.0 / 15
                            }
                        }
                    }
                }
            }
        }
        check("plans", badPlans == 0, "\(configs - badPlans) of \(configs) keep their timing")
        check("poses", badPoses == 0, "\(badPoses) broken cards across \(configs) clips at 15 fps")

        // The intro: the slides land one per slot, a whole fraction of a beat
        // apart, and the cover last, on the downbeat where the music takes over.
        var s = BeatSettings()
        s.outro = .loop
        let plan = Choreographer.plan(a, settings: s, layout: grid, slides: 15, clipStart: 0, clipLength: 30)
        let landings = plan.intro.landings.sorted()
        let gaps = zip(landings.dropFirst(), landings).map { $0 - $1 }
        let q = gaps.first ?? 0
        let even = gaps.allSatisfy { abs($0 - q) < 0.005 }
        let fraction = [2.0, 3, 4, 6, 8].contains { abs(q - plan.period / $0) < 0.005 }
        let coverLast = abs(plan.intro.landings[plan.intro.coverCell] - (landings.last ?? 0)) < 1e-6
        check("landings", even && fraction && coverLast && abs((landings.last ?? 0) - plan.intro.end) < 0.01,
              String(format: "%d slides %.3f s (1/%.0f beat) apart, cover lands at %.2f s", landings.count, q, plan.period / max(q, 1e-6),
                     landings.last ?? 0))

        // Restraint: between the intro and the ending, away from the drops,
        // no more than 40% of the grid is past half lit. Equaliser is exempt.
        for mode in BeatMode.allCases where mode != .equaliser {
            var m = BeatSettings()
            m.mode = mode
            m.outro = .loop
            let p = Choreographer.plan(a, settings: m, layout: grid, slides: 15, clipStart: 0, clipLength: 30)
            var sum: Float = 0, frames = 0, peak: Float = 0
            let featured = p.features.map { ($0.liftOff, $0.end) }
            var t = p.intro.end + p.period
            while t < p.outro.start {
                if !p.drops.contains(where: { t > $0 - p.period && t < $0 + 4 * p.period }), !featured.contains(where: { t >= $0.0 && t <= $0.1 }) {
                    var lit = 0
                    for c in 0..<p.cells where p.light(cell: c, at: t).level > 0.5 { lit += 1 }
                    let fraction = Float(lit) / Float(p.cells)
                    sum += fraction
                    peak = max(peak, fraction)
                    frames += 1
                }
                t += 1.0 / 30
            }
            let mean = sum / Float(max(frames, 1))
            let cap = Float(max(1, Int(Float(p.cells) * 0.4))) / Float(p.cells)
            check("restraint \(mode.rawValue)", peak <= cap + 1e-4, String(format: "mean %.2f, peak %.2f of the grid lit", mean, peak))
        }

        // A loop's last frame meets its first: the cards are where they started.
        let scene = BeatScene(plan: plan, layout: grid, settings: s)
        let ctx = context(15, aspect: tall)
        let first = scene.frame(at: 0, ctx), last = scene.frame(at: plan.length - 1.0 / 240, ctx)
        var seam: Float = 0
        for c in first.cards {
            guard let d = last.cards.first(where: { $0.occurrence == c.occurrence }) else { seam = .infinity; break }
            let move = c.position - d.position
            seam = max(seam, (move * move).sum().squareRoot(), abs(c.size.x - d.size.x), abs(c.opacity - d.opacity), abs(c.color.x - d.color.x))
        }
        check("loop seam", seam < 0.02 && first.cards.count == last.cards.count,
              String(format: "%d cards, largest change %.4f", first.cards.count, seam))

        // Read-through meets every slide; a deck larger than the grid is seen by halfway.
        var big = BeatSettings()
        big.grid.columns = 4
        big.grid.rows = 8
        let g2 = GridLayout(settings: big.grid, aspect: tall, slideAspect: 16.0 / 9.0)
        let p2 = Choreographer.plan(a, settings: big, layout: g2, slides: 40, clipStart: 0, clipLength: 30)
        var seen = Set(p2.firstSlide)
        for c in 0..<p2.cells { for w in p2.swaps[c] where w.time < 15 { seen.insert(w.slide) } }
        check("deck rotation", seen.count == 40, "\(seen.count) of 40 slides seen by 15 s on 4×8")

        // v2 ---------------------------------------------------------------

        // A slide stepping out of the grid stays inside the frame, as the camera
        // sees it: lifted towards the lens, on the kick, through the camera's
        // punch, whatever the slide's shape, the canvas, the wall or the spotlight.
        var worst: Float = -1, worstAt = "", heroFrames = 0
        let wide: Float = 2576.0 / 1080.0
        let canvases: [Float] = [tall, 1, 16.0 / 9.0], shapes: [Float] = [wide, 16.0 / 9.0, 4.0 / 3.0, 1, 0.75]
        for canvas in canvases {
            for slideAspect in shapes {
                for variant in 0..<4 {
                    var h = BeatSettings()
                    h.feature = .twoBars
                    h.spotlight = variant % 2 == 1
                    h.atmosphere = variant >= 2 ? 1 : 0.5
                    if variant == 3 { h.grid.wall = .angle }
                    let layout = GridLayout(settings: h.grid, aspect: canvas, slideAspect: slideAspect)
                    let p = Choreographer.plan(a, settings: h, layout: layout, slides: 15, clipStart: 0, clipLength: 30)
                    let scene = BeatScene(plan: p, layout: layout, settings: h)
                    let ctx = SceneContext(items: (0..<15).map { SceneItem(media: $0, occurrence: $0, aspect: slideAspect) }, aspect: canvas,
                                           dials: SceneDials())
                    var times: [Double] = stride(from: 0, to: p.intro.end, by: 1.0 / 30).map { $0 }
                    for f in p.features { times += stride(from: f.liftOff, through: f.end, by: 1.0 / 30).map { $0 } }
                    for t in times {
                        let frame = scene.frame(at: t, ctx)
                        let eye = GridLayout.eyeDistance + frame.camera.offset.z
                        for c in frame.cards where c.layer >= 3 && abs(c.rotation.x) + abs(c.rotation.y) + abs(c.rotation.z) < 0.02 {
                            let k = GridLayout.eyeDistance / (eye - c.position.z)
                            let overX = abs(c.position.x * k) + c.size.x * k / 2 - canvas / 2
                            let overY = abs(c.position.y * k) + c.size.y * k / 2 - 0.5
                            let over = max(overX, overY)
                            heroFrames += 1
                            if over > worst {
                                worst = over
                                worstAt = String(format: "canvas %.2f, slide %.2f, variant %d, t %.2f", canvas, slideAspect, variant, t)
                            }
                        }
                    }
                }
            }
        }
        // At least 1 % of the frame's height clear of every edge.
        check("hero fits", worst <= -0.01, String(format: "%d frames out front; at most %.3f from the edge (%@)", heroFrames, worst, worstAt as NSString))

        // A featured slide comes back to the card it left, and no other card
        // shows it meanwhile, even while cells turn over to show a big deck
        // (starred slides off the first grid step forward early and often).
        var homeless = 0, twins = 0, homed = 0
        for mode in BeatMode.allCases {
            var m = BeatSettings()
            m.mode = mode
            m.feature = .oneBar
            let p = Choreographer.plan(a, settings: m, layout: grid, slides: 40, clipStart: 0, clipLength: 34, starred: [18, 23, 31, 37])
            for f in p.features {
                for t in stride(from: f.liftOff, through: f.end, by: 0.05) {
                    if let c = f.cell {
                        let (slide, turn) = p.slide(cell: c, at: t)
                        if slide != f.slide || turn != 0 { homeless += 1 }
                    }
                    for c in 0..<p.cells where c != f.cell && p.slide(cell: c, at: t).slide == f.slide { twins += 1 }
                }
                if f.cell != nil { homed += 1 }
            }
        }
        check("comes home", homeless == 0 && twins == 0,
              "\(homed) features from the grid; \(homeless) moments away from home, \(twins) moments shown twice")

        // Projects from another version open: missing settings take their
        // defaults, unreadable ones are skipped, and nothing else is lost.
        let decoder = JSONDecoder()
        let empty = try? decoder.decode(BeatSettings.self, from: Data("{}".utf8))
        let partial = try? decoder.decode(BeatSettings.self, from: Data(#"{"mode":"strobe","sensitivity":0.9,"grid":{"columns":4,"shape":"hex"},"future":1}"#.utf8))
        var changed = BeatSettings()
        changed.mode = .ripple
        changed.lit.tint = 0.3
        changed.grid.wall = .angle
        changed.intro.entrance = .unfold
        let again = (try? JSONEncoder().encode(changed)).flatMap { try? decoder.decode(BeatSettings.self, from: $0) }
        let fix = try? decoder.decode(BeatFix.self, from: Data("{}".utf8))
        check("old projects", empty == BeatSettings() && partial?.mode == .pulse && partial?.sensitivity == 0.9 && partial?.grid.columns == 4
              && partial?.grid.rows == 5 && partial?.grid.shape == .auto && again == changed && fix == BeatFix.none,
              "empty, partial and future settings read; a round trip keeps every value")

        // Decks made for wide screens: 2576 × 1080 and 1920 × 1080 slides in a
        // 1080 × 1920 frame. The fitted grid holds the deck with less than a row
        // spare, inside the safe area, cropping at most a third of a slide.
        var fits: [String] = [], badFits = 0
        for (name, shape) in [("2576", wide), ("1920", Float(16.0 / 9.0))] {
            for n in [6, 10, 12, 15, 18, 20, 24, 27, 30, 36, 40, 60] {
                let g = GridSettings().fitted(count: n, aspect: tall, slideAspect: shape)
                let l = GridLayout(settings: g, aspect: tall, slideAspect: shape)
                let inside = l.cells.allSatisfy { c in
                    abs(c.centre.x) + c.size.x / 2 <= l.safeSize.x / 2 + 1e-4 && abs(c.centre.y) + c.size.y / 2 <= l.safeSize.y / 2 + 1e-4
                }
                if l.count < n || l.count - n >= l.columns || l.crop > 0.35 || !inside { badFits += 1 }
                if [15, 30].contains(n) {
                    fits.append("\(name)×1080 \(n): \(l.columns)×\(l.rows) \(l.shape.rawValue) \(Int(l.cells[0].size.x / l.px))×\(Int(l.cells[0].size.y / l.px)) px")
                }
            }
        }
        let auto15 = GridLayout(settings: GridSettings(), aspect: tall, slideAspect: wide)
        check("wide decks", badFits == 0 && auto15.crop == 0, fits.joined(separator: "; ") + "; default 3×5 keeps 2576 slides whole")

        // A lit slide opening to its own shape in a filled cell grows at most
        // half as wide again, so a very wide slide never sprawls over its row.
        var r = BeatSettings()
        r.mode = .readThrough
        r.lit = CellState(scale: 1.1, brightness: 1, colour: 1, lift: 0.06, glow: 0.15, tilt: 2, shadow: 1.3, open: 1)
        r.motion.bounce = 0.12
        r.grid.shape = .fill
        let rl = GridLayout(settings: r.grid, aspect: tall, slideAspect: wide)
        let rp = Choreographer.plan(a, settings: r, layout: rl, slides: 15, clipStart: 0, clipLength: 30)
        let rs = BeatScene(plan: rp, layout: rl, settings: r)
        let rctx = SceneContext(items: (0..<15).map { SceneItem(media: $0, occurrence: $0, aspect: wide) }, aspect: tall, dials: SceneDials())
        var widest: Float = 0
        for t in stride(from: rp.intro.end, to: rp.outro.start, by: 1.0 / 30) {
            for c in rs.frame(at: t, rctx).cards where c.layer < 3 { widest = max(widest, c.size.x / rl.cells[0].size.x) }
        }
        let allowed = 1.5 * r.lit.scale * (1 + r.motion.bounce)
        check("open wide", widest <= allowed + 0.01, String(format: "widest lit card %.2f× its cell (allowed %.2f×)", widest, allowed))

        // Fixing the beat: twice or half the tempo, bars starting a beat later,
        // the grid nudged; the plan still keeps its timing.
        let barOne = a.beats.first { $0.isDownbeat && $0.bar == 0 }?.time ?? 0
        let double = a.fixed(BeatFix(speed: .double)), half = a.fixed(BeatFix(speed: .half))
        let shifted = a.fixed(BeatFix(barShift: 1)), nudged = a.fixed(BeatFix(nudge: 0.05))
        let downAt = { (x: SongAnalysis) in x.beats.first { $0.isDownbeat && $0.bar == 0 }?.time ?? -1 }
        let beatOK = abs(double.tempo - 2 * a.tempo) < 0.01 && double.beats.count == 2 * a.beats.count - 1 && abs(downAt(double) - barOne) < 1e-6
            && abs(half.tempo - a.tempo / 2) < 0.01 && abs(downAt(half) - barOne) < 1e-6
            && abs(downAt(shifted) - (barOne + a.beatPeriod)) < a.beatPeriod * 0.2
            && zip(nudged.beats, a.beats).allSatisfy { abs($0.time - $1.time - 0.05) < 1e-9 }
        var planOK = true
        for x in [double, half, shifted, nudged] {
            let p = Choreographer.plan(x, settings: BeatSettings(), layout: grid, slides: 15, clipStart: 0, clipLength: 30)
            planOK = planOK && p.intro.end < p.outro.start && p.intro.landings.allSatisfy { $0 >= -1e-6 && $0 <= p.intro.end + 1e-6 }
        }
        check("beat fix", beatOK && planOK, String(format: "%.0f → %.0f and %.0f BPM; bar one %.2f → %.2f s; plans keep their timing",
                                                   a.tempo, double.tempo, half.tempo, barOne, downAt(shifted)))

        // A caption across the top: the grid keeps clear of it.
        let clear = Clearance(top: 0.25)
        let cl = GridLayout(settings: GridSettings(), aspect: tall, slideAspect: 16.0 / 9.0, clear: clear)
        let highest = cl.cells.map { cl.safeCentre.y + $0.centre.y + $0.size.y / 2 }.max() ?? 1
        check("caption room", highest <= 0.5 - 0.25 + 1e-4, String(format: "top of the grid %.0f px below the top of the frame",
                                                                   (0.5 - highest) * 1920))

        return failures
    }

    static func context(_ slides: Int, aspect: Float) -> SceneContext {
        SceneContext(items: (0..<slides).map { SceneItem(media: $0, occurrence: $0, aspect: $0 % 5 == 4 ? 4.0 / 3.0 : 16.0 / 9.0) },
                     aspect: aspect, dials: SceneDials())
    }

    static func sound(_ c: CardPose, slides: Int) -> Bool {
        let values = [c.position.x, c.position.y, c.position.z, c.rotation.x, c.rotation.y, c.rotation.z, c.size.x, c.size.y,
                      c.opacity, c.color.x, c.color.y, c.color.z, c.glow, c.blur, c.saturation, c.corner, c.shadow]
        return values.allSatisfy(\.isFinite) && c.size.x > 0 && c.size.y > 0 && c.media >= 0 && c.media < slides
            && c.opacity >= -1e-4 && c.opacity <= 1.0001
    }
}
