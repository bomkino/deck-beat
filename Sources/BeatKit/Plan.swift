import Foundation

// The choreography, worked out once for a clip: who lights when, which slide
// steps out to be read, when the cards arrive and leave. The scene then reads
// it at any time, so every frame is a pure function of time and the preview
// is the export.

/// One light on one cell: up over the attack, peaking on `time`, held, then
/// falling back.
public struct Trigger: Sendable {
    public var time: Double
    public var amp: Float
    public var hold: Double
    /// Seconds to fall to 5 %.
    public var release: Double
    /// Glow only: a glint from the hats, never a move.
    public var glint: Bool
    /// Which way a lit card leans (away from where the light came from), or zero.
    public var lean: SIMD2<Float>

    public init(time: Double, amp: Float, hold: Double, release: Double, glint: Bool = false, lean: SIMD2<Float> = .zero) {
        self.time = time
        self.amp = amp
        self.hold = hold
        self.release = release
        self.glint = glint
        self.lean = lean
    }
}

/// One slide stepping out of the grid to be read.
public struct FeatureMoment: Sendable {
    public var slide: Int
    /// The cell whose card steps out, or nil when the slide is not on the grid.
    public var cell: Int?
    public var liftOff: Double
    public var land: Double
    public var leave: Double
    public var end: Double
}

/// What happens on one drop, and for a grid that re-forms, when it comes home.
public struct DropMoment: Sendable {
    /// The downbeat of the drop.
    public var time: Double
    public var move: DropMove
    /// How long the cards take to reach their shape, and to come home.
    public var flyOut: Double
    public var flyHome: Double
    /// The downbeat the cards land back in their cells on.
    public var home: Double
    /// When the moment starts to show (the bar before the drop for a weave or
    /// a shape) and when it has finished; nothing else is planned in between.
    public var start: Double
    public var end: Double

    /// When the cards set off for home.
    public var leave: Double { home - flyHome }
}

/// A cell turning over to show another slide; `time` is when it is edge-on.
public struct Swap: Sendable {
    public var time: Double
    public var slide: Int
}

public struct IntroPlan: Sendable {
    /// When the last card lands and the music takes over.
    public var end: Double
    /// Per cell, when it lands.
    public var landings: [Double]
    /// The usual flight, and each card's own (by its voice, loosened by Feel).
    public var flight: Double
    public var flights: [Double]
    public var coldOpen: Bool
    public var coverCell: Int
    /// When the cover starts back to its cell.
    public var coverMove: Double
    public var pace: IntroPace
    /// Per cell, the sound that placed it: low (kick), mid (snare) or high (hats).
    public var voices: [Register]
    /// The cells in the order they land, the cover last.
    public var order: [Int]
    /// Beats between landing slots in a build (0 for a deal).
    public var step: Double
    /// Where the build began: its first beat, left empty.
    public var buildStart: Double
}

public struct OutroPlan: Sendable {
    public var kind: Outro
    /// When the outro begins; the clip's length when there is none.
    public var start: Double
    /// Close, leave, curtain call, drift away: per cell, when it starts to
    /// leave. Lights out: when it starts to go dark. Past the clip for a card that stays.
    public var leaves: [Double]
    public var flight: Double
    /// Per cell, how long it takes to leave.
    public var flights: [Double]
    /// Curtain call: per cell, when its bow peaks.
    public var bows: [Double]
    /// Per cell, its place in the order of leaving (0 first), so cards in
    /// flight ride over each other in a fixed order.
    public var rank: [Int]
    /// Close, curtain call, drift away: when the cover starts to rise, to be
    /// held up over the last moments.
    public var coverRise: Double
    /// The last downbeat, where the end card lands (curtain call: where the cover bows).
    public var end: Double
    /// Lights out: how long a slide takes to go dark.
    public var fade: Double
    /// The cover holds up front to the end.
    public var coverHolds: Bool
}

public final class BeatPlan: @unchecked Sendable {
    public static let rate: Double = 100

    public let start: Double
    public let length: Double
    public let period: Double
    public let cells: Int
    public let slides: Int
    public let triggers: [[Trigger]]
    /// The longest a trigger can still be seen after its peak.
    public let reach: Double
    public let attack: Double
    public let features: [FeatureMoment]
    public let firstSlide: [Int]
    public let swaps: [[Swap]]
    public let flipTime: Double
    /// Equaliser: per column, the level in rows and the held peak, at `rate`.
    public let levels: [[Float]]
    public let peaks: [[Float]]
    /// In scene time.
    public let drops: [Double]
    /// What each drop does, in the same order.
    public let moments: [DropMoment]
    public let punches: [(time: Double, amount: Float)]
    /// The kick, 0…1 at `rate`, for the backdrop and the cover.
    public let pulse: [Float]
    /// Loudness at `rate`.
    public let loud: [Float]
    public let intro: IntroPlan
    public let outro: OutroPlan
    /// Beats in scene time, and which are downbeats.
    public let beats: [Double]
    public let downbeats: [Double]

    init(start: Double, length: Double, period: Double, cells: Int, slides: Int, triggers: [[Trigger]], reach: Double, attack: Double,
         features: [FeatureMoment], firstSlide: [Int], swaps: [[Swap]], flipTime: Double, levels: [[Float]], peaks: [[Float]],
         drops: [Double], moments: [DropMoment], punches: [(time: Double, amount: Float)], pulse: [Float], loud: [Float], intro: IntroPlan,
         outro: OutroPlan, beats: [Double], downbeats: [Double]) {
        self.start = start
        self.length = length
        self.period = period
        self.cells = cells
        self.slides = slides
        self.triggers = triggers
        self.reach = reach
        self.attack = attack
        self.features = features
        self.firstSlide = firstSlide
        self.swaps = swaps
        self.flipTime = flipTime
        self.levels = levels
        self.peaks = peaks
        self.drops = drops
        self.moments = moments
        self.punches = punches
        self.pulse = pulse
        self.loud = loud
        self.intro = intro
        self.outro = outro
        self.beats = beats
        self.downbeats = downbeats
    }

    // MARK: Reading

    @inline(__always)
    public static func sample(_ track: [Float], _ t: Double) -> Float {
        guard !track.isEmpty else { return 0 }
        let x = max(0, t * rate)
        let i = Int(x)
        if i >= track.count - 1 { return track[track.count - 1] }
        let f = Float(x - Double(i))
        return track[i] + (track[i + 1] - track[i]) * f
    }

    /// A trigger's level at `t`.
    @inline(__always)
    public func envelope(_ g: Trigger, at t: Double) -> Float {
        let x = t - g.time
        if x < -attack { return 0 }
        if x < 0 {
            // Ease out, so the light is nearly up when the sound lands.
            let p = Float((x + attack) / max(attack, 1e-4))
            let q = 1 - p
            return g.amp * (1 - q * q * q * q)
        }
        if x < g.hold { return g.amp }
        let y = (x - g.hold) / max(g.release, 1e-3)
        if y > 1.6 { return 0 }
        return g.amp * Float(exp(-3 * y))
    }

    /// The light on a cell at `t` (0…1), its glint, how long since its last
    /// hit and how hard it was, and which way it leans.
    public func light(cell: Int, at t: Double) -> (level: Float, glint: Float, since: Double, last: Float, lean: SIMD2<Float>) {
        let list = triggers[cell]
        guard !list.isEmpty else { return (0, 0, .infinity, 0, .zero) }
        // The first trigger that can still be seen.
        var lo = 0, hi = list.count
        let from = t - reach
        while lo < hi {
            let mid = (lo + hi) / 2
            if list[mid].time < from { lo = mid + 1 } else { hi = mid }
        }
        var dark: Float = 1, glint: Float = 0
        var since = Double.infinity, last: Float = 0
        var lean = SIMD2<Float>.zero
        var i = lo
        while i < list.count, list[i].time <= t + attack {
            let g = list[i]
            let e = envelope(g, at: t)
            if g.glint {
                glint = max(glint, e)
            } else {
                dark *= 1 - min(e, 1)
                if g.time <= t { since = t - g.time; last = g.amp; if g.lean != .zero { lean = g.lean } }
            }
            i += 1
        }
        return (1 - dark, glint, since, last, lean)
    }

    /// The slide a cell shows at `t`, and how far through a turn it is (−1…1,
    /// 0 when face on; negative before the swap, positive after).
    public func slide(cell: Int, at t: Double) -> (slide: Int, turn: Float) {
        var slide = firstSlide[cell]
        var turn: Float = 0
        for s in swaps[cell] {
            let d = t - s.time
            if d >= 0 { slide = s.slide }
            if abs(d) < flipTime / 2 { turn = Float(d / (flipTime / 2)) }
            if d < -flipTime { break }
        }
        return (slide, turn)
    }

    /// A turn in progress on a cell at `t`: the slide it leaves, the one it
    /// turns to, and how far through the turn it is (0…1, halfway when edge-on).
    public func turnover(cell: Int, at t: Double) -> (from: Int, to: Int, progress: Float)? {
        var slide = firstSlide[cell]
        for s in swaps[cell] {
            let d = t - s.time
            if abs(d) < flipTime / 2 { return (slide, s.slide, Float((d + flipTime / 2) / flipTime)) }
            if d < 0 { break }
            slide = s.slide
        }
        return nil
    }

    /// The drop whose weave or shape is showing at `t`, if any.
    public func moment(at t: Double) -> DropMoment? {
        moments.first { $0.move != .light && t >= $0.start && t <= $0.end }
    }

    /// Position in beats since the clip began (fractional), for idle motion.
    public func beatPosition(at t: Double) -> Double {
        guard beats.count > 1 else { return t / period }
        var lo = 0, hi = beats.count - 1
        if t <= beats[0] { return (t - beats[0]) / period }
        if t >= beats[hi] { return Double(hi) + (t - beats[hi]) / period }
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if beats[mid] <= t { lo = mid } else { hi = mid }
        }
        return Double(lo) + (t - beats[lo]) / max(beats[lo + 1] - beats[lo], 1e-3)
    }

    /// The camera's push in, 0…, from loud downbeats and drops.
    public func punch(at t: Double) -> Float {
        var p: Float = 0
        for e in punches where e.time > t - 0.9 && e.time < t + 0.05 {
            let x = t - e.time
            let v: Float = x < 0 ? Float(1 + x / 0.04) : Float(exp(-3 * x / 0.45))
            p = max(p, e.amount * max(0, v))
        }
        return p
    }

    /// 0…1 over the bar before a drop, back to 0 on it.
    public func inhale(at t: Double) -> Float {
        let bar = period * 4
        for d in drops where t < d && t > d - bar {
            let x = Float((t - (d - bar)) / bar)
            return x * x * (3 - 2 * x)
        }
        return 0
    }

    /// The flash on a drop, 1 on the downbeat, falling over half a second.
    public func flash(at t: Double) -> Float {
        var f: Float = 0
        for d in drops where t >= d - 0.03 && t < d + 1.2 {
            f = max(f, t < d ? Float((t - d + 0.03) / 0.03) : Float(exp(-3 * (t - d) / 0.5)))
        }
        return f
    }
}

// MARK: - Planning

/// Small seeded randomness, the same on every machine.
struct Seeded {
    var state: UInt64
    init(_ seed: UInt32, salt: UInt64 = 0) { state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ salt &+ 0x632B_E59B_D9B4_E019 }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func shuffled(_ n: Int) -> [Int] {
        var a = Array(0..<n)
        if n > 1 { for i in stride(from: n - 1, to: 0, by: -1) { a.swapAt(i, Int(next() % UInt64(i + 1))) } }
        return a
    }
}

public enum Choreographer {
    /// Works out the choreography for a clip of a song on a layout.
    public static func plan(_ song: SongAnalysis, settings s: BeatSettings, layout: GridLayout, slides: Int,
                            clipStart: Double, clipLength: Double, starred: Set<Int> = []) -> BeatPlan {
        let n = layout.count
        let slideCount = max(1, slides)
        let length = max(clipLength, 0.5)
        let start = clipStart
        let tempo = song.tempo > 0 ? song.tempo : 120
        let period = 60 / tempo
        let sixteenth = period / 4
        let bar = period * 4
        let S = min(max(s.sensitivity, 0), 1)
        let release = max(0.08, s.motion.release * period)
        let holdTime = max(0, min(s.motion.hold, 0.5)) * period
        // The cover: the first starred slide, or the first.
        let coverSlide = starred.filter { $0 < slideCount }.min() ?? 0
        var rng = Seeded(s.seed)

        // Beats and downbeats in scene time.
        let clipBeats = song.beats.filter { $0.time >= start - period * 1.5 && $0.time <= start + length + period * 1.5 }
        let beatTimes = clipBeats.map { $0.time - start }
        let downbeats = clipBeats.filter(\.isDownbeat).map { $0.time - start }
        func strength(at t: Double) -> Float {
            clipBeats.min(by: { abs($0.time - start - t) < abs($1.time - start - t) })?.strength ?? 0.5
        }

        // Loudness and the kick, in scene time.
        let frames = Int(length * BeatPlan.rate) + 2
        let loud: [Float] = (0..<frames).map { SongAnalysis.sample(song.loudness, at: start + Double($0) / BeatPlan.rate) }
        func loudness(_ t: Double) -> Float { BeatPlan.sample(loud, t) }
        let onsets = song.onsets(from: start - 0.5, to: start + length + 0.5).map {
            Onset(time: $0.time - start, strength: $0.strength, register: $0.register)
        }
        var pulse = [Float](repeating: 0, count: frames)
        do {
            let lows = onsets.filter { $0.register == .low }
            var k = 0
            var level: Float = 0
            let decay = Float(exp(-3 / (0.4 * BeatPlan.rate)))
            for f in 0..<frames {
                let t = Double(f) / BeatPlan.rate
                level *= decay
                while k < lows.count, lows[k].time <= t + 0.02 {
                    level = max(level, lows[k].strength)
                    k += 1
                }
                pulse[f] = min(1, level)
            }
        }

        // MARK: Intro
        let firstDown = downbeats.first(where: { $0 >= -0.05 }) ?? 0
        func downbeat(barsAfterFirst k: Int) -> Double {
            if let i = downbeats.firstIndex(where: { $0 >= -0.05 }), i + k < downbeats.count { return downbeats[i + k] }
            return firstDown + Double(k) * bar
        }
        let freeTime = song.confidence < 0.4 || downbeats.isEmpty
        let builds = s.intro.pace.builds
        let feel = Double(min(max(s.motion.feel, 0), 1))
        /// A seeded 0…1 per cell, apart from the plan's own sequence so older plans keep their timing.
        func unit(_ c: Int, _ salt: UInt64) -> Double {
            var r = Seeded(s.seed, salt: salt &+ UInt64(c) &* 0x9E37_79B9)
            return Double(r.unit())
        }
        // The beats as a continuous count, so a slot between two beats falls where the music does.
        func position(_ t: Double) -> Double {
            guard beatTimes.count > 1, !freeTime else { return t / period }
            let last = beatTimes.count - 1
            if t <= beatTimes[0] { return (t - beatTimes[0]) / period }
            if t >= beatTimes[last] { return Double(last) + (t - beatTimes[last]) / period }
            var lo = 0, hi = last
            while lo < hi - 1 {
                let mid = (lo + hi) / 2
                if beatTimes[mid] <= t { lo = mid } else { hi = mid }
            }
            return Double(lo) + (t - beatTimes[lo]) / max(beatTimes[lo + 1] - beatTimes[lo], 1e-3)
        }
        func time(_ x: Double) -> Double {
            guard beatTimes.count > 1, !freeTime else { return x * period }
            let last = beatTimes.count - 1
            if x <= 0 { return beatTimes[0] + x * period }
            if x >= Double(last) { return beatTimes[last] + (x - Double(last)) * period }
            let i = Int(x.rounded(.down))
            return beatTimes[i] + (beatTimes[i + 1] - beatTimes[i]) * (x - Double(i))
        }
        var introBars = s.intro.bars
        var introEnd: Double
        var buildStart = 0.0
        // A drop in the song that the build lands its last slide on.
        var buildDrop: Double?
        if builds {
            // The board builds from the clip's first beat, left empty so the room is seen first, to the
            // first drop if it comes four to eight bars in, or over bars sized to the deck.
            buildStart = freeTime ? 0 : (beatTimes.first(where: { $0 >= -0.05 }) ?? 0)
            func downbeat(bars k: Int, after t: Double) -> Double {
                if let i = downbeats.firstIndex(where: { $0 >= t - 0.05 }), i + k < downbeats.count { return downbeats[i + k] }
                return (downbeats.first(where: { $0 >= t - 0.05 }) ?? t) + Double(k) * bar
            }
            let drop = freeTime || s.intro.bars > 0 ? nil : song.drops.map { $0 - start }.first {
                $0 >= buildStart + bar * 3.9 && $0 <= buildStart + bar * 8.1 && $0 <= length * 0.6
            }
            if let d = drop {
                let snapped = downbeats.min { abs($0 - d) < abs($1 - d) }.flatMap { abs($0 - d) < period * 0.6 ? $0 : nil } ?? d
                introEnd = snapped
                buildDrop = snapped
            } else {
                var bars = s.intro.bars > 0 ? s.intro.bars : Self.buildBars(cells: n)
                while bars > 1, downbeat(bars: bars, after: buildStart) > length * 0.5 { bars -= 1 }
                introEnd = freeTime ? min(Double(bars) * 2, length * 0.5) : downbeat(bars: bars, after: buildStart)
            }
            introBars = max(1, Int(((introEnd - firstDown) / bar).rounded()))
        } else {
            if introBars <= 0 {
                // The fewest of 1, 2 or 4 bars that give the deal room to read.
                introBars = 1
                while introBars < 4, downbeat(barsAfterFirst: introBars) - max(firstDown, 0) < 1.6 { introBars *= 2 }
            }
            introEnd = downbeat(barsAfterFirst: introBars)
            if freeTime { introEnd = 2.0 }
            introEnd = min(introEnd, length * 0.4)
        }
        let flight = builds ? min(max(period * 0.75, 0.25), 0.5) : (freeTime ? 0.45 : min(max(period, 0.35), 0.6))
        // Order ranks, 0…1.
        let ranks = staggerRanks(layout, order: s.intro.order, rng: &rng)

        // MARK: Slides in cells
        var first = [Int](repeating: 0, count: n)
        if layout.arrangement == .collage {
            // Each collage cell is sized for its own slide, so the deck sits in order.
            first = (0..<n).map { $0 % slideCount }
        } else {
            let perm = rng.shuffled(slideCount)
            let middle = s.grid.order == .coverCentre || (s.grid.order == .reading && layout.rows % 2 == 1 && layout.columns % 2 == 1)
            if slideCount >= n {
                for c in layout.cells { first[c.index] = s.grid.order == .shuffle ? perm[c.index] : c.index }
                if coverSlide != 0, !first.contains(coverSlide) { first[0] = coverSlide }
                if middle, n > 1 {
                    let centre = layout.centreCell
                    if let at = first.firstIndex(of: coverSlide) { first.swapAt(at, centre) } else { first[centre] = coverSlide }
                }
            } else {
                let pin = middle && n > 1 ? (cell: layout.centreCell, slide: coverSlide) : nil
                let order = Self.spread(slideCount, over: layout, pin: pin)
                first = s.grid.order == .shuffle ? order.map { perm[$0] } : order
            }
        }
        let cover = first.firstIndex(of: coverSlide) ?? 0

        var landings = [Double](repeating: 0, count: n)
        var voices = [Register](repeating: .low, count: n)
        var buildStep = 0.0
        let landingOrder = (0..<n).filter { !((builds || s.intro.coldOpen) && $0 == cover) }
            .sorted { (ranks[$0], $0) < (ranks[$1], $1) }
        var q = freeTime ? 0.07 : period / 8
        if builds {
            // Landing slots on the music, the cover alone and last on the drop.
            let m = landingOrder.count
            var slots: [Double] = []
            if freeTime {
                slots = (0..<m).map { buildStart + (introEnd - buildStart) * Double($0 + 1) / Double(m + 1) }
            } else {
                let x0 = position(buildStart), x1 = position(introEnd)
                let span = x1 - x0
                // The coarsest step that fits every slide: a bar, a half note, a beat, an eighth, a sixteenth.
                buildStep = 0.25
                for f in [4.0, 2, 1, 0.5, 0.25] where Int((span / f - 1e-3).rounded(.down)) >= m {
                    buildStep = f
                    break
                }
                let count = max(0, Int((span / buildStep - 1e-3).rounded(.down)))
                let grid = count > 0 ? (1...count).map { time(x0 + Double($0) * buildStep) } : []
                if s.intro.pace == .hits {
                    // The song's own hits, strongest first with a lift for the beat and the
                    // downbeat, never two within a sixteenth and never crowding one bar.
                    let lo = buildStart + sixteenth * 0.5, hi = introEnd - sixteenth * 0.5
                    let ranked = onsets.filter { $0.time > lo && $0.time < hi }.map { o -> (t: Double, score: Float) in
                        var score = o.strength
                        if downbeats.contains(where: { abs($0 - o.time) < 0.06 }) { score += 0.3 }
                        else if beatTimes.contains(where: { abs($0 - o.time) < 0.06 }) { score += 0.15 }
                        return (o.time, score)
                    }.sorted { $0.score != $1.score ? $0.score > $1.score : $0.t < $1.t }
                    let barsLong = max(1, (introEnd - buildStart) / bar)
                    let perBar = max(2, Int((Double(m) / barsLong * 2).rounded(.up)))
                    var chosen: [Double] = []
                    func room(_ t: Double) -> Bool {
                        guard !chosen.contains(where: { abs($0 - t) < sixteenth * 0.9 }) else { return false }
                        let b = Int(((t - buildStart) / bar).rounded(.down))
                        return chosen.filter { Int((($0 - buildStart) / bar).rounded(.down)) == b }.count < perBar
                    }
                    for h in ranked where chosen.count < m && room(h.t) { chosen.append(h.t) }
                    // Too few hits: beats, then eighths, then sixteenths fill in.
                    if chosen.count < m {
                        let quarter = Int(((x1 - x0) * 4 - 1e-3).rounded(.down))
                        var fill: [(t: Double, weight: Int)] = []
                        if quarter > 0 {
                            for k in 1...quarter {
                                let weight = k % 4 == 0 ? 0 : (k % 2 == 0 ? 1 : 2)
                                fill.append((time(x0 + Double(k) / 4), weight))
                            }
                        }
                        fill.sort { $0.weight != $1.weight ? $0.weight < $1.weight : $0.t < $1.t }
                        for f in fill where chosen.count < m && !chosen.contains(where: { abs($0 - f.t) < sixteenth * 0.9 }) {
                            chosen.append(f.t)
                        }
                    }
                    slots = chosen.sorted()
                } else {
                    slots = Array(grid.suffix(m))
                }
            }
            // More slides than slots: a slot lands a small group, spread across the board.
            for (i, c) in landingOrder.enumerated() {
                landings[c] = slots.isEmpty ? introEnd : slots[min(slots.count - 1, i * slots.count / max(m, 1))]
            }
            landings[cover] = introEnd
            if let gap = zip(slots, slots.dropFirst()).map({ $1 - $0 }).filter({ $0 > 0.01 }).min() { q = gap }
            // Each slide takes the sound that placed it: the strongest onset within 70 ms, or else
            // its place in the bar: beats one and three low, two and four mid, off the beat high.
            for c in 0..<n {
                let t = landings[c]
                var best: Onset?
                for o in onsets where abs(o.time - t) <= 0.07 && o.strength > (best?.strength ?? -1) { best = o }
                if let best {
                    voices[c] = best.register
                } else {
                    let x = position(t)
                    let frac = x - x.rounded(.down)
                    if frac > 0.12, frac < 0.88 {
                        voices[c] = .high
                    } else {
                        let beat = clipBeats.min { abs($0.time - start - t) < abs($1.time - start - t) }
                        voices[c] = (beat?.inBar ?? 0) % 2 == 0 ? .low : .mid
                    }
                }
            }
        } else {
            // Landing slots: the widest musical spacing that fits every card into
            // the window, the cover home last on the downbeat.
            let window = max(introEnd - period * 0.5 - flight, 0)
            let gaps = max(landingOrder.count - (s.intro.coldOpen ? 0 : 1), 1)
            if !freeTime {
                for f in [1.0 / 2, 1.0 / 3, 1.0 / 4, 1.0 / 6, 1.0 / 8] where Double(gaps) * f * period <= window + 1e-6 {
                    q = f * period
                    break
                }
            }
            let slots = min(gaps, max(1, Int((window / q + 1e-6).rounded(.down))))
            for (i, c) in landingOrder.enumerated() {
                let slot = gaps > 0 ? Int((Double(i) * Double(slots) / Double(gaps)).rounded(.down)) : 0
                landings[c] = max(introEnd - Double(slots - slot) * q, flight * 0.5)
            }
            if !s.intro.coldOpen, let last = landingOrder.last { landings[last] = introEnd }
            if s.intro.coldOpen { landings[cover] = introEnd }
            // A dealt board gets a balanced mix of voices: about 40 % low, 35 % mid, 25 % high.
            let low = Int((Double(n) * 0.4).rounded()), mid = Int((Double(n) * 0.35).rounded())
            var mix = (0..<n).map { $0 < low ? Register.low : ($0 < low + mid ? .mid : .high) }
            var voiceRng = Seeded(s.seed, salt: 0x5EED_B0B)
            mix = voiceRng.shuffled(n).map { mix[$0] }
            for (i, c) in (landingOrder + (landingOrder.contains(cover) ? [] : [cover])).enumerated() { voices[c] = mix[i] }
        }
        // Each card's flight: by its voice when it comes in by sound, loosened by Feel. The landing never moves.
        var flights = [Double](repeating: flight, count: n)
        for c in 0..<n {
            var f = flight
            if s.intro.entrance == .voices {
                let share = voices[c] == .low ? 0.75 : (voices[c] == .mid ? 0.5 : 1.0 / 3)
                f = min(max(period * share, 0.15), 0.45)
            }
            if feel > 0 {
                f *= 1 + 0.3 * feel * (unit(c, 0xF1) * 2 - 1)
                f += 0.025 * feel * (unit(c, 0xF2) * 2 - 1)
            }
            // A build opens on the empty room: nothing is in the air on frame 0.
            if builds { f = min(f, max(landings[c] - 1.0 / 60, 0.06)) }
            flights[c] = max(f, 0.06)
        }
        let landed = (0..<n).sorted { (landings[$0], ranks[$0], $0) < (landings[$1], ranks[$1], $1) }
        let intro = IntroPlan(end: introEnd, landings: landings, flight: flight, flights: flights, coldOpen: s.intro.coldOpen,
                              coverCell: cover, coverMove: max(introEnd - flight * 1.25, introEnd * 0.5), pace: s.intro.pace,
                              voices: voices, order: landed, step: buildStep, buildStart: buildStart)

        // MARK: Outro
        var kind = s.outro
        if kind == .auto { kind = length <= 30.5 ? (builds ? .leave : .loop) : (builds ? .curtainCall : .close) }
        var outroStart = length
        var leaves = [Double](repeating: length + 1, count: n)
        var outFlights = [Double](repeating: flight, count: n)
        var bows = [Double](repeating: -100, count: n)
        var rank = [Int](repeating: 0, count: n)
        var coverRise = length + 1
        var outroEnd = length
        var coverHolds = false
        // The last downbeat that leaves the end card time to hold.
        func lastDownbeat(before t: Double) -> Double {
            downbeats.last(where: { $0 <= t + 0.01 && $0 > introEnd + bar * 1.5 }) ?? t
        }
        /// A card's time to leave: by its voice, varied a little by Feel.
        func leaving(_ c: Int, base: Double) -> Double {
            base * (1 + 0.3 * feel * (unit(c, 0xF3) * 2 - 1))
        }
        let reverseOrder = landingOrder.reversed().map { $0 }
        switch kind {
        case .loop:
            outroStart = max(introEnd + bar, length - introEnd)
        case .close:
            outroEnd = lastDownbeat(before: length - max(bar, 1.5))
            outroStart = max(introEnd + bar, outroEnd - bar)
            let span = max(outroEnd - flight - q - (outroStart + bar * 0.25), 0)
            for (i, c) in reverseOrder.enumerated() {
                let k = reverseOrder.count > 1 ? Double(i) / Double(reverseOrder.count - 1) : 0
                leaves[c] = outroStart + bar * 0.25 + (span / q * k).rounded(.down) * q
                rank[c] = i
            }
            coverRise = outroEnd - flight
            coverHolds = true
        case .lightsOut:
            outroEnd = lastDownbeat(before: length - bar)
            outroStart = max(introEnd + bar, outroEnd - bar)
            let step = max(min(q, (outroEnd - outroStart) / Double(max(reverseOrder.count, 1))), 0.03)
            for (i, c) in reverseOrder.enumerated() {
                leaves[c] = outroEnd - Double(reverseOrder.count - i) * step
                rank[c] = i
            }
        case .leave:
            // The board empties the way it filled: the last to land leaves first, one slot a beat,
            // counted back from the clip's last beat, which takes the cover. A board that was dealt
            // empties in scattered order. With a cold open the cover stays and rises to meet frame 0.
            let departing = builds ? reverseOrder : Self.scatterOrder(layout, seed: s.seed).filter { $0 != cover }
            let m = departing.count
            let total = position(length)
            // The last beat with room after it for the cover to go.
            let lastBeat = position(length - period * 0.5).rounded(.down)
            let budget = min(16, max(4, (total - position(introEnd)) * 0.3))
            var stepOut = 0.25
            let options = builds && buildStep > 0 ? [buildStep] + [1.0, 0.5, 0.25].filter { $0 < buildStep } : [1.0, 0.5, 0.25]
            for f in options where Double(m) * f <= budget + 1e-6 {
                stepOut = f
                break
            }
            let slotsOut = max(1, min(m, Int((budget / stepOut + 1e-6).rounded(.down))))
            for (j, c) in departing.enumerated() {
                let slot = j * slotsOut / max(m, 1)
                let x = lastBeat - Double(slotsOut - slot) * stepOut
                leaves[c] = time(x) + 0.02 * feel * (unit(c, 0xF4) * 2 - 1)
                rank[c] = j
            }
            if s.intro.coldOpen {
                coverHolds = true
                coverRise = time(lastBeat) - flight
            } else {
                leaves[cover] = time(lastBeat)
                rank[cover] = m
            }
            for c in 0..<n {
                let share = voices[c] == .low ? 0.75 : (voices[c] == .mid ? 0.5 : 1.0 / 3)
                outFlights[c] = leaving(c, base: min(max(period * share, 0.18), 0.45))
            }
            outroStart = max(introEnd + bar * 0.5, (departing.map { leaves[$0] }.min() ?? length) - period)
        case .curtainCall:
            // A bow in a wave from the middle out over the second-last bar, one ring a beat; then
            // in the last bar each slide leaves downwards in its own time, slowing like a
            // ritardando. The cover rises to the front and takes the last bow on the final downbeat.
            outroEnd = lastDownbeat(before: length - max(bar, 1.5))
            outroStart = max(introEnd + bar, outroEnd - 2 * bar)
            let rings = min(4, max(1, Int(((outroEnd - bar - outroStart) / period).rounded())))
            let d = layout.distances(from: layout.cells[layout.centreCell].centre)
            for c in 0..<n where c != cover {
                bows[c] = time(position(outroStart) + Double(max(0, min(rings - 1, Int(d[c] * Float(rings) - 1e-3)))))
            }
            bows[cover] = outroEnd
            // Bottom rows first, so a card leaving never drops across one still resting.
            let departing = (0..<n).filter { $0 != cover }.sorted {
                let a = layout.cells[$0].centre.y + Float(unit($0, 0xF5)) * layout.gap, b = layout.cells[$1].centre.y + Float(unit($1, 0xF5)) * layout.gap
                return a != b ? a < b : $0 < $1
            }
            let m = departing.count
            let from = outroEnd - bar, span = max(bar - 0.75, bar * 0.5)
            for (j, c) in departing.enumerated() {
                let k = m > 1 ? Double(j) / Double(m - 1) : 0
                leaves[c] = from + span * pow(k, 1.5) + 0.025 * feel * (unit(c, 0xF6) * 2 - 1)
                outFlights[c] = leaving(c, base: min(max(period * 1.2, 0.5), 0.8))
                rank[c] = j
            }
            coverRise = outroEnd - bar
            coverHolds = true
        case .driftAway:
            // Over the last two to four bars the slides lift away one by one, outside in, close
            // together at first and further apart, like a breath out. The cover rises to the middle
            // and stays, glowing.
            let barsAway = n <= 12 ? 2 : (n <= 30 ? 3 : 4)
            let target = length - Double(barsAway) * bar
            outroStart = max(introEnd + bar, downbeats.min { abs($0 - target) < abs($1 - target) }.flatMap { abs($0 - target) < bar ? $0 : nil } ?? target)
            outroEnd = length
            let departing = (0..<n).filter { $0 != cover }.sorted {
                let d0 = simdLength(layout.cells[$0].centre - layout.cells[cover].centre) + Float(unit($0, 0xF7)) * layout.gap * 2
                let d1 = simdLength(layout.cells[$1].centre - layout.cells[cover].centre) + Float(unit($1, 0xF7)) * layout.gap * 2
                return d0 != d1 ? d0 > d1 : $0 < $1
            }
            let m = departing.count
            let last = max(outroStart, length - bar - 1.2)
            for (j, c) in departing.enumerated() {
                let k = m > 1 ? Double(j) / Double(m - 1) : 0
                leaves[c] = outroStart + (last - outroStart) * pow(k, 1.7)
                outFlights[c] = 1.8 + 0.8 * unit(c, 0xF8)
                rank[c] = j
            }
            coverRise = outroStart + (last - outroStart) * 0.55
            coverHolds = true
        default:
            break
        }
        let outro = OutroPlan(kind: kind, start: outroStart, leaves: leaves, flight: flight, flights: outFlights, bows: bows, rank: rank,
                              coverRise: coverRise, end: outroEnd, fade: max(q * 2, 0.12), coverHolds: coverHolds)

        // MARK: Drops and the mode's gain over the clip
        var drops = s.drops ? song.drops.map { $0 - start }.filter { $0 > introEnd + bar * 0.5 && $0 < outroStart - period } : []
        // A build that lands on the song's drop hits it like any other drop.
        if s.drops, let d = buildDrop { drops.insert(d, at: 0) }
        // What each drop does. A weave needs the whole bar before it clear of
        // the intro; a shape needs to be home a bar later (two, for a quick
        // bar) before the ending or the next drop. Otherwise it lights.
        var moments: [DropMoment] = []
        for (i, d) in drops.enumerated() {
            var move = s.dropMove
            let flyOut = min(max(period * 0.9, 0.3), 0.6), flyHome = flyOut * 1.15
            var home = d + period
            let next = i + 1 < drops.count ? drops[i + 1] : Double.infinity
            if move != .light, d - bar < introEnd + 0.05 { move = .light }
            if move.reforms {
                let target = d + Double(bar >= 1.8 ? 1 : 2) * bar
                home = downbeats.first(where: { $0 > target - period * 0.5 }) ?? target
                if home + period * 2 > outroStart || home + period > next - bar { move = .light }
            }
            let window: (Double, Double)
            switch move {
            case .light: window = (d - period, d + period)
            case .weave: window = (d - bar, d + period * 2)
            default: window = (d - bar, home + period)
            }
            if move.reforms == false { home = d + period }
            moments.append(DropMoment(time: d, move: move, flyOut: flyOut, flyHome: flyHome, home: home, start: window.0, end: window.1))
        }
        func modeGain(_ t: Double) -> Float {
            var g: Float = 1
            if builds {
                // A build hands over to the music on its last landing, over a beat.
                if t < introEnd - 0.02 { return 0 }
                g = min(1, Float((t - introEnd + 0.02) / max(period, 0.2)))
            } else {
                let rampIn = introEnd * 0.25
                if t < introEnd - rampIn { return 0 }
                if t < introEnd { g = Float((t - (introEnd - rampIn)) / max(rampIn, 1e-3)) }
            }
            if kind != .none, t > outroStart {
                g *= max(0, 1 - Float((t - outroStart) / (kind.loops ? bar : bar * 0.5)))
            }
            // Through the breath before a drop, less happens.
            for d in drops where t < d && t > d - bar { g *= 0.6 }
            return g
        }

        // MARK: Mode
        var cellsTriggers = [[Trigger]](repeating: [], count: n)
        var lastLit = [Double](repeating: -100, count: n)
        let tieBreak = (0..<n).map { _ in rng.unit() }
        func add(_ c: Int, _ t: Double, _ a: Float, hold: Double? = nil, release r: Double? = nil, glint: Bool = false, lean: SIMD2<Float> = .zero) {
            guard a > 0.01, c >= 0, c < n else { return }
            cellsTriggers[c].append(Trigger(time: t, amp: min(a, 1), hold: hold ?? holdTime, release: r ?? release, glint: glint, lean: lean))
            if !glint { lastLit[c] = t }
        }
        let registers: Set<Register> = {
            switch s.listen {
            case .everything: return [.low, .mid, .high]
            case .drums: return [.low, .high]
            case .bass: return [.low]
            case .melody: return [.mid]
            }
        }()
        let modeFrom = builds ? introEnd - 0.02 : introEnd * 0.7
        let modeOnsets = onsets.filter { registers.contains($0.register) && $0.time > modeFrom && $0.time < length }
        let threshold: Float = 0.55 - 0.45 * S

        /// The least recently lit cells, spread apart: farthest-point picks.
        func pick(_ k: Int, at t: Double, among pool: [Int]? = nil, avoid recent: Double = 0) -> [Int] {
            let candidates = (pool ?? Array(0..<n)).filter { t - lastLit[$0] > recent }
            guard !candidates.isEmpty, k > 0 else { return [] }
            let ordered = candidates.sorted { (lastLit[$0], tieBreak[$0]) < (lastLit[$1], tieBreak[$1]) }
            var remaining = Array(ordered.prefix(max(k * 2, Int((Double(n) * 0.3).rounded(.up)))))
            var chosen = [remaining.removeFirst()]
            // Each candidate's distance to the nearest cell chosen so far.
            var nearest = remaining.map { simdLength(layout.cells[$0].centre - layout.cells[chosen[0]].centre) }
            while chosen.count < k, !remaining.isEmpty {
                var best = 0, bestD: Float = -1
                for j in remaining.indices {
                    // Waiting longer counts a little, so spacing never starves a cell.
                    let score = nearest[j] + Float(j == 0 ? 0.02 : 0)
                    if score > bestD { bestD = score; best = j }
                }
                let c = remaining.remove(at: best)
                nearest.remove(at: best)
                chosen.append(c)
                let at = layout.cells[c].centre
                for j in remaining.indices { nearest[j] = min(nearest[j], simdLength(layout.cells[remaining[j]].centre - at)) }
            }
            return chosen
        }

        let modeBeats = clipBeats.map { (b: $0, t: $0.time - start) }.filter { $0.t > modeFrom && $0.t < length }
        let barIndex: (Double) -> Int = { t in Int(((t - firstDown) / bar).rounded(.down)) }

        switch s.mode {
        case .pulse:
            let density = 0.04 + 0.16 * S
            for (b, t) in modeBeats {
                let l = loudness(t)
                let g = modeGain(t)
                guard g > 0.01, l > 0.1 || b.strength > 0.2 else { continue }
                let amp = (0.45 + 0.55 * min(1, 0.6 * b.strength + 0.4 * l)) * g
                var k = Int((Float(n) * density * (0.5 + l)).rounded())
                if b.isDownbeat { k = Int((Float(k) * 1.75).rounded()) }
                k = min(max(k, 1), max(1, Int(Float(n) * 0.4)))
                if b.isDownbeat, n >= 6 {
                    // A shape on each downbeat, on a four-bar cycle.
                    let shape = ((barIndex(t) % 4) + 4) % 4
                    var cells: [Int] = []
                    switch shape {
                    case 0 where layout.rows > 1:
                        let row = (0..<layout.rows).min { r1, r2 in
                            avgLast(layout, lastLit, row: r1) < avgLast(layout, lastLit, row: r2)
                        } ?? 0
                        cells = layout.cells.filter { $0.row == row }.map(\.index)
                    case 1 where layout.columns > 1:
                        let col = (0..<layout.columns).min { c1, c2 in
                            avgLast(layout, lastLit, column: c1) < avgLast(layout, lastLit, column: c2)
                        } ?? 0
                        cells = layout.cells.filter { $0.column == col }.map(\.index)
                    case 2:
                        let span = layout.rows + layout.columns - 1
                        let k0 = Int(rng.next() % UInt64(max(span, 1)))
                        let flip = rng.unit() < 0.5
                        cells = layout.cells.filter { (flip ? $0.row + $0.column : $0.row + layout.columns - 1 - $0.column) == k0 }.map(\.index)
                        if cells.count < 2 { cells = pick(k, at: t) }
                    default:
                        cells = pick(k, at: t)
                    }
                    for c in cells { add(c, t, max(amp, 0.85 * g)) }
                } else {
                    for c in pick(k, at: t, avoid: period * 0.9) { add(c, t, amp) }
                }
            }
            // Kicks off the beat light one more; hats glint.
            var lastGlint = -10.0
            for o in modeOnsets {
                let g = modeGain(o.time)
                guard g > 0.01 else { continue }
                let onBeat = modeBeats.contains { abs($0.t - o.time) < 0.07 }
                if o.register == .low, !onBeat, o.strength >= threshold {
                    for c in pick(1, at: o.time, avoid: period) { add(c, o.time, (0.35 + 0.4 * o.strength) * g) }
                } else if o.register == .high, o.strength >= threshold * 0.8, o.time - lastGlint >= period / 2 {
                    lastGlint = o.time
                    for c in pick(1, at: o.time, avoid: period * 0.5) {
                        add(c, o.time, (0.25 + 0.15 * o.strength) * g, hold: 0.05, release: 0.15, glint: true)
                    }
                }
            }

        case .ripple:
            let cross = min(max(period * Double(s.spread), 0.25), 0.9)
            let centre = layout.cells[layout.centreCell].centre
            var rings: [Double] = []
            var events: [(t: Double, origin: Int?, amp: Float)] = []
            // Kicks start the big rings, snares the small ones; each at most
            // once in its own stretch, so the wall reads as waves, not a wash.
            var lastLow = -10.0, lastMid = -10.0
            for o in modeOnsets where o.strength >= max(threshold, 0.35) {
                if o.register == .low, o.time - lastLow >= period * 0.9 {
                    lastLow = o.time
                    events.append((o.time, nil, 0.5 + 0.5 * o.strength))
                }
                if o.register == .mid, o.strength >= max(0.6, threshold + 0.25), o.time - lastMid >= period * 1.9 {
                    lastMid = o.time
                    events.append((o.time, -1, 0.7 * (0.5 + 0.5 * o.strength)))
                }
            }
            // Downbeats always send a ring, so music without a kick still moves.
            for (b, t) in modeBeats where b.isDownbeat && !events.contains(where: { $0.origin == nil && abs($0.t - t) < 0.08 }) {
                if loudness(t) > 0.12 { events.append((t, nil, 0.6)) }
            }
            events.sort { $0.t < $1.t }
            for e in events {
                let g = modeGain(e.t)
                guard g > 0.01 else { continue }
                rings = rings.filter { e.t - $0 < cross }
                guard rings.count < 2, rings.allSatisfy({ e.t - $0 >= 0.15 }) else { continue }
                rings.append(e.t)
                let originCell = e.origin == nil ? layout.centreCell : (pick(1, at: e.t, avoid: period).first ?? layout.centreCell)
                let origin = e.origin == nil ? centre : layout.cells[originCell].centre
                let d = layout.distances(from: origin)
                // The ring meets each distance in turn, evenly spaced, so on a
                // small grid it steps outwards on a steady pulse.
                var steps: [Float] = []
                for x in d.sorted() where steps.last.map({ x - $0 > 1e-3 }) ?? true { steps.append(x) }
                let arrive = d.map { x in
                    Double(steps.firstIndex { abs($0 - x) <= 1e-3 } ?? 0) / Double(max(steps.count - 1, 1)) * cross
                }
                let amps = d.map { e.amp * (1 - 0.35 * $0) * g }
                // A short tail, so each ring reads as a moving band, not a filled
                // disc, and no thicker than keeps 40 % of the grid lit at most.
                var hold = min(holdTime, cross / 4), tail = min(release, cross / 2)
                let cap = max(1, Int(Float(n) * 0.4))
                let times = layout.cells.indices.filter { amps[$0] > 0.5 }.map { arrive[$0] }.sorted()
                if times.count > cap {
                    var band = Double.infinity
                    for k in 0..<(times.count - cap) { band = min(band, times[k + cap] - times[k]) }
                    // Light passes half a little before its trigger; ln 2 / 3 of the tail is still above half.
                    band -= max(s.motion.attack, 0.001) * 0.7 + 0.005
                    if hold + tail * 0.231 > band {
                        hold = max(0, min(hold, band * 0.4))
                        tail = max(0.02, (band - hold) / 0.231)
                    }
                }
                for c in layout.cells {
                    let away = c.centre - origin
                    let len = simdLength(away)
                    add(c.index, e.t + arrive[c.index], amps[c.index], hold: hold, release: tail, lean: len > 1e-5 ? away / len : .zero)
                }
            }

        case .equaliser:
            break

        case .voices:
            // Each onset lights the next slides of its own voice, in the order they landed, so a
            // group walks rather than flashing as one: a kick one to three (half the low group
            // on a loud downbeat), a snare one or two, a hat a glint.
            var groups: [Register: [Int]] = [:]
            for c in intro.order { groups[intro.voices[c], default: []].append(c) }
            var pointer: [Register: Int] = [:]
            func next(_ r: Register, _ k: Int, at t: Double, avoid: Double) -> [Int] {
                guard let pool = groups[r], !pool.isEmpty else { return pick(k, at: t, avoid: avoid) }
                var out: [Int] = []
                var p = pointer[r] ?? 0
                var tried = 0
                while out.count < k, tried < pool.count {
                    let c = pool[p % pool.count]
                    p += 1
                    tried += 1
                    if t - lastLit[c] > avoid { out.append(c) }
                }
                pointer[r] = p
                return out
            }
            var lastGlint = -10.0
            for o in modeOnsets where o.strength >= threshold {
                let g = modeGain(o.time)
                guard g > 0.01 else { continue }
                switch o.register {
                case .low:
                    let loudDown = o.strength > 0.6 && loudness(o.time) > 0.55 && downbeats.contains { abs($0 - o.time) < 0.07 }
                    let k = loudDown ? max(1, (groups[.low]?.count ?? 2) / 2) : min(3, 1 + Int(o.strength * 2.2))
                    for c in next(.low, k, at: o.time, avoid: period * 0.45) { add(c, o.time, (0.55 + 0.45 * o.strength) * g) }
                case .mid:
                    for c in next(.mid, o.strength > 0.7 ? 2 : 1, at: o.time, avoid: period * 0.45) {
                        // A snare slide flicks away from the middle.
                        let away = layout.cells[c].centre - layout.safeCentre
                        let lean = SIMD2<Float>(away.x >= 0 ? 1 : -1, 0)
                        add(c, o.time, (0.5 + 0.45 * o.strength) * g, lean: lean)
                    }
                case .high:
                    guard o.time - lastGlint >= period / 2 else { continue }
                    lastGlint = o.time
                    for c in next(.high, 1, at: o.time, avoid: period * 0.5) {
                        add(c, o.time, (0.3 + 0.2 * o.strength) * g, hold: 0.05, release: 0.18, glint: true)
                    }
                }
            }

        case .readThrough:
            // One pass of the deck fills a four-bar phrase: the longest of a
            // beat, a half or a quarter that fits, never quicker than 110 ms.
            var stepBeats = s.step
            if stepBeats <= 0 {
                stepBeats = 0.25
                for f in [1.0, 0.5, 0.25] where Double(n) * f <= 16 + 1e-6 { stepBeats = f; break }
            }
            let stepTime = max(stepBeats * period, 0.11)
            let trail = stepTime * 1.5 * max(0.25, s.motion.release)
            let spare = max(0, Int(((16 * period) / stepTime + 1e-6).rounded(.down)) - n)
            // Reading order: across, then down; a spare slot at the end of a pass lights the whole grid.
            var k = 0
            var t = modeBeats.first(where: { $0.t >= introEnd - 0.02 })?.t ?? introEnd
            while t < length {
                let g = modeGain(t)
                let slot = spare > 0 ? k % (n + spare) : k % n
                if slot < n {
                    let near = modeOnsets.filter { abs($0.time - t) < 0.1 }.map(\.strength).max() ?? strength(at: t)
                    let onDownbeat = downbeats.contains(where: { abs($0 - t) < 0.03 })
                    let amp = (onDownbeat ? 1 : 0.6 + 0.4 * min(1, near)) * g
                    add(slot, t, amp, hold: stepTime * 0.25, release: trail)
                } else if slot == n {
                    for c in 0..<n { add(c, t, 0.5 * g, hold: 0, release: stepTime * 2) }
                }
                k += 1
                // Follow the tracked beats where they are, so the walk stays in time.
                let next = t + stepTime
                t = beatTimes.min(by: { abs($0 - next) < abs($1 - next) }).flatMap { abs($0 - next) < stepTime * 0.3 ? $0 : nil } ?? next
            }

        case .lightsOn:
            let low = layout.cells.filter { Float($0.row) >= Float(layout.rows) * 0.4 - 0.01 }.map(\.index)
            let middle = layout.cells.filter { Float($0.row) >= Float(layout.rows) * 0.2 - 0.01 && Float($0.row) < Float(layout.rows) * 0.8 }.map(\.index)
            let top = layout.cells.filter { Float($0.row) < Float(layout.rows) * 0.4 + 0.01 }.map(\.index)
            let cap = n < 24 ? 2 : n
            let tail = n < 24 ? release * 1.5 : release
            for o in modeOnsets where o.strength >= threshold * 0.8 {
                let g = modeGain(o.time)
                guard g > 0.01 else { continue }
                let s2 = o.strength * o.strength
                switch o.register {
                case .low:
                    let k = min(cap, max(1, Int((0.15 * Float(n) * s2).rounded())))
                    for c in pick(k, at: o.time, among: low, avoid: period) { add(c, o.time, (0.55 + 0.45 * o.strength) * g, release: tail) }
                case .mid:
                    let k = min(cap, Int((0.10 * Float(n) * s2).rounded()))
                    for c in pick(k, at: o.time, among: middle, avoid: period) { add(c, o.time, (0.55 + 0.45 * o.strength) * g, release: tail) }
                case .high:
                    let k = min(cap, max(1, Int((0.04 * Float(n) * s2).rounded())))
                    for c in pick(k, at: o.time, among: top, avoid: period * 0.5) {
                        add(c, o.time, (0.3 + 0.2 * o.strength) * g, hold: 0.04, release: 0.2, glint: true)
                    }
                }
            }
        }

        // MARK: Restraint: outside the intro and drops, at most 40 % of the grid lit at once.
        if s.mode != .equaliser, n >= 3 {
            let cap = max(1, Int(Float(n) * 0.4))
            var all: [(c: Int, k: Int)] = []
            for c in 0..<n { for (k, g) in cellsTriggers[c].enumerated() where !g.glint { all.append((c, k)) } }
            func trigger(_ e: (c: Int, k: Int)) -> Trigger { cellsTriggers[e.c][e.k] }
            // Same moment: the strongest first, so the weakest are the ones dropped.
            all.sort {
                let a = trigger($0), b = trigger($1)
                return a.time != b.time ? a.time < b.time : (a.amp != b.amp ? a.amp > b.amp : $0.c < $1.c)
            }
            var litUntil = [Double](repeating: -100, count: n)
            var dropped = cellsTriggers.map { [Bool](repeating: false, count: $0.count) }
            var anyDropped = false
            // Cells above half, counted as they come up and as they fall back
            // (oldest first off a heap; entries a later trigger outlasted are skipped).
            var lit = 0
            var falling = Expiries()
            var stamp = [Int](repeating: -1, count: n)
            // The light is past half a little before its trigger, so a cell counts from there.
            // (Voices lights more at once, so it counts from where a full-strength light passes half.)
            let lead = max(s.motion.attack, 0.001) * (s.mode == .voices ? 0.9 : 0.7)
            var i = 0
            while i < all.count {
                // A ripple's ring reaches cells at one distance together: all of
                // them light or none do, so the ring stays round.
                var j = i + 1
                if s.mode == .ripple {
                    let first = trigger(all[i])
                    while j < all.count, abs(trigger(all[j]).time - first.time) < 0.002, abs(trigger(all[j]).amp - first.amp) < 0.02 { j += 1 }
                }
                let group = all[i..<j]
                let from = trigger(all[i]).time - lead
                while let e = falling.first, e.until <= from {
                    falling.removeFirst()
                    if litUntil[e.cell] == e.until { lit -= 1 }
                }
                var litMembers = 0, fresh = 0
                for e in group {
                    let up = litUntil[e.c] > from
                    if up, stamp[e.c] != i { litMembers += 1 }
                    stamp[e.c] = i
                    if !up, trigger(e).amp > 0.5 { fresh += 1 }
                }
                let busy = lit - litMembers
                if busy >= cap || busy + fresh > cap {
                    for e in group where litUntil[e.c] <= from && trigger(e).amp > 0 {
                        dropped[e.c][e.k] = true
                        anyDropped = true
                    }
                } else {
                    // Above half until the envelope has fallen by half.
                    for e in group {
                        let g = trigger(e)
                        guard g.amp > 0.5 else { continue }
                        let until = g.time + g.hold + g.release * Double(log(2 * g.amp)) / 3
                        guard until > litUntil[e.c] else { continue }
                        if litUntil[e.c] <= from { lit += 1 }
                        litUntil[e.c] = until
                        falling.insert(until: until, cell: e.c)
                    }
                }
                i = j
            }
            if anyDropped {
                for c in 0..<n where dropped[c].contains(true) {
                    cellsTriggers[c] = cellsTriggers[c].indices.filter { !dropped[c][$0] }.map { cellsTriggers[c][$0] }
                }
            }
        }

        // MARK: The intro lights each card as it lands; drops light everything.
        if builds {
            // Echoes: once a slide has landed, later sounds in its voice light it again, gently.
            // The pattern of the song becomes the pattern of the board as it grows.
            var lastEcho: [Register: Double] = [:]
            var echoed = [Double](repeating: -100, count: n)
            for o in onsets where o.time > buildStart && o.time < introEnd - 0.05 && o.strength >= threshold * 0.9 {
                guard o.time - (lastEcho[o.register] ?? -10) >= period * 0.45 else { continue }
                let group = (0..<n).filter { voices[$0] == o.register && landings[$0] < o.time - 0.08 && !(s.intro.coldOpen && $0 == cover) }
                guard !group.isEmpty else { continue }
                lastEcho[o.register] = o.time
                let k = max(1, Int((Double(group.count) * 0.3).rounded()))
                for c in group.sorted(by: { (echoed[$0], landings[$0]) < (echoed[$1], landings[$1]) }).prefix(k) {
                    echoed[c] = o.time
                    if o.register == .high {
                        add(c, o.time, 0.25 + 0.2 * o.strength, hold: 0.04, release: 0.16, glint: true)
                    } else {
                        add(c, o.time, 0.3 + 0.25 * o.strength, hold: 0, release: release * 0.6)
                    }
                }
            }
        }
        for c in 0..<n {
            // The cover lands last and fullest: the music takes over from it.
            add(c, landings[c], (s.intro.coldOpen || builds) && c == cover ? 1 : 0.8)
            // Then the whole grid takes a breath of light as the mode starts.
            if c != cover || !s.intro.coldOpen, introEnd - landings[c] > 0.05 { add(c, introEnd, 0.5) }
        }
        // Each slide lights as it leaves on its beat, and as it bows.
        switch kind {
        case .leave:
            for c in 0..<n where outro.leaves[c] < length { add(c, outro.leaves[c], 0.6, hold: 0, release: release * 0.7) }
        case .curtainCall:
            for c in 0..<n where outro.bows[c] > 0 { add(c, outro.bows[c], c == cover ? 1 : 0.55, hold: period * 0.25, release: release) }
        default:
            break
        }
        let dropOrder = layout.distances(from: layout.cells[layout.centreCell].centre)
        for d in drops {
            for c in 0..<n {
                add(c, d + Double(dropOrder[c]) * sixteenth * 2, 1, hold: period * 0.5, release: release * 1.5)
            }
        }
        // A grid coming home lands lit, on the downbeat.
        for m in moments where m.move.reforms {
            for c in 0..<n { add(c, m.home, 0.75, hold: period * 0.25, release: release) }
        }
        for c in 0..<n { cellsTriggers[c].sort { $0.time < $1.time } }

        // MARK: Equaliser levels
        var levels: [[Float]] = []
        var peaks: [[Float]] = []
        if s.mode == .equaliser {
            let cols = layout.columns
            let rows = Float(layout.rows)
            let gate = 0.32 - 0.22 * S
            let up = Float(1 - exp(-1 / (0.03 * BeatPlan.rate))), down = Float(1 - exp(-1 / (0.22 * BeatPlan.rate)))
            for j in 0..<cols {
                let position = cols == 1 ? 0.5 : Float(j) / Float(cols - 1) * 0.94 + 0.03
                var e: Float = 0, peak: Float = 0, held = 0.0
                var level = [Float](repeating: 0, count: frames), top = [Float](repeating: 0, count: frames)
                for f in 0..<frames {
                    let t = Double(f) / BeatPlan.rate
                    let x = song.spectrum(at: position, time: start + t)
                    let v = smoothstep(gate, 0.95, x) * modeGain(t)
                    e += (v - e) * (v > e ? up : down)
                    let fill = e * rows
                    // The peak holds a beat, then falls a row every eighth note.
                    if fill >= peak { peak = fill; held = period } else if held > 0 { held -= 1 / BeatPlan.rate } else {
                        peak = max(fill, peak - Float(1 / (period / 2) / BeatPlan.rate))
                    }
                    level[f] = fill
                    top[f] = peak
                }
                levels.append(level)
                peaks.append(top)
            }
        }

        // MARK: Feature moments
        var features: [FeatureMoment] = []
        // Deck order after the cover; starred slides come round twice as often.
        let deckOrder = (0..<slideCount).map { ($0 + coverSlide + 1) % slideCount }
        let stars = deckOrder.filter { starred.contains($0) }
        var featureQueue: [Int] = []
        for (i, slide) in deckOrder.enumerated() {
            featureQueue.append(slide)
            if !stars.isEmpty, i % 2 == 1 { featureQueue.append(stars[(i / 2) % stars.count]) }
        }
        var nextFeature = 0
        let every = s.spotlight && s.feature == .off ? 2 : s.feature.rawValue
        if every > 0, n > 1 || slideCount > 1 {
            var k = introBars + every
            while true {
                let d = downbeat(barsAfterFirst: k)
                k += every
                if d > length { break }
                let liftOff = d - period * 0.5
                let holdUntil = s.spotlight ? max(d + Double(every) * bar - period, d + 1.8) : d + (bar < 1.8 ? bar * 2 : bar)
                let end = holdUntil + period * 0.5
                guard liftOff > introEnd + 0.05, end < outroStart - 0.1 else { if d > outroStart { break } else { continue } }
                if moments.contains(where: { liftOff < $0.end && end > $0.start }) { continue }
                features.append(FeatureMoment(slide: featureQueue[nextFeature % featureQueue.count], cell: nil, liftOff: liftOff,
                                              land: d, leave: holdUntil, end: end))
                nextFeature += 1
            }
        }

        // MARK: Turning cells over to the slides not on the grid
        var swaps = [[Swap]](repeating: [], count: n)
        let flipTime = max(0.28, period / 2)
        if slideCount > n, s.grid.rotate {
            var queue = (0..<slideCount).filter { !first.contains($0) } // the slides not yet seen
            var showing = first
            var lastSwap = [Double](repeating: -100, count: n)
            var k = introBars + 1
            // Enough each bar that every slide has shown by halfway through.
            let clipBars = max(1, Int(((outroStart - introEnd) / bar).rounded(.down)))
            let perBar = min(max(1, Int((2 * Double(slideCount - n) / Double(clipBars)).rounded(.up))), max(1, n / 4))
            while true {
                let d = downbeat(barsAfterFirst: k)
                k += 1
                guard d < outroStart - bar else { break }
                // A weave or a shape keeps every card as it is until it is home.
                if moments.contains(where: { $0.move != .light && d > $0.start - bar * 0.5 && d < $0.end + flipTime }) { continue }
                let count = min(perBar, slideCount - n)
                // A slide out front comes back to the card it left, and is not dealt onto another meanwhile.
                let featured = Set(features.filter { $0.liftOff < d + 1 && $0.end > d - 0.2 }.map(\.slide))
                // Resting cells only, the longest unchanged first. The cover stays
                // put: the clip begins and ends on it.
                let resting = (0..<n).filter { c in
                    c != cover && !featured.contains(showing[c]) &&
                        !cellsTriggers[c].contains { !$0.glint && $0.amp > 0.3 && $0.time > d - release * 0.6 && $0.time < d + flipTime + 0.4 }
                }.sorted { (lastSwap[$0], tieBreak[$0]) < (lastSwap[$1], tieBreak[$1]) }
                for (i, c) in resting.prefix(count).enumerated() {
                    if queue.isEmpty { queue = Array(0..<slideCount).filter { !showing.contains($0) } }
                    guard let pick = queue.firstIndex(where: { !featured.contains($0) }) else { break }
                    let next = queue.remove(at: pick)
                    queue.append(showing[c])
                    let t = d + Double(i) * sixteenth + flipTime / 2
                    swaps[c].append(Swap(time: t, slide: next))
                    showing[c] = next
                    lastSwap[c] = t
                }
            }
        }
        // A featured slide that is on the grid steps out of its own cell; when
        // a small deck shows it twice, out of the copy nearest the middle.
        for i in features.indices {
            let f = features[i]
            features[i].cell = (0..<n).filter { c in
                var slide = first[c]
                for w in swaps[c] where w.time <= f.liftOff { slide = w.slide }
                return slide == f.slide && !swaps[c].contains { $0.time > f.liftOff - 1 && $0.time < f.end + flipTime }
            }.min { (simdLength(layout.cells[$0].centre), $0) < (simdLength(layout.cells[$1].centre), $1) }
        }

        // MARK: Camera punches: loud downbeats, harder on drops
        var punches: [(time: Double, amount: Float)] = []
        for d in downbeats where d > introEnd + 0.1 && d < outroStart {
            var mean: Float = 0
            for k in 0..<8 { mean += loudness(d + bar * Double(k) / 8) }
            mean /= 8
            if mean > 0.6 { punches.append((d, 0.015)) }
        }
        // A kick landing in a build gives the camera a little push, so you feel it land.
        if builds { for c in 0..<n where c != cover && voices[c] == .low { punches.append((landings[c], 0.006)) } }
        for d in drops { punches.removeAll { abs($0.time - d) < 0.1 }; punches.append((d, 0.03)) }
        for m in moments where m.move.reforms { punches.removeAll { abs($0.time - m.home) < 0.1 }; punches.append((m.home, 0.02)) }
        punches.sort { $0.time < $1.time }

        let reach = max(release, (cellsTriggers.flatMap { $0 }.map(\.release).max() ?? release)) * 1.6 +
            (cellsTriggers.flatMap { $0 }.map(\.hold).max() ?? 0)
        return BeatPlan(start: start, length: length, period: period, cells: n, slides: slideCount, triggers: cellsTriggers,
                        reach: reach, attack: max(s.motion.attack, 0.001), features: features, firstSlide: first, swaps: swaps,
                        flipTime: flipTime, levels: levels, peaks: peaks, drops: drops, moments: moments, punches: punches, pulse: pulse, loud: loud,
                        intro: intro, outro: outro, beats: beatTimes, downbeats: downbeats)
    }

    /// Bars for a build of `cells` cards with a slide on every beat after the first: two to eight.
    public static func buildBars(cells: Int) -> Int {
        min(max(Int((Double(cells + 1) / 4).rounded(.up)), 2), 8)
    }

    /// When each cell lands in the intro, as a rank 0 (first) … 1 (last).
    static func staggerRanks(_ layout: GridLayout, order: StaggerOrder, rng: inout Seeded) -> [Float] {
        let n = layout.count
        guard n > 1 else { return [0] }
        var raw: [Float]
        switch order {
        case .reading: raw = layout.cells.map { Float($0.index) }
        case .rows: raw = layout.cells.map { Float($0.row) }
        case .columns: raw = layout.cells.map { Float($0.column) }
        case .diagonal: raw = layout.cells.map { Float($0.row + $0.column) }
        case .centreOut:
            let d = layout.distances(from: .zero)
            // Rings: cells at nearly the same distance land together.
            raw = d.map { ($0 * 8).rounded() }
        case .spiral:
            raw = layout.cells.map { c in
                let a = atan2f(c.centre.y, c.centre.x)
                let r = simdLength(c.centre) / max(simdLength(layout.gridSize / 2), 1e-5)
                return r * 3 + (a + .pi) / (2 * .pi) * 0.999
            }
        case .random:
            let perm = rng.shuffled(n)
            raw = perm.map { Float($0) }
        case .scatter:
            let order = scatterOrder(layout, seed: UInt32(truncatingIfNeeded: rng.next()))
            raw = [Float](repeating: 0, count: n)
            for (i, c) in order.enumerated() { raw[c] = Float(i) }
        }
        let lo = raw.min() ?? 0, hi = raw.max() ?? 1
        return raw.map { hi > lo ? ($0 - lo) / (hi - lo) : 0 }
    }

    /// The cells in a scattered order: each as far as it can be from those before it and from
    /// the one just placed, from a seeded start, so the board fills evenly at every moment
    /// and never in reading order.
    static func scatterOrder(_ layout: GridLayout, seed: UInt32) -> [Int] {
        let n = layout.count
        guard n > 1 else { return Array(0..<n) }
        var rng = Seeded(seed, salt: 0x5CA7)
        let centres = layout.cells.map(\.centre)
        let diagonal = max(simdLength(layout.gridSize), 1e-5)
        var remaining = Array(0..<n)
        var order = [remaining.remove(at: Int(rng.next() % UInt64(n)))]
        var nearest = remaining.map { simdLength(centres[$0] - centres[order[0]]) }
        let jitter = (0..<n).map { _ in rng.unit() * 0.05 }
        while !remaining.isEmpty {
            let last = centres[order[order.count - 1]]
            var best = 0, bestScore: Float = -1
            for j in remaining.indices {
                let c = remaining[j]
                let score = (nearest[j] + 0.6 * simdLength(centres[c] - last)) / diagonal + jitter[c]
                if score > bestScore { bestScore = score; best = j }
            }
            let c = remaining.remove(at: best)
            nearest.remove(at: best)
            order.append(c)
            for j in remaining.indices { nearest[j] = min(nearest[j], simdLength(centres[remaining[j]] - centres[c])) }
        }
        return order
    }

    static func avgLast(_ layout: GridLayout, _ last: [Double], row: Int? = nil, column: Int? = nil) -> Double {
        let cells = layout.cells.filter { (row == nil || $0.row == row!) && (column == nil || $0.column == column!) }
        guard !cells.isEmpty else { return 0 }
        return cells.map { last[$0.index] }.reduce(0, +) / Double(cells.count)
    }
}

@inline(__always) func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = min(max((x - a) / max(b - a, 1e-5), 0), 1)
    return t * t * (3 - 2 * t)
}

extension Choreographer {
    /// A deck smaller than the grid, dealt in reading order: every slide shows
    /// before any shows twice, and a repeat never sits next to itself where
    /// another slide can go there. `pin` holds one slide in one cell, such as
    /// the cover in the middle.
    static func spread(_ slides: Int, over layout: GridLayout, pin: (cell: Int, slide: Int)? = nil) -> [Int] {
        // Dealing greedily can corner itself next to the pinned slide; deal
        // again from the next slide along until no repeat sits beside itself.
        var best: (deal: [Int], beside: Int)?
        for start in 0..<slides {
            let deal = Self.deal(slides, over: layout, pin: pin, from: start)
            let beside = layout.cells.filter { c in
                (c.column > 0 && deal[c.index] == deal[c.index - 1]) || (c.row > 0 && deal[c.index] == deal[c.index - layout.columns])
            }.count
            if beside < best?.beside ?? .max { best = (deal, beside) }
            if beside == 0 { break }
        }
        return best?.deal ?? []
    }

    private static func deal(_ slides: Int, over layout: GridLayout, pin: (cell: Int, slide: Int)?, from start: Int) -> [Int] {
        let n = layout.cells.count, columns = layout.columns
        var out = [Int](repeating: -1, count: n)
        var uses = [Int](repeating: 0, count: slides)
        if let pin {
            out[pin.cell] = pin.slide
            uses[pin.slide] += 1
        }
        var next = start % slides
        for c in 0..<n where c != pin?.cell {
            let row = c / columns, column = c % columns
            // Side by side or above and below, then corner to corner.
            var beside: [Int] = [], corner: [Int] = []
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 {
                    let r2 = row + dr, c2 = column + dc
                    guard r2 >= 0, c2 >= 0, c2 < columns, r2 * columns + c2 < n else { continue }
                    let slide = out[r2 * columns + c2]
                    guard slide >= 0 else { continue }
                    if dr == 0 || dc == 0 { beside.append(slide) } else { corner.append(slide) }
                }
            }
            let least = uses.min() ?? 0
            let candidates = (0..<slides).map { (next + $0) % slides }.filter { uses[$0] == least }
            let pick = candidates.first { !beside.contains($0) && !corner.contains($0) }
                ?? candidates.first { !beside.contains($0) }
                ?? candidates.first
                ?? next
            out[c] = pick
            uses[pick] += 1
            next = (pick + 1) % slides
        }
        return out
    }
}

/// When lit cells fall back below half, soonest first: a binary min-heap.
struct Expiries {
    private var items: [(until: Double, cell: Int)] = []

    var first: (until: Double, cell: Int)? { items.first }

    mutating func insert(until: Double, cell: Int) {
        items.append((until, cell))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard items[i].until < items[parent].until else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func removeFirst() {
        guard !items.isEmpty else { return }
        items.swapAt(0, items.count - 1)
        items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < items.count, items[l].until < items[m].until { m = l }
            if r < items.count, items[r].until < items[m].until { m = r }
            guard m != i else { break }
            items.swapAt(i, m)
            i = m
        }
    }
}
