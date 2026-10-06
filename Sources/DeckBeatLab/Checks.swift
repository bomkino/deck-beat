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

        // v3 ---------------------------------------------------------------

        // Every drop move and turn, either feature style, on small and large
        // decks of wide slides: each drop does what was asked, no card breaks,
        // the pieces stay few enough to draw, and a loop closes on its first frame.
        var v3Bad = 0, v3Configs = 0, mostCards = 0, v3Seam: Float = 0, v3SeamAt = ""
        var movesMissed: [String] = []
        for (k, move) in DropMove.allCases.enumerated() {
            for turn in TurnStyle.allCases {
                for slides in [8, 15, 30] {
                    var m = BeatSettings()
                    m.dropMove = move
                    m.turn = turn
                    m.featureStyle = (k + slides) % 2 == 0 ? .zoom : .lift
                    m.feature = .twoBars
                    m.outro = .loop
                    m.mode = BeatMode.allCases[(k + slides) % BeatMode.allCases.count]
                    if slides == 30 {
                        m.grid.columns = 5
                        m.grid.rows = 6
                    }
                    let layout = GridLayout(settings: m.grid, aspect: tall, slideAspect: wide)
                    let p = Choreographer.plan(a, settings: m, layout: layout, slides: slides, clipStart: 0, clipLength: 30)
                    if move != .light, !p.moments.contains(where: { $0.move == move }) { movesMissed.append("\(move.rawValue) \(slides)") }
                    let scene = BeatScene(plan: p, layout: layout, settings: m)
                    let ctx = context(slides, aspect: tall)
                    v3Configs += 1
                    var t = 0.0
                    while t <= p.length {
                        let cards = scene.frame(at: t, ctx).cards
                        mostCards = max(mostCards, cards.count)
                        for c in cards where !sound(c, slides: slides) {
                            v3Bad += 1
                            if v3Bad <= 3 { print("     pose \(move) \(turn) \(slides) t \(t): \(c.position) \(c.size) \(c.opacity)") }
                        }
                        t += 1.0 / 15
                    }
                    let first = scene.frame(at: 0, ctx), last = scene.frame(at: p.length - 1.0 / 240, ctx)
                    var gap: Float = first.cards.count == last.cards.count ? 0 : .infinity
                    for c in first.cards {
                        guard let d = last.cards.first(where: { $0.occurrence == c.occurrence }) else { gap = .infinity; break }
                        let move = c.position - d.position
                        gap = max(gap, (move * move).sum().squareRoot(), abs(c.size.x - d.size.x), abs(c.opacity - d.opacity))
                    }
                    if gap > v3Seam {
                        v3Seam = gap
                        v3SeamAt = "\(move.rawValue) \(turn.rawValue) \(slides)"
                    }
                }
            }
        }
        check("drop moves", movesMissed.isEmpty, movesMissed.isEmpty
              ? "weave, tunnel, fan and strip each happen on the drop, on 8, 15 and 30 slides" : "fell back to light: " + movesMissed.joined(separator: ", "))
        check("v3 poses", v3Bad == 0 && mostCards <= 800,
              "\(v3Bad) broken cards across \(v3Configs) clips at 15 fps; at most \(mostCards) cards in a frame")
        check("v3 loop seam", v3Seam < 0.02, String(format: "largest change %.4f (%@)", v3Seam, v3SeamAt as NSString))

        // A zoom on a featured slide keeps it in the frame all the way, and
        // inside the feature box once it is there, for every slide and canvas shape.
        var zoomWorst: Float = -1, zoomSafe: Float = -1, zoomAt = "", zoomFrames = 0
        for canvas in canvases {
            for slideAspect in shapes {
                var z = BeatSettings()
                z.feature = .twoBars
                z.featureStyle = .zoom
                let layout = GridLayout(settings: z.grid, aspect: canvas, slideAspect: slideAspect)
                let p = Choreographer.plan(a, settings: z, layout: layout, slides: 15, clipStart: 0, clipLength: 30)
                let scene = BeatScene(plan: p, layout: layout, settings: z)
                let ctx = SceneContext(items: (0..<15).map { SceneItem(media: $0, occurrence: $0, aspect: slideAspect) }, aspect: canvas,
                                       dials: SceneDials())
                let safeLo = layout.featureCentre - layout.featureSize / 2, safeHi = layout.featureCentre + layout.featureSize / 2
                for f in p.features {
                    for t in stride(from: f.liftOff, through: f.end, by: 1.0 / 30) {
                        let frame = scene.frame(at: t, ctx)
                        let eye = SIMD3<Float>(0, 0, GridLayout.eyeDistance) + frame.camera.offset
                        for c in frame.cards where c.layer >= 10 {
                            let k = GridLayout.eyeDistance / (eye.z - c.position.z)
                            let centre = (SIMD2(c.position.x, c.position.y) - SIMD2(eye.x, eye.y)) * k
                            let half = c.size * k / 2
                            let over = max(abs(centre.x) + half.x - canvas / 2, abs(centre.y) + half.y - 0.5)
                            zoomFrames += 1
                            if over > zoomWorst {
                                zoomWorst = over
                                zoomAt = String(format: "canvas %.2f, slide %.2f, t %.2f", canvas, slideAspect, t)
                            }
                            if t >= f.land, t <= f.leave {
                                let lo = centre - half, hi = centre + half
                                zoomSafe = max(zoomSafe, safeLo.x - lo.x, safeLo.y - lo.y, hi.x - safeHi.x, hi.y - safeHi.y)
                            }
                        }
                    }
                }
            }
        }
        check("zoom fits", zoomFrames > 0 && zoomWorst <= -0.005 && zoomSafe <= 0.005,
              String(format: "%d frames zoomed; at most %.3f from the frame's edge (%@), %.3f past the feature box", zoomFrames, zoomWorst,
                     zoomAt as NSString, zoomSafe))

        // In a Reel with Safe margins, a slide held up to be read (stepped out,
        // zoomed in on, or the cover at the start) stays clear of the platform's
        // header, caption and button column, for wide and 16:9 decks.
        var clearWorst: Float = -1, clearAt = "", clearFrames = 0
        let ui = Margins.platform(aspect: tall)
        let clearHi = SIMD2<Float>(tall / 2 - ui.right * tall, 0.5 - ui.top), clearLo = SIMD2<Float>(-tall / 2, -0.5 + ui.bottom)
        for slideAspect in [wide, Float(16.0 / 9.0)] {
            for (style, spot) in [(FeatureStyle.lift, false), (.lift, true), (.zoom, false)] {
                var r = BeatSettings()
                r.feature = .twoBars
                r.featureStyle = style
                r.spotlight = spot
                r.intro.coldOpen = true
                let layout = GridLayout(settings: r.grid, aspect: tall, slideAspect: slideAspect)
                let p = Choreographer.plan(a, settings: r, layout: layout, slides: 15, clipStart: 0, clipLength: 30)
                let scene = BeatScene(plan: p, layout: layout, settings: r)
                let ctx = SceneContext(items: (0..<15).map { SceneItem(media: $0, occurrence: $0, aspect: slideAspect) }, aspect: tall,
                                       dials: SceneDials())
                var held: [(Double, Float)] = [(0, 3)]
                for f in p.features { held += stride(from: f.land, through: f.leave, by: 1.0 / 30).map { ($0, 10) } }
                for (t, layer) in held {
                    let frame = scene.frame(at: t, ctx)
                    let eye = SIMD3<Float>(0, 0, GridLayout.eyeDistance) + frame.camera.offset
                    for c in frame.cards where c.layer >= layer {
                        let k = GridLayout.eyeDistance / (eye.z - c.position.z)
                        let centre = (SIMD2(c.position.x, c.position.y) - SIMD2(eye.x, eye.y)) * k
                        let lo = centre - c.size * k / 2, hi = centre + c.size * k / 2
                        let over = max(hi.x - clearHi.x, hi.y - clearHi.y, clearLo.x - lo.x, clearLo.y - lo.y)
                        clearFrames += 1
                        if over > clearWorst {
                            clearWorst = over
                            clearAt = String(format: "slide %.2f, %@%@, t %.2f", slideAspect, style.rawValue as NSString, spot ? " spotlit" : "", t)
                        }
                    }
                }
            }
        }
        check("clear of the buttons", clearFrames > 0 && clearWorst <= 0,
              String(format: "%d frames held up in a Reel; closest %.0f px from the platform's interface (%@)", clearFrames, -clearWorst * 1920,
                     clearAt as NSString))

        // Words on the beat: one landing per group, in order, each on a beat or
        // half a beat; inside an opening or closing title's window with time to
        // read; and gone again on a loop's first and last frames.
        let headline = ReelTitle(text: "Brightside raises its Series A", kicker: "pitch.dog · 2026", placement: .centre, timing: .opening,
                                 beat: true)
        let groups = ReelTitle.groups(headline.text)
        var wordsBad: [String] = [], cueCount = 0
        for timing in ReelTitle.Timing.allCases {
            for outro in [Outro.loop, .close] {
                for length in [15.0, 30.0] {
                    var m = BeatSettings()
                    m.outro = outro
                    let p = Choreographer.plan(a, settings: m, layout: grid, slides: 15, clipStart: 0, clipLength: length)
                    var title = headline
                    title.timing = timing
                    let cues = WordTiming.cues(title, plan: p)
                    let name = "\(timing.rawValue) \(outro.rawValue) \(Int(length)) s"
                    cueCount += cues.count
                    guard cues.count == title.beatGroups else {
                        wordsBad.append("\(name): \(cues.count) cues")
                        continue
                    }
                    let halves = zip(p.beats, p.beats.dropFirst()).map { ($0 + $1) / 2 }
                    for (i, c) in cues.enumerated() {
                        let onBeat = (p.beats + halves).contains { abs($0 - c.land) < 1e-6 }
                        if !onBeat || (i > 0 && c.land <= cues[i - 1].land) { wordsBad.append(String(format: "%@: cue %d at %.3f", name as NSString, i, c.land)) }
                        if c.leave.isFinite, c.leave < c.land + 1 { wordsBad.append("\(name): cue \(i) leaves too soon") }
                    }
                    if let w = timing.window(loop: p.length), let first = cues.first, let last = cues.last {
                        if first.land - first.lead < w.start - 1e-6 || last.land > w.end - 0.3 { wordsBad.append("\(name): outside its window") }
                        if !cues.allSatisfy({ $0.presence(at: w.end - 0.01).alpha > 0.999 }) { wordsBad.append("\(name): not all shown") }
                    }
                    if timing == .throughout, p.outro.kind == .loop {
                        let seen = cues.map { max($0.presence(at: 0).alpha, $0.presence(at: p.length - 1.0 / 240).alpha) }.max() ?? 0
                        if seen > 0.001 { wordsBad.append("\(name): words at the seam") }
                    }
                }
            }
        }
        check("words on the beat", groups.count == 3 && wordsBad.isEmpty,
              wordsBad.isEmpty ? "\(cueCount) landings over 12 clips; groups: " + groups.map { "\($0.count)" }.joined(separator: ", ") + " characters"
                  : wordsBad.prefix(4).joined(separator: "; "))

        // Restraint holds round the new drops too: outside a drop's own moment,
        // no more than 40% of the grid is past half lit.
        var shapePeak: Float = 0, shapeCap: Float = 1
        for move in DropMove.allCases where move != .light {
            var m = BeatSettings()
            m.dropMove = move
            m.outro = .loop
            let p = Choreographer.plan(a, settings: m, layout: grid, slides: 15, clipStart: 0, clipLength: 30)
            var t = p.intro.end + p.period
            while t < p.outro.start {
                let busy = p.drops.contains(where: { t > $0 - p.period && t < $0 + 4 * p.period })
                    || p.moments.contains(where: { t >= $0.start && t <= $0.end + p.period })
                    || p.features.contains(where: { t >= $0.liftOff && t <= $0.end })
                if !busy {
                    var lit = 0
                    for c in 0..<p.cells where p.light(cell: c, at: t).level > 0.5 { lit += 1 }
                    shapePeak = max(shapePeak, Float(lit) / Float(p.cells))
                }
                t += 1.0 / 30
            }
            shapeCap = Float(max(1, Int(Float(p.cells) * 0.4))) / Float(p.cells)
        }
        check("restraint round drops", shapePeak <= shapeCap + 1e-4, String(format: "peak %.2f of the grid lit away from the drop", shapePeak))

        // Projects from 2.0 open in 3.0 with the moves they had, and the new
        // choices survive a round trip; a title from 2.0 doesn't land on the beat.
        var v3 = BeatSettings()
        v3.dropMove = .fan
        v3.featureStyle = .zoom
        v3.turn = .page
        v3.intro.entrance = .weave
        let v3Again = (try? JSONEncoder().encode(v3)).flatMap { try? decoder.decode(BeatSettings.self, from: $0) }
        let oldTitle = try? decoder.decode(ReelTitle.self, from: Data(#"{"text":"Hi","placement":"centre","timing":"opening"}"#.utf8))
        let titleAgain = (try? JSONEncoder().encode(headline)).flatMap { try? decoder.decode(ReelTitle.self, from: $0) }
        check("old projects 3.0", empty?.dropMove == .light && empty?.featureStyle == .lift && empty?.turn == .flip && v3Again == v3
              && oldTitle?.beat == false && oldTitle?.text == "Hi" && titleAgain == headline,
              "2.0 settings and titles read with 3.0 defaults; a round trip keeps the new choices")

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
        // And a deck fitted around it keeps its slides whole, or nearly.
        let hdAround = GridSettings().fitted(count: 24, aspect: tall, slideAspect: 16.0 / 9.0, clear: clear)
        let around = GridLayout(settings: hdAround, aspect: tall, slideAspect: 16.0 / 9.0, clear: clear)
        let bare = GridLayout(settings: GridSettings().fitted(count: 24, aspect: tall, slideAspect: 16.0 / 9.0), aspect: tall,
                              slideAspect: 16.0 / 9.0, clear: clear)
        check("fit round a caption", around.crop <= 0.35 + 1e-4 && around.cells.count >= 24,
              String(format: "24 slides at 1920×1080: %d×%d %@, %.0f%% cropped (fitted without it: %d×%d %@, %.0f%%)", around.columns, around.rows,
                     around.shape.rawValue as NSString, around.crop * 100, bare.columns, bare.rows, bare.shape.rawValue as NSString, bare.crop * 100))

        // A deck smaller than the grid: every slide shows before any repeats,
        // and a repeat never sits beside itself where another slide could.
        var smallOK = true, smallDetail: [String] = []
        for (slides, columns, rows) in [(20, 3, 7), (13, 3, 5), (8, 3, 5), (4, 3, 5), (2, 2, 3)] {
            for order in [SlideOrder.reading, .shuffle, .coverCentre] {
                var sm = BeatSettings()
                sm.grid.columns = columns
                sm.grid.rows = rows
                sm.grid.order = order
                let layout = GridLayout(settings: sm.grid, aspect: tall, slideAspect: 16.0 / 9.0)
                let p = Choreographer.plan(a, settings: sm, layout: layout, slides: slides, clipStart: 0, clipLength: 30)
                var uses = [Int](repeating: 0, count: slides)
                for s in p.firstSlide { uses[s] += 1 }
                var beside = 0
                for c in layout.cells {
                    if c.column > 0, p.firstSlide[c.index] == p.firstSlide[c.index - 1] { beside += 1 }
                    if c.row > 0, p.firstSlide[c.index] == p.firstSlide[c.index - columns] { beside += 1 }
                }
                let even = (uses.min() ?? 0) >= 1 && (uses.max() ?? 0) - (uses.min() ?? 0) <= 1
                if !even || (order == .reading && slides >= 4 && beside > 0) {
                    smallOK = false
                    smallDetail.append("\(slides) on \(columns)×\(rows) \(order.rawValue): uses \(uses), \(beside) beside")
                }
            }
        }
        check("small decks", smallOK, smallOK ? "20 on 3×7, 13, 8 and 4 on 3×5, 2 on 2×3: every slide shows, repeats spread" : smallDetail.joined(separator: "; "))

        // v6 ---------------------------------------------------------------

        func dist(_ p: SIMD2<Float>, _ q: SIMD2<Float>) -> Float { let d = p - q; return (d * d).sum().squareRoot() }
        var bbb = BeatSettings()
        LookMoves.beatByBeat(&bbb)

        // Beat by Beat opens on the empty room and lands a slide on every slot after the first
        // beat, on the beat grid, scattered, never in reading order, the cover alone and last on the drop.
        var buildBad: [String] = [], buildDetail: [String] = []
        for slides in [8, 15, 30, 60] {
            var b = bbb
            b.grid = GridSettings().fitted(count: slides, aspect: tall, slideAspect: 16.0 / 9.0)
            let layout = GridLayout(settings: b.grid, aspect: tall, slideAspect: 16.0 / 9.0)
            let p = Choreographer.plan(a, settings: b, layout: layout, slides: slides, clipStart: 0, clipLength: 30)
            let i = p.intro
            let x0 = p.beatPosition(at: i.buildStart)
            let onGrid = i.step > 0 && i.landings.allSatisfy { t in
                let k = (p.beatPosition(at: t) - x0) / i.step
                return abs(k - k.rounded()) < 0.02 && k.rounded() >= 1
            }
            let coverLast = i.landings.indices.allSatisfy { $0 == i.coverCell || i.landings[$0] < i.landings[i.coverCell] - 1e-6 }
            let order = i.order.filter { $0 != i.coverCell }
            let diagonal = (layout.gridSize * layout.gridSize).sum().squareRoot()
            let hops = zip(order, order.dropFirst()).map { dist(layout.cells[$0].centre, layout.cells[$1].centre) / diagonal }
            let hop = hops.reduce(0, +) / Float(max(hops.count, 1))
            let scene = BeatScene(plan: p, layout: layout, settings: b)
            let empty = scene.frame(at: 0, context(slides, aspect: tall)).cards.isEmpty
            let full = scene.frame(at: i.end + 0.01, context(slides, aspect: tall)).cards.count >= p.cells
            if !(abs(i.end - dropAt) < 0.06 && onGrid && coverLast && order != order.sorted() && hop >= 0.3 && empty && full) {
                buildBad.append("\(slides): end \(i.end) grid \(onGrid) cover \(coverLast) hop \(hop) empty \(empty) full \(full)")
            }
            buildDetail.append(String(format: "%d on %@ beats", slides, i.step >= 1 ? "\(Int(i.step))" : (i.step == 0.5 ? "½" : "¼")))
        }
        check("build on the beat", buildBad.isEmpty, buildBad.isEmpty
              ? "the empty room, then \(buildDetail.joined(separator: ", ")), scattered, the cover on the drop at \(String(format: "%.2f", dropAt)) s"
              : buildBad.joined(separator: "; "))

        // On every hit: the slides land on the song's own onsets (or the beat grid where there
        // are too few), never two within a sixteenth.
        do {
            var h = bbb
            h.intro.pace = .hits
            let p = Choreographer.plan(a, settings: h, layout: grid, slides: 15, clipStart: 0, clipLength: 30)
            let onsetTimes = a.onsets(from: 0, to: 30).map(\.time)
            let times = Set(p.intro.landings.map { ($0 * 1000).rounded() / 1000 }).sorted()
            let onHits = p.intro.landings.filter { t in onsetTimes.contains { abs($0 - t) < 0.002 } }.count
            let apart = zip(times, times.dropFirst()).allSatisfy { $1 - $0 >= p.period / 4 * 0.85 }
            check("build on every hit", onHits >= p.cells - 1 && apart,
                  "\(onHits) of \(p.cells) slides land on a hit, none within a sixteenth of another")
        }

        // Voices: after the build, each light on a slide comes with a sound in its own voice.
        do {
            let p = Choreographer.plan(a, settings: bbb, layout: grid, slides: 15, clipStart: 0, clipLength: 30)
            let onsets = a.onsets(from: 0, to: 30)
            var total = 0, answered = 0
            for c in 0..<p.cells {
                for g in p.triggers[c] where g.time > p.intro.end + p.period && g.time < p.outro.start - 0.01
                    && !p.drops.contains(where: { abs(g.time - $0) < p.period * 2 }) {
                    total += 1
                    if onsets.contains(where: { abs($0.time - g.time) < 0.002 && $0.register == p.intro.voices[c] }) { answered += 1 }
                }
            }
            let mix = Register.allCases.map { r in p.intro.voices.filter { $0 == r }.count }
            check("voices answer", total > 20 && answered == total,
                  "\(answered) of \(total) lights answer their slide's own sound; voices \(mix[0]) low, \(mix[1]) mid, \(mix[2]) high")
        }

        // Restraint holds while the slides answer their voices, after a build.
        do {
            let p = Choreographer.plan(a, settings: bbb, layout: grid, slides: 15, clipStart: 0, clipLength: 30)
            var peak: Float = 0
            var t = p.intro.end + p.period
            while t < p.outro.start {
                if !p.drops.contains(where: { t > $0 - p.period && t < $0 + 4 * p.period }),
                   !p.features.contains(where: { t >= $0.liftOff && t <= $0.end }) {
                    var lit = 0
                    for c in 0..<p.cells where p.light(cell: c, at: t).level > 0.5 { lit += 1 }
                    peak = max(peak, Float(lit) / Float(p.cells))
                }
                t += 1.0 / 30
            }
            let cap = Float(max(1, Int(Float(p.cells) * 0.4))) / Float(p.cells)
            check("restraint after a build", peak <= cap + 1e-4, String(format: "peak %.2f of the grid lit", peak))
        }

        // Leave on the beat: the clip starts and ends on the empty room, so it loops; the board
        // is whole just before it starts to empty.
        do {
            let p = Choreographer.plan(a, settings: bbb, layout: grid, slides: 15, clipStart: 0, clipLength: 32)
            let scene = BeatScene(plan: p, layout: grid, settings: bbb)
            let ctx = context(15, aspect: tall)
            let first = scene.frame(at: 0, ctx).cards.count, last = scene.frame(at: p.length - 1.0 / 240, ctx).cards.count
            let whole = scene.frame(at: p.outro.start, ctx).cards.count
            let lastOut = p.outro.leaves.filter { $0 < p.length }.max() ?? 0
            check("leave loops", p.outro.kind == .leave && first == 0 && last == 0 && whole >= p.cells,
                  String(format: "%d cards at 0 and %d at the end; all %d at %.2f s; the cover leaves at %.2f s of %.2f",
                         first, last, whole, p.outro.start, lastOut, p.length))
        }

        // Curtain call and Drift away end on the cover alone, square, still and inside the frame.
        var endBad: [String] = []
        for outro in [Outro.curtainCall, .driftAway] {
            for slides in [15, 30] {
                var e = bbb
                e.outro = outro
                e.grid = GridSettings().fitted(count: slides, aspect: tall, slideAspect: 16.0 / 9.0)
                let layout = GridLayout(settings: e.grid, aspect: tall, slideAspect: 16.0 / 9.0)
                let p = Choreographer.plan(a, settings: e, layout: layout, slides: slides, clipStart: 0, clipLength: 30)
                let scene = BeatScene(plan: p, layout: layout, settings: e)
                let ctx = context(slides, aspect: tall)
                let end = scene.frame(at: p.length - 1.0 / 240, ctx).cards
                let still = scene.frame(at: p.length - 1.0 / 30, ctx).cards
                guard end.count == 1, let c = end.first, c.occurrence == p.intro.coverCell else {
                    endBad.append("\(outro.rawValue) \(slides): \(end.count) cards at the end")
                    continue
                }
                let k = BeatScene.seen(c.position.z)
                let inside = abs(c.position.x * k) + c.size.x * k / 2 <= tall / 2 + 1e-3 && abs(c.position.y * k) + c.size.y * k / 2 <= 0.5 + 1e-3
                let square = abs(c.rotation.x) + abs(c.rotation.y) + abs(c.rotation.z) < 1e-3
                let moved = still.first.map { dist(SIMD2($0.position.x, $0.position.y), SIMD2(c.position.x, c.position.y)) } ?? 1
                if !inside || !square || (outro == .curtainCall && moved > 1e-4) {
                    endBad.append("\(outro.rawValue) \(slides): inside \(inside) square \(square) moved \(moved)")
                }
            }
        }
        check("endings", endBad.isEmpty, endBad.isEmpty ? "Curtain call and Drift away end on the cover, square and inside the frame" : endBad.joined(separator: "; "))

        // Collage: a deck of mixed shapes lays out whole, each slide at its own shape, without
        // overlaps, inside the box, covering at least 55 % of it, in a Reel, a square and a landscape frame.
        let mixed: [Float] = [16.0 / 9.0, 4.0 / 3.0, 1, 9.0 / 16.0, wide, 3.0 / 4.0, 16.0 / 9.0, 1.5, 4.0 / 5.0, 16.0 / 9.0, 1, 21.0 / 9.0,
                              2.0 / 3.0, 16.0 / 9.0, 4.0 / 3.0]
        var collageBad: [String] = [], collageDetail: [String] = []
        for (name, canvas) in [("reel", tall), ("square", Float(1)), ("landscape", Float(16.0 / 9.0))] {
            for n in [5, 9, 15] {
                let aspects = Array(mixed.prefix(n))
                let g = GridSettings().fitted(count: n, aspect: canvas, slideAspect: 16.0 / 9.0, aspects: aspects)
                let l = GridLayout(settings: g, aspect: canvas, slideAspect: 16.0 / 9.0, aspects: aspects)
                let shapes = l.cells.allSatisfy { abs($0.size.x / $0.size.y / aspects[$0.index] - 1) < 0.01 }
                var overlaps = 0
                for i in l.cells.indices {
                    for j in l.cells.indices where j > i {
                        let p = l.cells[i], q = l.cells[j]
                        if abs(p.centre.x - q.centre.x) < (p.size.x + q.size.x) / 2 - 1e-5, abs(p.centre.y - q.centre.y) < (p.size.y + q.size.y) / 2 - 1e-5 { overlaps += 1 }
                    }
                }
                let inside = l.cells.allSatisfy { abs($0.centre.x) + $0.size.x / 2 <= l.safeSize.x / 2 + 1e-4 && abs($0.centre.y) + $0.size.y / 2 <= l.safeSize.y / 2 + 1e-4 }
                if g.arrangement != .collage || l.count != n || !shapes || overlaps > 0 || !inside || l.coverage < 0.55 {
                    collageBad.append("\(name) \(n): \(g.arrangement.rawValue) shapes \(shapes) overlaps \(overlaps) inside \(inside) cover \(l.coverage)")
                }
                if n == 15 { collageDetail.append("\(name) \(l.rows)×\(l.columns) \(Int(l.coverage * 100))%") }
            }
        }
        let same = GridSettings().fitted(count: 15, aspect: tall, slideAspect: 16.0 / 9.0, aspects: [Float](repeating: 16.0 / 9.0, count: 15))
        if same.arrangement != .grid { collageBad.append("a deck of one shape became a collage") }
        check("collage", collageBad.isEmpty, collageBad.isEmpty ? "15 mixed slides whole: \(collageDetail.joined(separator: ", ")); one shape keeps its grid" : collageBad.joined(separator: "; "))

        // Every mode, ending and drop on a collage, building or dealt: no broken cards.
        do {
            let aspects = mixed
            var g = GridSettings().fitted(count: 15, aspect: tall, slideAspect: 16.0 / 9.0, aspects: aspects)
            g.order = .reading
            let layout = GridLayout(settings: g, aspect: tall, slideAspect: 16.0 / 9.0, aspects: aspects)
            let ctx = SceneContext(items: aspects.enumerated().map { SceneItem(media: $0.offset, occurrence: $0.offset, aspect: $0.element) },
                                   aspect: tall, dials: SceneDials())
            var bad = 0, clips = 0
            for mode in BeatMode.allCases {
                for (outro, move) in [(Outro.leave, DropMove.tunnel), (.curtainCall, .fan), (.driftAway, .strip), (.loop, .weave), (.close, .light)] {
                    var c = bbb
                    c.grid = g
                    c.mode = mode
                    c.outro = outro
                    c.dropMove = move
                    c.feature = .twoBars
                    c.loose = 0.5
                    c.intro.pace = mode == .equaliser ? .together : .beats
                    let p = Choreographer.plan(a, settings: c, layout: layout, slides: 15, clipStart: 0, clipLength: 30)
                    let scene = BeatScene(plan: p, layout: layout, settings: c)
                    clips += 1
                    var t = 0.0
                    while t <= 30 {
                        for card in scene.frame(at: t, ctx).cards where !sound(card, slides: 15) { bad += 1 }
                        t += 1.0 / 15
                    }
                }
            }
            check("collage poses", bad == 0, "\(bad) broken cards across \(clips) collage clips at 15 fps")
        }

        // Fifty slides or more: the fitted grid shows every slide with less than a row spare, up to 12 across.
        var bigFits: [String] = [], bigBad = 0
        for (name, shape) in [("2576", wide), ("1920", Float(16.0 / 9.0))] {
            for n in [50, 60, 100, 150] {
                let g = GridSettings().fitted(count: n, aspect: tall, slideAspect: shape)
                let l = GridLayout(settings: g, aspect: tall, slideAspect: shape)
                let inside = l.cells.allSatisfy { abs($0.centre.x) + $0.size.x / 2 <= l.safeSize.x / 2 + 1e-4 && abs($0.centre.y) + $0.size.y / 2 <= l.safeSize.y / 2 + 1e-4 }
                if l.count < n || l.count - n >= l.columns || !inside { bigBad += 1 }
                if n == 60 || n == 100 { bigFits.append("\(name) \(n): \(l.columns)×\(l.rows) gap \(Int(g.gap))") }
            }
        }
        check("fit 50 to 150", bigBad == 0, bigFits.joined(separator: ", "))

        // Loose: cards stay in the frame; a slide held up to be read is square and flat.
        do {
            var l = bbb
            l.loose = 1
            l.feature = .twoBars
            l.featureStyle = .lift
            l.outro = .loop
            let p = Choreographer.plan(a, settings: l, layout: grid, slides: 15, clipStart: 0, clipLength: 60)
            let scene = BeatScene(plan: p, layout: grid, settings: l)
            let ctx = context(15, aspect: tall)
            var out = 0, tilted = 0, held = 0
            var t = p.intro.end + 0.3
            while t < p.outro.start {
                for c in scene.frame(at: t, ctx).cards {
                    let r = abs(c.rotation.z)
                    let w = (c.size.x * cosf(r) + c.size.y * sinf(r)) / 2, h = (c.size.x * sinf(r) + c.size.y * cosf(r)) / 2
                    if abs(c.position.x) + w > tall / 2 + 1e-3 || abs(c.position.y) + h > 0.5 + 1e-3 { out += 1 }
                }
                t += 1.0 / 15
            }
            for f in p.features {
                for c in scene.frame(at: f.land + (f.leave - f.land) / 2, ctx).cards where c.layer >= 10 {
                    held += 1
                    if abs(c.rotation.x) + abs(c.rotation.y) + abs(c.rotation.z) > 1e-3 { tilted += 1 }
                }
            }
            check("loose", out == 0 && tilted == 0 && held > 0, "\(out) cards out of frame; \(held) slides held up to read, \(tilted) of them turned")
        }

        // Idle and active presets each set both states, and active is the stronger.
        let presetsOK = StatePreset.all.allSatisfy { pr in
            var s = BeatSettings()
            pr.apply(&s)
            return pr.matches(s) && pr.active.brightness >= pr.idle.brightness && pr.active.scale > pr.idle.scale
        } && Set(StatePreset.all.map(\.id)).count == StatePreset.all.count
        check("presets", presetsOK, "\(StatePreset.all.count) idle and active pairs: \(StatePreset.all.map(\.name).joined(separator: ", "))")

        // Projects from 3.0 open in 6.0 as they were: a deal, tight, tidy, on a grid; the new
        // choices survive a round trip.
        do {
            let json = #"{"mode":"pulse","intro":{"coldOpen":true,"entrance":"deal","order":"centreOut","bars":0},"motion":{"attack":0.05,"bounce":0.08},"grid":{"columns":3,"rows":5,"margins":"safe"},"outro":"auto"}"#
            let old = try? decoder.decode(BeatSettings.self, from: Data(json.utf8))
            var v6 = bbb
            v6.grid.arrangement = .collage
            v6.grid.margins = .clear
            v6.loose = 0.4
            let again = (try? JSONEncoder().encode(v6)).flatMap { try? decoder.decode(BeatSettings.self, from: $0) }
            let p = Choreographer.plan(a, settings: old ?? BeatSettings(), layout: grid, slides: 15, clipStart: 0, clipLength: 30)
            let dealt = p.intro.pace == .together && p.intro.flights.allSatisfy { $0 == p.intro.flight }
            check("old projects 6.0", old?.intro.pace == .together && old?.motion.feel == 0 && old?.loose == 0 && old?.grid.arrangement == .grid
                  && again == v6 && dealt && p.outro.kind == .loop,
                  "3.0 settings read as a deal, tight and tidy on a grid, ending in a loop; a round trip keeps the 6.0 choices")
        }

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
