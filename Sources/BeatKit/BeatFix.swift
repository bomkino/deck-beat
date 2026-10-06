import Foundation

/// Corrections to the beat Deck Beat heard, for the songs it hears wrong: a
/// tempo felt twice as fast (or half), bar 1 a beat or more out, or a grid a
/// hair early or late against the music.
public struct BeatFix: Codable, Hashable, Sendable {
    public enum Speed: String, Codable, CaseIterable, Identifiable, Sendable {
        case half, asHeard, double

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .half: return "½×"
            case .asHeard: return "As heard"
            case .double: return "2×"
            }
        }
    }

    public var speed: Speed = .asHeard
    /// Beats the first beat of each bar moves later, 0…3.
    public var barShift = 0
    /// Seconds the whole grid moves, −0.15…0.15; positive is later.
    public var nudge: Double = 0

    public init(speed: Speed = .asHeard, barShift: Int = 0, nudge: Double = 0) {
        self.speed = speed
        self.barShift = barShift
        self.nudge = nudge
    }

    public static let none = BeatFix()
    public static let nudgeRange = -0.15...0.15

    public var isNone: Bool { self == .none }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        c.update(&speed, .speed)
        c.update(&barShift, .barShift)
        c.update(&nudge, .nudge)
    }
}

public extension SongAnalysis {
    /// The same listening with its beat grid corrected: the sound, onsets and
    /// spectrum are untouched; the beats, bars, tempo and drops follow the fix.
    func fixed(_ fix: BeatFix) -> SongAnalysis {
        guard !fix.isNone, beats.count >= 2 else { return self }
        // A downbeat to count bars from, before the grid changes.
        let zero = beats.firstIndex { $0.isDownbeat && $0.bar == 0 } ?? beats.firstIndex(where: \.isDownbeat) ?? 0
        var times = beats.map(\.time)
        var strengths = beats.map(\.strength)
        var zeroIndex = zero
        var tempo = self.tempo
        switch fix.speed {
        case .double:
            var t: [Double] = [], s: [Float] = []
            for i in times.indices {
                t.append(times[i])
                s.append(strengths[i])
                if i + 1 < times.count {
                    t.append((times[i] + times[i + 1]) / 2)
                    s.append(min(strengths[i], strengths[i + 1]) * 0.6)
                }
            }
            times = t
            strengths = s
            zeroIndex = zero * 2
            tempo *= 2
        case .half:
            // Every other beat, keeping the downbeats.
            let keep = times.indices.filter { ($0 - zero) % 2 == 0 }
            times = keep.map { times[$0] }
            strengths = keep.map { strengths[$0] }
            zeroIndex = keep.firstIndex(of: zero) ?? 0
            tempo /= 2
        case .asHeard:
            break
        }
        zeroIndex += max(0, min(fix.barShift, 3))
        let nudge = min(max(fix.nudge, BeatFix.nudgeRange.lowerBound), BeatFix.nudgeRange.upperBound)
        let fixedBeats = times.indices.map { i -> Beat in
            let rel = i - zeroIndex
            return Beat(time: times[i] + nudge, strength: strengths[i], inBar: ((rel % 4) + 4) % 4,
                        bar: Int((Double(rel) / 4).rounded(.down)))
        }
        let drops = SongAnalyzer.findDrops(loudness: loudness, beats: fixedBeats, period: 60 / max(tempo, 1))
        return SongAnalysis(duration: duration, bands: bands, loudness: loudness, brightness: brightness, flux: flux, spectrum: spectrum,
                            onsets: onsets, tempo: tempo, confidence: confidence, beats: fixedBeats, drops: drops, start: start, end: end)
    }
}
