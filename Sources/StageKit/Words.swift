import Foundation

/// Words set over the finished frame: a title with an optional short line
/// above it. The app sets the type; the exporter places it in time.
public struct ReelTitle: Codable, Hashable, Sendable {
    public enum Placement: String, Codable, CaseIterable, Sendable {
        /// Small, in a corner clear of platform controls, like a caption.
        case corner
        /// Large and centred over a dimmed stage, like a title card.
        case centre

        public var title: String { self == .corner ? "Caption" : "Title card" }
    }

    public enum Timing: String, Codable, CaseIterable, Sendable {
        case throughout, opening, closing

        public var title: String {
            switch self {
            case .throughout: return "Throughout"
            case .opening: return "Opening"
            case .closing: return "Closing"
            }
        }
    }

    public enum Ink: String, Codable, CaseIterable, Sendable {
        case auto, light, dark

        public var title: String { rawValue.capitalized }
    }

    /// The typeface the words are set in.
    public enum Face: String, Codable, CaseIterable, Sendable {
        /// pitch.dog's own type: PD Head for the title, PD Eyebrow for the line above.
        case pitchdog
        /// PD Head italic for the title.
        case pitchdogItalic = "pitchdog-italic"
        case modern, grotesk, editorial, poster

        public var title: String {
            switch self {
            case .pitchdog: return "pitch.dog"
            case .pitchdogItalic: return "pitch.dog Italic"
            case .modern: return "Modern"
            case .grotesk: return "Grotesk"
            case .editorial: return "Editorial"
            case .poster: return "Poster"
            }
        }
    }

    /// How words that land on the beat arrive.
    public enum Motion: String, Codable, CaseIterable, Sendable {
        /// Each group falls onto its beat with a small give.
        case land
        /// Each group grows in from 85 % with a little overshoot, full size on its beat.
        case pop
        /// Each group rises into place from behind its own line, like a title sequence.
        case reveal

        public var title: String {
            switch self {
            case .land: return "Land"
            case .pop: return "Pop"
            case .reveal: return "Reveal"
            }
        }
    }

    public var text: String
    /// The short line above the title, such as a date or a client.
    public var kicker: String
    public var placement: Placement
    public var timing: Timing
    public var ink: Ink
    public var face: Face
    /// The words land a few at a time on the beat instead of rising in together.
    public var beat: Bool
    /// How they land, when they land on the beat.
    public var motion: Motion

    /// A new title is set in pitch.dog type; a saved one keeps the face it was saved with.
    public init(text: String = "", kicker: String = "", placement: Placement = .corner, timing: Timing = .throughout, ink: Ink = .auto,
                face: Face = .pitchdog, beat: Bool = false, motion: Motion = .land) {
        self.text = text
        self.kicker = kicker
        self.placement = placement
        self.timing = timing
        self.ink = ink
        self.face = face
        self.beat = beat
        self.motion = motion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        kicker = try c.decodeIfPresent(String.self, forKey: .kicker) ?? ""
        placement = try c.decodeIfPresent(Placement.self, forKey: .placement) ?? .corner
        timing = try c.decodeIfPresent(Timing.self, forKey: .timing) ?? .throughout
        ink = try c.decodeIfPresent(Ink.self, forKey: .ink) ?? .auto
        face = try c.decodeIfPresent(Face.self, forKey: .face) ?? .modern
        beat = try c.decodeIfPresent(Bool.self, forKey: .beat) ?? false
        motion = (try? c.decodeIfPresent(Motion.self, forKey: .motion)) ?? .land
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && kicker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The groups of title words that land together on the beat, as UTF-16
    /// ranges of the trimmed title. A word shorter than seven characters waits
    /// for the next, so small words never land on their own.
    public static func groups(_ text: String) -> [Range<Int>] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var words: [Range<Int>] = []
        var offset = 0
        var start: Int?
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if let s = start { words.append(s..<offset) }
                start = nil
            } else if start == nil {
                start = offset
            }
            offset += scalar.utf16.count
        }
        if let s = start { words.append(s..<offset) }
        var groups: [Range<Int>] = []
        var open: Range<Int>?
        var letters = 0
        for w in words {
            open = open.map { $0.lowerBound..<w.upperBound } ?? w
            letters += w.count
            if letters >= 7, let g = open {
                groups.append(g)
                open = nil
                letters = 0
            }
        }
        if let g = open { groups.append(g) }
        return groups
    }

    /// How many times the words land on the beat: the line above at once, then each group of the title.
    public var beatGroups: Int {
        (kicker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1) + Self.groups(text).count
    }
}

/// When one group of a title's words lands on the beat, and when it lifts off again.
public struct WordCue: Hashable, Sendable {
    /// The beat it lands on, in loop time.
    public var land: Double
    /// When it starts to lift off; infinity while the title stays.
    public var leave: Double
    /// How long the fall onto the beat, and the lift away, take.
    public var lead: Double

    public init(land: Double, leave: Double = .infinity, lead: Double) {
        self.land = land
        self.leave = leave
        self.lead = lead
    }

    /// Opacity, and how far below its place the group sits (a share of the frame height, negative above), at loop time `u`.
    /// It drops in from just above and hits its place on the beat with a small give, then lifts away the way it came.
    public func presence(at u: Double) -> (alpha: Float, drop: Float) {
        let lead = max(self.lead, 1e-3)
        let fall = Float(min(max((u - (land - lead)) / lead, 0), 1))
        guard fall > 0 else { return (0, 0) }
        let rest = 1 - fall
        var drop = -0.016 * rest * rest
        let after = Float((u - land) / 0.14)
        if after > 0, after < 1 { drop += 0.0035 * sinf(.pi * after) * (1 - after) }
        var alpha = Ease.smooth(fall / 0.7)
        if leave.isFinite {
            let lift = Float(min(max((u - leave) / lead, 0), 1))
            alpha *= 1 - Ease.smooth(lift)
            drop -= 0.012 * lift * lift
        }
        return (alpha, drop)
    }

    /// Pop: opacity and size at loop time `u`. The group grows from 85 % with
    /// a small overshoot and is full size on its beat; it shrinks a little as it goes.
    public func pop(at u: Double) -> (alpha: Float, scale: Float) {
        let lead = max(self.lead, 1e-3)
        let k = Float(min(max((u - (land - lead)) / lead, 0), 1))
        guard k > 0 else { return (0, 0.85) }
        // Back-out: about 4 % over full size halfway in, home on the beat.
        let c: Float = 3
        let x = k - 1
        var scale = 0.85 + 0.15 * (1 + (c + 1) * x * x * x + c * x * x)
        let after = Float((u - land) / 0.12)
        if after > 0, after < 1 { scale += 0.006 * sinf(.pi * after) * (1 - after) }
        var alpha = Ease.smooth(k / 0.55)
        if leave.isFinite {
            let lift = Float(min(max((u - leave) / lead, 0), 1))
            alpha *= 1 - Ease.smooth(lift)
            scale *= 1 - 0.08 * Ease.smooth(lift)
        }
        return (alpha, scale)
    }

    /// Reveal: how much of a line's height the group still sits below its
    /// place at loop time `u`, 1 (hidden behind its line) to 0 (home on its
    /// beat). It sinks back the way it came as it goes.
    public func reveal(at u: Double) -> Float {
        let lead = max(self.lead, 1e-3)
        let k = Float(min(max((u - (land - lead)) / lead, 0), 1))
        guard k > 0 else { return 1 }
        var hidden = 1 - Ease.register(k)
        if leave.isFinite {
            let lift = Float(min(max((u - leave) / lead, 0), 1))
            hidden = max(hidden, Ease.place(lift))
        }
        return hidden
    }
}

/// Part of a drawn title that follows one cue: its rectangle in the frame as
/// (u0, v0, u1, v1), 0…1 with v down. The pieces of a title tile the frame.
public struct TitlePiece: Hashable, Sendable {
    public var rect: SIMD4<Float>
    public var cue: Int
    /// The words themselves, as (u0, v0, u1, v1): from the top of their capitals
    /// to the foot of their line. A pop grows from their middle; a reveal
    /// rises from behind their foot.
    public var words: SIMD4<Float>

    public init(rect: SIMD4<Float>, cue: Int, words: SIMD4<Float>? = nil) {
        self.rect = rect
        self.cue = cue
        self.words = words ?? rect
    }
}

extension ReelTitle.Timing {
    /// When an opening or closing title starts to rise in and starts to clear,
    /// and how long each fade takes; nil for a title shown throughout.
    public func window(loop: Double) -> (start: Double, fadeIn: Double, end: Double, fadeOut: Double)? {
        guard self != .throughout else { return nil }
        let margin = min(0.35, loop * 0.04)
        let fadeIn = min(0.8, loop * 0.1)
        let fadeOut = min(0.7, loop * 0.08)
        // How long the title holds at full strength.
        let hold = max(1.4, min(3.9, loop * 0.42) - margin - fadeIn)
        let start = self == .opening ? margin : max(loop * 0.3, loop - margin - fadeOut - hold - fadeIn)
        let end = min(start + fadeIn + hold, loop - fadeOut - margin)
        return (start, fadeIn, end, fadeOut)
    }
}
