import Foundation

/// The song Deck Beat opens with, so the grid is alive before anything is
/// dropped in: 34 seconds at 120 BPM in A minor, synthesised here, so it
/// ships with no recording and plays the same everywhere.
///
/// Four bars of pads, four of build with a riser, eight bars of drop, then
/// one last chord: an intro, a lift and a payoff to try every mode on.
public enum DemoGroove {
    public static let title = "Demo groove"
    public static let bpm: Double = 120
    public static let bars = 17
    public static let sampleRate = 48_000
    /// The bar the drop lands on.
    public static let dropBar = 8

    static var beat: Double { 60 / bpm }
    static var bar: Double { beat * 4 }
    public static var duration: Double { Double(bars) * bar }

    /// Stereo, interleaved, at 48 kHz.
    public static func render() -> [Float] {
        var g = Mixer(duration: duration, rate: Double(sampleRate))
        let chords: [[Int]] = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]]
        let roots = [33, 29, 36, 31]

        for b in 0..<bars {
            let t0 = Double(b) * bar
            let chord = chords[b % 4], root = roots[b % 4]
            let intro = b < 4, build = b >= 4 && b < 8, drop = b >= 8 && b < 16, end = b == 16
            // Pads: closed in the intro, opening through the build, full in the drop.
            let cutoff: Double = intro ? 520 + Double(b) * 90 : (build ? 900 + Double(b - 4) * 420 : (drop ? 3_000 : 2_200))
            let padLevel: Float = intro ? 0.16 : (build ? 0.15 : (drop ? 0.13 : 0.2))
            g.pad(chord, at: t0, length: end ? 3.6 : bar + 0.06, cutoff: cutoff, level: padLevel, attack: intro && b == 0 ? 1.6 : 0.05)

            for k in 0..<4 {
                let t = t0 + Double(k) * beat
                if intro {
                    if b >= 2, k == 0 { g.kick(at: t, level: 0.42) }
                    if b >= 2 { g.hat(at: t + beat / 2, level: 0.05, open: false, pan: 0.2) }
                } else if build {
                    // In the last two beats of the build the kick steps out.
                    if !(b == 7 && k >= 2) { g.kick(at: t, level: 0.55) }
                    if k % 2 == 1 { g.clap(at: t, level: 0.18) }
                    g.hat(at: t + beat / 2, level: 0.07, open: false, pan: 0.25)
                    if !(b == 7 && k >= 2) {
                        g.bass(root, at: t + beat / 2, length: beat * 0.42, level: 0.2, cutoff: 500 + Double(b - 4) * 120)
                    }
                } else if drop {
                    g.kick(at: t, level: 0.95)
                    if k % 2 == 1 { g.clap(at: t, level: 0.36) }
                    for s in 0..<4 {
                        let accent: Float = s == 2 ? 0.11 : 0.06
                        g.hat(at: t + Double(s) * beat / 4, level: accent, open: s == 2 && k == 3, pan: s % 2 == 0 ? 0.3 : -0.3)
                    }
                    g.bass(root, at: t + beat / 2, length: beat * 0.45, level: 0.32, cutoff: 900)
                    g.bass(root + 12, at: t + beat * 0.75, length: beat * 0.2, level: 0.12, cutoff: 1_400)
                    // The arpeggio walks the chord, an octave up.
                    for s in 0..<4 {
                        let step = (k * 4 + s) % 6
                        let note = chord[[0, 1, 2, 1, 2, 0][step]] + 12 + (step >= 4 ? 12 : 0)
                        g.pluck(note, at: t + Double(s) * beat / 4, level: 0.085, pan: s % 2 == 0 ? -0.35 : 0.35)
                    }
                } else if end, k == 0 {
                    g.kick(at: t, level: 0.95)
                    g.crash(at: t, level: 0.3)
                    g.bass(root, at: t, length: 2.4, level: 0.3, cutoff: 700)
                }
            }
            if b == 7 {
                // A riser and a snare roll into the drop.
                g.riser(from: t0, length: bar, level: 0.2)
                for s in 0..<16 { g.clap(at: t0 + Double(s) * beat / 4, level: 0.04 + Float(s) * 0.012) }
            }
            if drop, b % 4 == 0 { g.crash(at: t0, level: 0.26) }
            if b == 4 { g.crash(at: t0, level: 0.14) }
        }
        // The drop ducks the pads and bass under each kick.
        let kicks = (32..<64).map { Double($0) * beat } + [16 * bar]
        return g.mixdown(duckAt: kicks)
    }
}

/// A tiny offline mixer with a drum bus and a music bus.
struct Mixer {
    let rate: Double
    let n: Int
    var drumsL: [Float], drumsR: [Float]
    var musicL: [Float], musicR: [Float]
    var echoL: [Float], echoR: [Float]
    private var noiseState: UInt32 = 0x9E37_79B9

    init(duration: Double, rate: Double) {
        self.rate = rate
        n = Int(duration * rate)
        drumsL = [Float](repeating: 0, count: n); drumsR = drumsL
        musicL = drumsL; musicR = drumsL
        echoL = drumsL; echoR = drumsL
    }

    mutating func noise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Float(noiseState) / Float(UInt32.max) * 2 - 1
    }

    static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// One-pole low-pass coefficient for a cutoff.
    func lp(_ cutoff: Double) -> Float { Float(1 - exp(-2 * Double.pi * cutoff / rate)) }

    func span(_ start: Double, _ length: Double) -> Range<Int> {
        let a = max(0, Int(start * rate)), b = min(n, Int((start + length) * rate))
        return a..<max(a, b)
    }

    mutating func kick(at t: Double, level: Float) {
        var phase = 0.0
        for i in span(t, 0.42) {
            let x = Double(i) / rate - t
            let f = 46 + 110 * exp(-x * 28)
            phase += 2 * Double.pi * f / rate
            let env = Float(exp(-x * 7.5)) * min(1, Float(x * 2_000))
            let click = Float(exp(-x * 400)) * 0.25
            let v = (Float(sin(phase)) * env + click * noise() * 0.5) * level
            drumsL[i] += v; drumsR[i] += v
        }
    }

    mutating func clap(at t: Double, level: Float) {
        var lo: Float = 0, lo2: Float = 0
        let a = lp(4_000), b = lp(900)
        for i in span(t, 0.3) {
            let x = Double(i) / rate - t
            // Three quick slaps then a tail, like hands.
            let slaps = (0..<3).reduce(Float(0)) { acc, k in
                let d = x - Double(k) * 0.011
                return acc + (d >= 0 ? Float(exp(-d * 180)) : 0)
            }
            let env = slaps * 0.6 + Float(exp(-x * 16)) * 0.7
            let raw = noise()
            // Noise between about 900 Hz and 4 kHz.
            lo += a * (raw - lo)
            lo2 += b * (lo - lo2)
            let tone = Float(sin(2 * Double.pi * 190 * x)) * Float(exp(-x * 30)) * 0.3
            let v = ((lo - lo2) * 1.6 + tone) * env * level
            drumsL[i] += v * 0.95; drumsR[i] += v
        }
    }

    mutating func hat(at t: Double, level: Float, open: Bool, pan: Float) {
        var prev: Float = 0
        let decay = open ? 9.0 : 55.0
        for i in span(t, open ? 0.45 : 0.12) {
            let x = Double(i) / rate - t
            let raw = noise()
            let hp = raw - prev
            prev = raw
            let v = hp * Float(exp(-x * decay)) * level
            drumsL[i] += v * (1 - pan); drumsR[i] += v * (1 + pan)
        }
    }

    mutating func crash(at t: Double, level: Float) {
        var prev: Float = 0
        for i in span(t, 2.4) {
            let x = Double(i) / rate - t
            let raw = noise()
            let hp = raw - prev * 0.6
            prev = raw
            let v = hp * Float(exp(-x * 1.6)) * level * min(1, Float(x * 400))
            drumsL[i] += v * 1.1; drumsR[i] += v * 0.9
        }
    }

    mutating func riser(from t: Double, length: Double, level: Float) {
        var s: Float = 0
        for i in span(t, length) {
            let x = (Double(i) / rate - t) / length
            let a = lp(300 + 7_000 * x * x)
            s += a * (noise() - s)
            let v = s * Float(x * x) * level
            musicL[i] += v; musicR[i] += v
        }
    }

    mutating func bass(_ midi: Int, at t: Double, length: Double, level: Float, cutoff: Double) {
        let f = Self.hz(midi)
        var phase = 0.0, s1: Float = 0, s2: Float = 0
        for i in span(t, length + 0.05) {
            let x = Double(i) / rate - t
            phase += f / rate
            let saw = Float(2 * (phase - floor(phase)) - 1)
            let sub = Float(sin(2 * Double.pi * phase))
            let a = lp(cutoff * (1 + 2.5 * exp(-x * 18)))
            s1 += a * (saw - s1); s2 += a * (s1 - s2)
            let env = min(1, Float(x * 400)) * (x < length ? 1 : Float(max(0, 1 - (x - length) / 0.05)))
            let v = (s2 * 0.7 + sub * 0.5) * env * level
            musicL[i] += v; musicR[i] += v
        }
    }

    mutating func pad(_ chord: [Int], at t: Double, length: Double, cutoff: Double, level: Float, attack: Double) {
        let a = lp(cutoff)
        var sl: Float = 0, sr: Float = 0
        let detune: [Double] = [-0.006, 0, 0.007]
        var phases = [Double](repeating: 0, count: chord.count * 3)
        let freqs = chord.flatMap { m in detune.map { Self.hz(m) * (1 + $0) } }
        let release = 0.5
        for i in span(t, length + release) {
            let x = Double(i) / rate - t
            var l: Float = 0, r: Float = 0
            for k in freqs.indices {
                phases[k] += freqs[k] / rate
                let saw = Float(2 * (phases[k] - floor(phases[k])) - 1)
                if k % 3 == 0 { l += saw } else if k % 3 == 2 { r += saw } else { l += saw * 0.5; r += saw * 0.5 }
            }
            sl += a * (l - sl); sr += a * (r - sr)
            let env = Float(min(1, x / attack)) * (x < length ? 1 : Float(max(0, 1 - (x - length) / release)))
            let g = env * level / Float(chord.count)
            musicL[i] += sl * g; musicR[i] += sr * g
        }
    }

    mutating func pluck(_ midi: Int, at t: Double, level: Float, pan: Float) {
        let f = Self.hz(midi)
        var phase = 0.0, s: Float = 0
        for i in span(t, 0.22) {
            let x = Double(i) / rate - t
            phase += f / rate
            let p = phase - floor(phase)
            let sq = Float(p < 0.5 ? 1 : -1) * 0.6 + Float(2 * p - 1) * 0.4
            let a = lp(900 + 5_000 * exp(-x * 22))
            s += a * (sq - s)
            let v = s * Float(exp(-x * 14)) * min(1, Float(x * 1_000)) * level
            echoL[i] += v * (1 - pan); echoR[i] += v * (1 + pan)
        }
    }

    /// Ducks the music under the kicks, adds the echo, and levels the mix to
    /// a −1 dBFS peak through a soft clip.
    func mixdown(duckAt kicks: [Double]) -> [Float] {
        var duck = [Float](repeating: 1, count: n)
        for k in kicks {
            for i in span(k, 0.4) {
                let x = Double(i) / rate - k
                duck[i] = min(duck[i], 1 - 0.55 * Float(exp(-x * 9)) * min(1, Float(x * 300) + 0.3))
            }
        }
        // A ping-pong echo of three sixteenths for the plucks.
        let delay = Int(0.375 * rate / 2)
        var eL = echoL, eR = echoR
        if delay < n {
            for i in delay..<n {
                eL[i] += eR[i - delay] * 0.38
                eR[i] += eL[i - delay] * 0.38
            }
        }
        var out = [Float](repeating: 0, count: n * 2)
        var peak: Float = 1e-6
        for i in 0..<n {
            let l = drumsL[i] + (musicL[i] + eL[i]) * duck[i]
            let r = drumsR[i] + (musicR[i] + eR[i]) * duck[i]
            out[2 * i] = l; out[2 * i + 1] = r
            peak = max(peak, abs(l), abs(r))
        }
        let gain = 1.15 / peak
        let ceiling: Float = 0.89
        for i in out.indices {
            out[i] = ceiling * tanhf(out[i] * gain)
        }
        return out
    }
}
