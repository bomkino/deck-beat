import Foundation

// Listening to a whole song once, before anything moves: the spectrum in six
// bands, onsets in three, the tempo, a beat grid with its downbeats, and the
// moments the song opens up. Every picture Deck Beat draws is a pure function
// of time over these arrays, so the preview is the export, scrubbing is exact,
// and the choreography can see a drop coming.

/// The six bands the spectrum is read in.
public enum Band: Int, CaseIterable, Codable, Sendable {
    case sub, bass, lowMid, mid, highMid, air

    /// Edges in hertz.
    public var range: ClosedRange<Double> {
        switch self {
        case .sub: return 25...60
        case .bass: return 60...160
        case .lowMid: return 160...500
        case .mid: return 500...2_000
        case .highMid: return 2_000...5_000
        case .air: return 5_000...11_000
        }
    }
}

/// The three registers onsets are found in: kicks and bass, the body of the
/// mix, and hats and air.
public enum Register: Int, CaseIterable, Codable, Sendable {
    case low, mid, high

    var bands: [Band] {
        switch self {
        case .low: return [.sub, .bass]
        case .mid: return [.lowMid, .mid]
        case .high: return [.highMid, .air]
        }
    }
}

/// A sound starting: a kick, a snare, a chord, a hat.
public struct Onset: Codable, Hashable, Sendable {
    public var time: Double
    /// 0…1, against the song's own loudest onsets in this register.
    public var strength: Float
    public var register: Register

    public init(time: Double, strength: Float, register: Register) {
        self.time = time
        self.strength = strength
        self.register = register
    }
}

/// One beat of the grid.
public struct Beat: Codable, Hashable, Sendable {
    public var time: Double
    /// 0…1: how much actually happens on this beat. Beats carried through a
    /// quiet passage, or past either end of the music, are weak.
    public var strength: Float
    /// Position in its bar, 0 being the downbeat.
    public var inBar: Int
    /// Which bar, counting from the first downbeat at or after the music starts.
    public var bar: Int

    public init(time: Double, strength: Float, inBar: Int, bar: Int) {
        self.time = time
        self.strength = strength
        self.inBar = inBar
        self.bar = bar
    }

    public var isDownbeat: Bool { inBar == 0 }
}

/// Everything Deck Beat knows about a song. Immutable and shared by
/// reference, because scenes read it on every frame.
public final class SongAnalysis: Codable, @unchecked Sendable {
    public static let version = 1
    public static let frameRate: Double = 100
    public static let spectrumBands = 16

    /// Edges of the fine spectrum's bands in hertz.
    public static func spectrumEdges() -> [Double] {
        (0...spectrumBands).map { 40 * pow(11_000 / 40, Double($0) / Double(spectrumBands)) }
    }

    public let version: Int
    public let duration: Double
    /// Per band, 0…1 at `frameRate`: each band against its own quiet and loud.
    public let bands: [[Float]]
    /// Loudness, 0…1 at `frameRate`.
    public let loudness: [Float]
    /// Spectral centroid, 0 (dark) … 1 (bright), at `frameRate`.
    public let brightness: [Float]
    /// Onset strength in each register, 0…1 at `frameRate`.
    public let flux: [[Float]]
    /// A finer spectrum: `spectrumBands` log-spaced bands from 40 Hz to
    /// 11 kHz, each 0…1 against its own range, at `frameRate`.
    public let spectrum: [[Float]]
    public let onsets: [Onset]
    public let tempo: Double
    /// How clearly the music keeps a steady beat, 0…1.
    public let confidence: Float
    /// A grid covering the whole song, carried through quiet passages.
    public let beats: [Beat]
    /// Times where the song opens up: a big rise in energy, on a downbeat.
    public let drops: [Double]
    /// Where the music starts and stops being audible.
    public let start: Double
    public let end: Double

    public init(duration: Double, bands: [[Float]], loudness: [Float], brightness: [Float], flux: [[Float]], spectrum: [[Float]],
                onsets: [Onset], tempo: Double, confidence: Float, beats: [Beat], drops: [Double], start: Double, end: Double) {
        version = Self.version
        self.duration = duration
        self.bands = bands
        self.loudness = loudness
        self.brightness = brightness
        self.flux = flux
        self.spectrum = spectrum
        self.onsets = onsets
        self.tempo = tempo
        self.confidence = confidence
        self.beats = beats
        self.drops = drops
        self.start = start
        self.end = end
    }

    /// Seconds per beat.
    public var beatPeriod: Double { 60 / max(tempo, 1) }

    public var frameCount: Int { loudness.count }

    // MARK: Reading at a time

    /// Linear interpolation into a feature track.
    @inline(__always)
    public static func sample(_ track: [Float], at t: Double) -> Float {
        guard !track.isEmpty else { return 0 }
        let x = max(0, t * frameRate)
        let i = Int(x)
        if i >= track.count - 1 { return track[track.count - 1] }
        let f = Float(x - Double(i))
        return track[i] + (track[i + 1] - track[i]) * f
    }

    public func band(_ b: Band, at t: Double) -> Float { Self.sample(bands[b.rawValue], at: t) }
    /// The fine spectrum at a fractional position 0 (lowest) … 1 (highest).
    public func spectrum(at position: Float, time t: Double) -> Float {
        guard !spectrum.isEmpty else { return 0 }
        let x = min(max(position, 0), 1) * Float(spectrum.count - 1)
        let i = min(Int(x), spectrum.count - 2), f = x - Float(i)
        guard spectrum.count > 1 else { return Self.sample(spectrum[0], at: t) }
        return Self.sample(spectrum[i], at: t) * (1 - f) + Self.sample(spectrum[i + 1], at: t) * f
    }
    public func loudness(at t: Double) -> Float { Self.sample(loudness, at: t) }
    public func brightness(at t: Double) -> Float { Self.sample(brightness, at: t) }
    public func register(_ r: Register, at t: Double) -> Float {
        let bs = r.bands
        return bs.reduce(0) { $0 + band($1, at: t) } / Float(bs.count)
    }

    /// The index of the last beat at or before `t`, or nil before the first.
    public func beatIndex(at t: Double) -> Int? {
        var lo = 0, hi = beats.count - 1
        guard hi >= 0, beats[0].time <= t else { return nil }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if beats[mid].time <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Position in beats: the index of the beat before `t` plus the fraction
    /// of the way to the next. Before the first beat it counts backwards.
    public func beatPosition(at t: Double) -> Double {
        guard let first = beats.first else { return t / beatPeriod }
        guard let i = beatIndex(at: t) else { return (t - first.time) / beatPeriod }
        let a = beats[i].time
        let b = i + 1 < beats.count ? beats[i + 1].time : a + beatPeriod
        return Double(i) + (t - a) / max(b - a, 1e-3)
    }

    /// The time of a fractional beat position (the inverse of `beatPosition`).
    public func time(atBeat position: Double) -> Double {
        guard let first = beats.first else { return position * beatPeriod }
        if position < 0 { return first.time + position * beatPeriod }
        let i = Int(position)
        if i >= beats.count - 1 {
            let last = beats[beats.count - 1].time
            return last + (position - Double(beats.count - 1)) * beatPeriod
        }
        let f = position - Double(i)
        return beats[i].time + (beats[i + 1].time - beats[i].time) * f
    }

    /// Onsets with `from <= time < to`, in time order.
    public func onsets(from: Double, to: Double) -> ArraySlice<Onset> {
        let a = firstOnset(atOrAfter: from), b = firstOnset(atOrAfter: to)
        return onsets[a..<max(a, b)]
    }

    private func firstOnset(atOrAfter t: Double) -> Int {
        var lo = 0, hi = onsets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if onsets[mid].time < t { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: Choosing a section

    /// The best `length` seconds for a post: loud and busy, starting on a
    /// downbeat, and if the song has a drop, with it landing a few seconds in,
    /// after the opening has had time to play.
    public func bestSection(length: Double, lead: Double = 3) -> Double {
        guard duration > length + 0.5 else { return 0 }
        let candidates = beats.filter { $0.isDownbeat && $0.time >= start - 0.01 && $0.time + length <= duration + 0.01 }.map(\.time)
        let starts = candidates.isEmpty ? stride(from: 0, through: duration - length, by: 1).map { $0 } : candidates
        var best = starts[0], bestScore = -Double.infinity
        for s in starts {
            let a = Int(s * Self.frameRate), b = min(loudness.count, Int((s + length) * Self.frameRate))
            guard b > a else { continue }
            var energy: Double = 0, busy: Double = 0
            for i in a..<b {
                energy += Double(loudness[i])
                busy += Double(flux[0][i] + flux[1][i] + flux[2][i]) / 3
            }
            energy /= Double(b - a)
            busy /= Double(b - a)
            var score = energy + 0.5 * busy
            // A drop shortly after the opening is the best hook a clip can have.
            if drops.contains(where: { $0 - s >= lead * 0.6 && $0 - s <= lead + 4 }) { score += 0.25 }
            // Starting in silence wastes the hook.
            let opening = Double(Self.sample(loudness, at: s + 0.5))
            score += 0.1 * opening
            if score > bestScore { bestScore = score; best = s }
        }
        return best
    }
}

// MARK: - Analyser

public enum SongAnalyzer {
    /// Rate the analysis runs at, after halving the usual 48 kHz.
    static let rate: Double = 24_000
    static let fftSize = 1024
    static let hop = 240

    /// Analyses mono samples at `sampleRate`. Pure and deterministic.
    public static func analyze(mono input: [Float], sampleRate: Double) -> SongAnalysis {
        let duration = Double(input.count) / max(sampleRate, 1)
        let samples = resample(input, from: sampleRate, to: rate)
        let frames = max(1, Int((Double(samples.count) / Double(hop)).rounded(.up)))
        let fft = RealFFT(size: fftSize)
        let window = fft.hann
        let bins = fftSize / 2 + 1
        let binHz = rate / Double(fftSize)

        // Which bins each band covers.
        let bandBins: [Range<Int>] = Band.allCases.map { b in
            let lo = max(1, Int((b.range.lowerBound / binHz).rounded()))
            let hi = min(bins - 1, max(lo + 1, Int((b.range.upperBound / binHz).rounded())))
            return lo..<hi
        }

        var bandEnergy = Band.allCases.map { _ in [Float](repeating: 0, count: frames) }
        var rms = [Float](repeating: 0, count: frames)
        var centroid = [Float](repeating: 0, count: frames)
        var flux = Register.allCases.map { _ in [Float](repeating: 0, count: frames) }
        let edges = SongAnalysis.spectrumEdges()
        let fineBins: [Range<Int>] = (0..<SongAnalysis.spectrumBands).map { k in
            let lo = max(1, Int((edges[k] / binHz).rounded()))
            let hi = min(bins - 1, max(lo + 1, Int((edges[k + 1] / binHz).rounded())))
            return lo..<hi
        }
        var fine = fineBins.map { _ in [Float](repeating: 0, count: frames) }

        var frame = [Float](repeating: 0, count: fftSize)
        var mags = [Float](repeating: 0, count: bins)
        var logPrev = [Float](repeating: 0, count: bins)
        var logNow = [Float](repeating: 0, count: bins)
        let registerOf: [Int] = (0..<bins).map { k in
            for (i, r) in bandBins.enumerated() where r.contains(k) { return Register.allCases.first { $0.bands.contains(Band(rawValue: i)!) }!.rawValue }
            return -1
        }

        samples.withUnsafeBufferPointer { s in
            for f in 0..<frames {
                // Frames are centred on their time.
                let centre = f * hop
                var sumSq: Float = 0
                for i in 0..<fftSize {
                    let j = centre - fftSize / 2 + i
                    let v: Float = (j >= 0 && j < s.count) ? s[j] : 0
                    frame[i] = v * window[i]
                    sumSq += v * v
                }
                rms[f] = (sumSq / Float(fftSize)).squareRoot()
                frame.withUnsafeBufferPointer { inp in
                    mags.withUnsafeMutableBufferPointer { out in fft.magnitudes(inp, into: out) }
                }
                var weighted: Float = 0, total: Float = 0
                for k in 1..<bins {
                    let m = mags[k]
                    weighted += m * Float(k)
                    total += m
                    logNow[k] = logf(1 + 100 * m)
                }
                centroid[f] = total > 1e-6 ? weighted / total * Float(binHz) : 0
                for (i, r) in bandBins.enumerated() {
                    var e: Float = 0
                    for k in r { e += mags[k] * mags[k] }
                    bandEnergy[i][f] = e / Float(max(r.count, 1))
                }
                for (i, r) in fineBins.enumerated() {
                    var e: Float = 0
                    for k in r { e += mags[k] * mags[k] }
                    fine[i][f] = e / Float(max(r.count, 1))
                }
                if f > 0 {
                    var acc: [Float] = [0, 0, 0]
                    for k in 1..<bins where registerOf[k] >= 0 {
                        let d = logNow[k] - logPrev[k]
                        if d > 0 { acc[registerOf[k]] += d }
                    }
                    for r in 0..<3 { flux[r][f] = acc[r] }
                }
                swap(&logPrev, &logNow)
            }
        }

        // Each band against its own range, on a log scale, lightly smoothed.
        let bands: [[Float]] = bandEnergy.map { e in
            let db = e.map { 10 * log10f($0 + 1e-10) }
            return smooth(normalize(db, low: 0.10, high: 0.995, floorSpan: 24), radius: 1)
        }
        let spectrum: [[Float]] = fine.map { e in
            smooth(normalize(e.map { 10 * log10f($0 + 1e-10) }, low: 0.10, high: 0.995, floorSpan: 24), radius: 1)
        }
        let loudDB = rms.map { 20 * log10f($0 + 1e-7) }
        let loudness = smooth(normalize(loudDB, low: 0.05, high: 0.995, floorSpan: 30), radius: 2)
        let bright = smooth(centroid.map { c in
            // 300 Hz (dark) to 5 kHz (bright) on a log scale.
            guard c > 0 else { return 0 }
            return min(max((log2f(c) - log2f(300)) / (log2f(5_000) - log2f(300)), 0), 1)
        }, radius: 4)
        let normFlux = flux.map { scaleToPercentile($0, 0.99) }

        // Where the music is audible.
        let peak = loudDB.max() ?? -140
        let audible = loudDB.indices.filter { loudDB[$0] > peak - 50 }
        let start = Double(audible.first ?? 0) / SongAnalysis.frameRate
        let end = Double((audible.last ?? frames - 1) + 1) / SongAnalysis.frameRate

        let onsets = pickOnsets(normFlux)
        let envelope = onsetEnvelope(normFlux)
        let (tempo, confidence) = estimateTempo(envelope)
        let kicks = kickStrength(low: zip(bandEnergy[Band.sub.rawValue], bandEnergy[Band.bass.rawValue]).map { $0 + $1 })
        var beatTimes = trackBeats(envelope, tempo: tempo, duration: duration, start: start, end: end)
        beatTimes = alignToKicks(beatTimes, kicks: kicks, start: start, end: end)
        let beats = labelBeats(beatTimes, envelope: envelope, low: kicks, harmony: harmonicChange(spectrum, at: beatTimes),
                               start: start, end: end)
        let drops = findDrops(loudness: loudness, beats: beats, period: 60 / tempo)

        return SongAnalysis(duration: duration, bands: bands, loudness: loudness, brightness: bright, flux: normFlux, spectrum: spectrum,
                            onsets: onsets, tempo: tempo, confidence: confidence, beats: beats, drops: drops,
                            start: start, end: min(end, duration))
    }

    // MARK: Resampling

    /// Resamples by linear interpolation after a gentle low-pass, enough for
    /// analysis (not for listening).
    static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        guard from > 0, abs(from - to) > 1 else { return x }
        let ratio = from / to
        var src = x
        if ratio > 1 {
            // A moving average as wide as the step keeps aliasing down.
            let width = max(1, Int(ratio.rounded()))
            if width > 1 {
                var out = [Float](repeating: 0, count: x.count)
                var acc: Float = 0
                for i in 0..<x.count {
                    acc += x[i]
                    if i >= width { acc -= x[i - width] }
                    out[i] = acc / Float(min(i + 1, width))
                }
                src = out
            }
        }
        let n = Int(Double(x.count) / ratio)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let p = Double(i) * ratio
            let j = Int(p)
            let f = Float(p - Double(j))
            let a = src[min(j, src.count - 1)], b = src[min(j + 1, src.count - 1)]
            out[i] = a + (b - a) * f
        }
        return out
    }

    // MARK: Shaping feature tracks

    /// Maps values between two percentiles to 0…1. A span narrower than
    /// `floorSpan` is widened downwards, so a steady drone does not swing.
    static func normalize(_ x: [Float], low: Double, high: Double, floorSpan: Float) -> [Float] {
        guard !x.isEmpty else { return x }
        let sorted = x.sorted()
        let lo = sorted[Int(Double(sorted.count - 1) * low)]
        let hi = sorted[Int(Double(sorted.count - 1) * high)]
        let span = max(hi - lo, floorSpan)
        let base = hi - span
        return x.map { min(max(($0 - base) / span, 0), 1) }
    }

    /// Divides by a high percentile and clamps, so the loudest moments read as 1.
    static func scaleToPercentile(_ x: [Float], _ p: Double) -> [Float] {
        let sorted = x.sorted()
        guard let top = sorted.isEmpty ? nil : sorted[Int(Double(sorted.count - 1) * p)], top > 1e-6 else {
            return x.map { _ in 0 }
        }
        return x.map { min($0 / top, 1) }
    }

    static func smooth(_ x: [Float], radius: Int) -> [Float] {
        guard radius > 0, x.count > 2 else { return x }
        var out = [Float](repeating: 0, count: x.count)
        var acc: Float = 0
        var count = 0
        // A running box filter.
        var lo = 0, hi = -1
        for i in 0..<x.count {
            while hi < min(x.count - 1, i + radius) { hi += 1; acc += x[hi]; count += 1 }
            while lo < i - radius { acc -= x[lo]; lo += 1; count -= 1 }
            out[i] = acc / Float(max(count, 1))
        }
        return out
    }

    // MARK: Onsets

    /// Peaks that stand clear of their neighbourhood, at least a few
    /// hundredths of a second apart.
    static func pickOnsets(_ flux: [[Float]]) -> [Onset] {
        var out: [Onset] = []
        let rate = SongAnalysis.frameRate
        for r in Register.allCases {
            let x = flux[r.rawValue]
            let n = x.count
            let wait = r == .low ? 9 : (r == .mid ? 7 : 5)
            let delta: Float = r == .high ? 0.08 : 0.07
            var last = -1000
            var prefix = [Float](repeating: 0, count: n + 1)
            for i in 0..<n { prefix[i + 1] = prefix[i] + x[i] }
            for i in 0..<n {
                let v = x[i]
                guard v > 0.08 else { continue }
                let a = max(0, i - 3), b = min(n - 1, i + 3)
                var isMax = true
                for j in a...b where x[j] > v || (x[j] == v && j < i) { isMax = false; break }
                guard isMax else { continue }
                let ma = max(0, i - 12), mb = min(n, i + 8)
                let mean = (prefix[mb] - prefix[ma]) / Float(mb - ma)
                guard v >= mean + delta, i - last >= wait else { continue }
                last = i
                out.append(Onset(time: Double(i) / rate, strength: min(1, v), register: r))
            }
        }
        out.sort { $0.time < $1.time || ($0.time == $1.time && $0.register.rawValue < $1.register.rawValue) }
        return out
    }

    /// One onset-strength curve for tempo and beats: lows count most, as
    /// kicks carry the pulse in most music.
    static func onsetEnvelope(_ flux: [[Float]]) -> [Float] {
        let n = flux[0].count
        var e = [Float](repeating: 0, count: n)
        for i in 0..<n { e[i] = 1.2 * flux[0][i] + 1.0 * flux[1][i] + 0.6 * flux[2][i] }
        // Remove the slow trend so only the attacks remain.
        let trend = smooth(e, radius: 25)
        return zip(e, trend).map { max(0, $0 - $1) }
    }

    // MARK: Tempo

    /// The tempo by autocorrelation of the onset envelope, leaning towards
    /// 120 BPM between 60 and 190, with how strongly the pulse stands out.
    static func estimateTempo(_ env: [Float]) -> (bpm: Double, confidence: Float) {
        let rate = SongAnalysis.frameRate
        let n = env.count
        let minLag = Int(rate * 60 / 190), maxLag = Int(rate * 60 / 60)
        guard n > maxLag * 3 else { return (120, 0) }
        let mean = env.reduce(0, +) / Float(n)
        let x = env.map { $0 - mean }
        var energy: Float = 0
        for v in x { energy += v * v }
        guard energy > 1e-6 else { return (120, 0) }
        var ac = [Float](repeating: 0, count: maxLag + 2)
        for lag in max(1, minLag - 1)...(maxLag + 1) {
            var s: Float = 0
            var i = 0
            while i + lag < n { s += x[i] * x[i + lag]; i += 1 }
            ac[lag] = s / energy
        }
        func prior(_ lag: Double) -> Double {
            let bpm = 60 * rate / lag
            let z = log2(bpm / 120) / 0.85
            return exp(-0.5 * z * z)
        }
        var bestLag = minLag
        var best = -Double.infinity
        for lag in minLag...maxLag {
            // A true period also correlates at twice its lag.
            let double = 2 * lag <= maxLag + 1 ? Double(ac[min(2 * lag, maxLag + 1)]) : 0
            let score = (Double(ac[lag]) + 0.5 * max(0, double)) * prior(Double(lag))
            if score > best { best = score; bestLag = lag }
        }
        // Parabolic refinement around the peak.
        var lag = Double(bestLag)
        if bestLag > minLag, bestLag < maxLag {
            let a = Double(ac[bestLag - 1]), b = Double(ac[bestLag]), c = Double(ac[bestLag + 1])
            let d = a - 2 * b + c
            if abs(d) > 1e-9 { lag += min(max(0.5 * (a - c) / d, -0.5), 0.5) }
        }
        let bpm = 60 * rate / lag
        // How far the chosen peak stands above the typical correlation.
        let typical = ac[minLag...maxLag].map { abs($0) }.reduce(0, +) / Float(maxLag - minLag + 1)
        let confidence = min(1, max(0, (ac[bestLag] - typical) / max(0.25, 1 - typical) * 2))
        return (bpm, confidence)
    }

    // MARK: Beats

    /// Dynamic-programming beat tracking (after Ellis, 2007): beats fall on
    /// strong onsets while keeping close to the tempo. The grid is then carried
    /// at the tempo through the silence before and after the music.
    static func trackBeats(_ env: [Float], tempo: Double, duration: Double, start: Double, end: Double) -> [Double] {
        let rate = SongAnalysis.frameRate
        let n = env.count
        let period = rate * 60 / tempo
        guard n > Int(period * 2) else { return gridOnly(period: 60 / tempo, from: start, duration: duration) }
        // Local score: the envelope smoothed by a narrow Gaussian.
        let radius = max(1, Int(period / 8))
        let sigma = period / 32
        var kernel = [Float](repeating: 0, count: 2 * radius + 1)
        for i in -radius...radius { kernel[i + radius] = Float(exp(-0.5 * pow(Double(i) / max(sigma, 0.5), 2))) }
        var local = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var s: Float = 0
            for k in -radius...radius where i + k >= 0 && i + k < n { s += env[i + k] * kernel[k + radius] }
            local[i] = s
        }
        let maxLocal = local.max() ?? 0
        guard maxLocal > 1e-6 else { return gridOnly(period: 60 / tempo, from: start, duration: duration) }
        let tightness = 100.0
        var score = [Double](repeating: 0, count: n)
        var back = [Int](repeating: -1, count: n)
        let lo = Int((period * 2).rounded()), hi = max(1, Int((period / 2).rounded()))
        var transition: [Double] = []
        for d in hi...lo { transition.append(-tightness * pow(log(Double(d) / period), 2)) }
        let threshold = 0.01 * Double(maxLocal)
        var started = false
        for i in 0..<n {
            var best = -Double.infinity, arg = -1
            if i - hi >= 0 {
                for (k, d) in (hi...lo).enumerated() {
                    let j = i - d
                    guard j >= 0 else { break }
                    let s = score[j] + transition[k]
                    if s > best { best = s; arg = j }
                }
            }
            let l = Double(local[i]) / Double(maxLocal)
            if !started, l > threshold / Double(maxLocal) { started = true }
            if arg >= 0, started {
                score[i] = l + best
                back[i] = arg
            } else {
                score[i] = l
            }
        }
        // The last beat: the latest local maximum of the cumulative score that
        // is reasonably high.
        var maxima: [Int] = []
        for i in 1..<(n - 1) where score[i] > score[i - 1] && score[i] >= score[i + 1] { maxima.append(i) }
        guard !maxima.isEmpty else { return gridOnly(period: 60 / tempo, from: start, duration: duration) }
        let med = maxima.map { score[$0] }.sorted()[maxima.count / 2]
        var last = maxima.last { score[$0] >= 0.5 * med } ?? maxima.last!
        var frames: [Int] = []
        while last >= 0 {
            frames.append(last)
            last = back[last]
        }
        frames.reverse()
        // Keep the tracked beats inside the music, then carry the grid outwards.
        var times = frames.map { Double($0) / rate }.filter { $0 >= start - 0.05 && $0 <= end + 0.05 }
        guard times.count >= 2 else { return gridOnly(period: 60 / tempo, from: start, duration: duration) }
        let p = 60 / tempo
        var before: [Double] = []
        var t = times[0] - p
        while t > -p * 0.25 { before.append(max(t, 0)); t -= p }
        // A beat a hair before the start counts as on it; never two at zero.
        if before.count >= 2, before[before.count - 1] == 0, before[before.count - 2] < p * 0.5 { before.removeLast() }
        var after: [Double] = []
        t = times[times.count - 1] + p
        while t < duration + p * 0.25 { after.append(t); t += p }
        times = before.reversed() + times + after
        // Remove any accidental near-duplicates.
        var cleaned: [Double] = []
        for t in times where cleaned.last.map({ t - $0 > p * 0.4 }) ?? true { cleaned.append(t) }
        return cleaned
    }

    /// How hard the low end jumps at each frame, in amplitude, 0…1: kicks
    /// stand out here far more than in the log-scaled flux, where a bass note
    /// coming back after a duck looks as strong as the kick that ducked it.
    static func kickStrength(low power: [Float]) -> [Float] {
        let n = power.count
        var rise = [Float](repeating: 0, count: n)
        for f in 0..<n {
            var floor = power[f]
            for k in max(0, f - 5)..<f { floor = min(floor, power[k]) }
            rise[f] = max(0, power[f].squareRoot() - floor.squareRoot())
        }
        return scaleToPercentile(rise, 0.99)
    }

    /// Flux alone cannot always tell the beat from the offbeat (offbeat bass,
    /// open hats). If the grid shifted by half a beat lands on clearly harder
    /// kicks, the music's pulse is there.
    static func alignToKicks(_ times: [Double], kicks: [Float], start: Double, end: Double) -> [Double] {
        guard times.count >= 8 else { return times }
        let rate = SongAnalysis.frameRate
        func at(_ t: Double) -> Float {
            let c = Int((t * rate).rounded())
            var m: Float = 0
            let lo = max(0, c - 3), hi = min(kicks.count - 1, c + 3)
            guard lo <= hi else { return 0 }
            for i in lo...hi { m = max(m, kicks[i]) }
            return m
        }
        var on: Float = 0, off: Float = 0
        for i in 0..<(times.count - 1) where times[i] >= start - 0.05 && times[i] <= end {
            on += at(times[i])
            off += at((times[i] + times[i + 1]) / 2)
        }
        guard off > on * 1.2 else { return times }
        var shifted: [Double] = []
        for i in 0..<times.count {
            let next = i + 1 < times.count ? times[i + 1] : times[i] + (times[i] - times[max(0, i - 1)])
            shifted.append((times[i] + next) / 2)
        }
        // Keep the half beat before the first, so the grid still reaches the start.
        let first = times[0] - (times[1] - times[0]) / 2
        return (first > -0.02 ? [max(first, 0)] : []) + shifted
    }

    static func gridOnly(period: Double, from start: Double, duration: Double) -> [Double] {
        var out: [Double] = []
        var t = start
        while t > period { t -= period }
        while t < duration + period * 0.25 { out.append(t); t += period }
        return out
    }

    /// Strength for each beat, and bar positions from the phase where the
    /// lows hit hardest (four beats to a bar).
    /// How much the harmony moves across each beat: the middle of the spectrum
    /// over the half beat after it against the half beat before. Chords change
    /// on downbeats far more often than anywhere else.
    static func harmonicChange(_ spectrum: [[Float]], at times: [Double]) -> [Float] {
        let rate = SongAnalysis.frameRate
        let n = spectrum.first?.count ?? 0
        guard n > 0, times.count > 1 else { return times.map { _ in 0 } }
        let mid = 3..<min(13, spectrum.count)
        func mean(_ band: Int, _ a: Double, _ b: Double) -> Float {
            let i = max(0, min(n - 1, Int(a * rate))), j = max(i + 1, min(n, Int(b * rate)))
            var s: Float = 0
            for k in i..<j { s += spectrum[band][k] }
            return s / Float(j - i)
        }
        let out: [Float] = times.indices.map { i in
            let half = (i + 1 < times.count ? times[i + 1] - times[i] : times[i] - times[i - 1]) / 2
            let t = times[i]
            var d: Float = 0
            for b in mid { d += abs(mean(b, t + 0.03, t + half) - mean(b, t - half, t - 0.03)) }
            return d
        }
        return scaleToPercentile(out, 0.95)
    }

    static func labelBeats(_ times: [Double], envelope: [Float], low: [Float], harmony: [Float], start: Double, end: Double) -> [Beat] {
        guard !times.isEmpty else { return [] }
        let rate = SongAnalysis.frameRate
        func peak(_ x: [Float], _ t: Double) -> Float {
            let c = Int((t * rate).rounded())
            var m: Float = 0
            let lo = max(0, c - 5), hi = min(x.count - 1, c + 5)
            guard lo <= hi else { return 0 }
            for i in lo...hi { m = max(m, x[i]) }
            return m
        }
        let raw = times.map { peak(envelope, $0) }
        let top = max(raw.sorted()[Int(Double(raw.count - 1) * 0.95)], 1e-6)
        var strengths = raw.map { min(1, $0 / top) }
        for (i, t) in times.enumerated() where t < start - 0.05 || t > end + 0.05 { strengths[i] = 0 }
        var bestPhase = 0
        var bestScore: Float = -1
        for phase in 0..<4 {
            var s: Float = 0
            var i = phase
            while i < times.count {
                s += peak(low, times[i]) + 0.35 * raw[i] + 0.6 * harmony[i]
                i += 4
            }
            if s > bestScore { bestScore = s; bestPhase = phase }
        }
        // The first downbeat at or after the music starts is bar 0.
        let firstAudible = times.firstIndex { $0 >= start - 0.05 } ?? 0
        var zero = bestPhase
        while zero < firstAudible { zero += 4 }
        while zero - 4 >= firstAudible { zero -= 4 }
        return times.enumerated().map { i, t in
            let rel = i - zero
            let inBar = ((rel % 4) + 4) % 4
            let bar = Int((Double(rel) / 4).rounded(.down))
            return Beat(time: t, strength: strengths[i], inBar: inBar, bar: bar)
        }
    }

    // MARK: Drops

    /// Downbeats where the next two bars are much louder than the two before,
    /// best first in time order, at least four bars apart.
    static func findDrops(loudness: [Float], beats: [Beat], period: Double) -> [Double] {
        let rate = SongAnalysis.frameRate
        func mean(_ a: Double, _ b: Double) -> Float {
            let i = max(0, Int(a * rate)), j = min(loudness.count, Int(b * rate))
            guard j > i else { return 0 }
            var s: Float = 0
            for k in i..<j { s += loudness[k] }
            return s / Float(j - i)
        }
        let sorted = loudness.sorted()
        let loudish = sorted.isEmpty ? 1 : sorted[Int(Double(sorted.count - 1) * 0.55)]
        var candidates: [(time: Double, score: Float)] = []
        for b in beats where b.isDownbeat {
            let span = period * 8
            guard b.time - span >= 0 else { continue }
            let before = mean(b.time - span, b.time - period * 0.25)
            let after = mean(b.time + period * 0.1, b.time + span)
            let rise = after - before
            if rise > 0.12, after >= loudish { candidates.append((b.time, rise)) }
        }
        candidates.sort { $0.score > $1.score }
        var chosen: [Double] = []
        for c in candidates where chosen.allSatisfy({ abs($0 - c.time) >= period * 15.5 }) {
            chosen.append(c.time)
            if chosen.count == 6 { break }
        }
        return chosen.sorted()
    }
}
