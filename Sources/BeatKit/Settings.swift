import Foundation

// Everything a person can set in Deck Beat, as plain values. A preset sets
// the mode, the states, the intro and the atmosphere; it never touches the
// grid, the slides or the song.

/// How the music lights the grid.
public enum BeatMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case pulse
    case ripple
    case equaliser
    case readThrough
    case lightsOn

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pulse: return "Pulse"
        case .ripple: return "Ripple"
        case .equaliser: return "Equaliser"
        case .readThrough: return "Read-through"
        case .lightsOn: return "Lights On"
        }
    }

    public var summary: String {
        switch self {
        case .pulse: return "A few slides come up on every beat, more on the bar, and a shape on each downbeat."
        case .ripple: return "Each kick sends a ring of light out from the middle. Snares start smaller rings of their own."
        case .equaliser: return "Each column is a level meter: bass on the left, cymbals on the right."
        case .readThrough: return "The light reads the deck in order, one slide per beat."
        case .lightsOn: return "Windows in a block of flats after dark. Bass lights the lower floors, hats the roof."
        }
    }

    public var symbol: String {
        switch self {
        case .pulse: return "square.grid.3x3.middle.filled"
        case .ripple: return "dot.radiowaves.left.and.right"
        case .equaliser: return "chart.bar.fill"
        case .readThrough: return "text.line.first.and.arrowtriangle.forward"
        case .lightsOn: return "building.2"
        }
    }
}

/// One end of a slide's range: how it looks at rest, or fully lit.
public struct CellState: Codable, Hashable, Sendable {
    /// Size against the cell, 0.5…1.6.
    public var scale: Float
    /// 0…1.5; 1 is the slide as supplied.
    public var brightness: Float
    /// Colour, 0 (grey) … 1 (as supplied) … 1.3 (richer).
    public var colour: Float
    /// Towards the camera, in canvas heights, −0.10…0.15.
    public var lift: Float
    /// 0…1.
    public var glow: Float
    /// 0…1. Dim with brightness, not opacity: opacity lets the backdrop through.
    public var opacity: Float
    /// Extra softness in pixels at 1080, 0…24.
    public var blur: Float
    /// Degrees, 0…20, leaning away from where the light came from.
    public var tilt: Float
    /// Multiplies the cast shadow, 0…2.
    public var shadow: Float
    /// For filled cells: how far a card opens to its slide's own shape, 0…1.
    public var open: Float
    /// A colour laid over the slide like a gel, 0…1, and the gel's colour.
    public var tint: Float
    public var tintColour: String

    public init(scale: Float, brightness: Float, colour: Float, lift: Float, glow: Float, opacity: Float = 1,
                blur: Float = 0, tilt: Float = 0, shadow: Float = 1, open: Float = 0, tint: Float = 0, tintColour: String = "#FFFFFF") {
        self.scale = scale
        self.brightness = brightness
        self.colour = colour
        self.lift = lift
        self.glow = glow
        self.opacity = opacity
        self.blur = blur
        self.tilt = tilt
        self.shadow = shadow
        self.open = open
        self.tint = tint
        self.tintColour = tintColour
    }

    public static let rest = CellState(scale: 0.95, brightness: 0.4, colour: 0.2, lift: 0, glow: 0, shadow: 0.4)
    public static let lit = CellState(scale: 1.06, brightness: 1, colour: 1, lift: 0.04, glow: 0.25, tilt: 2, shadow: 1.2)
}

/// Slow movement at rest; it fades as a slide lights.
public enum IdleMotion: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, breathe, float, sway
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return "Still"
        case .breathe: return "Breathe"
        case .float: return "Float"
        case .sway: return "Sway"
        }
    }
}

/// How a slide comes up and goes down.
public struct Motion: Codable, Hashable, Sendable {
    /// Seconds to come up, ending on the hit: 0…0.2.
    public var attack: Double = 0.05
    /// Beats held at full before falling: 0…0.5.
    public var hold: Double = 0.25
    /// Beats to fall back to rest: 0.25…4.
    public var release: Double = 1
    /// Spring overshoot on size and lift, 0…0.25.
    public var bounce: Float = 0.08
    public var idle: IdleMotion = .breathe
    /// 0…1.
    public var idleAmount: Float = 0.25

    public init() {}
}

/// Which parts of the song set the lights off.
public enum Listen: String, Codable, CaseIterable, Identifiable, Sendable {
    case everything, drums, bass, melody
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .everything: return "Everything"
        case .drums: return "Drums"
        case .bass: return "Bass"
        case .melody: return "Melody"
        }
    }
}

/// The shape of each cell.
public enum CellShape: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Slide-shaped when that fills the frame well, filled otherwise.
    case auto
    /// The slides' own shape, nothing cropped.
    case slide
    /// Cells fill the frame; slides are cropped around their focal point.
    case fill
    case square

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .slide: return "Slide"
        case .fill: return "Fill"
        case .square: return "Square"
        }
    }
}

/// Room left around the grid.
public enum Margins: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Clear of the app interface on Reels, TikTok and Shorts in a tall frame.
    case safe
    case even
    case bleed

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .safe: return "Safe"
        case .even: return "Even"
        case .bleed: return "Edge"
        }
    }

    /// Insets as fractions of the canvas: left/right of its width, top and bottom of its height.
    public func insets(aspect: Float) -> (side: Float, top: Float, bottom: Float) {
        switch self {
        // Reels: 60 px at the sides, 220 above and 340 below, at 1080 × 1920.
        case .safe: return aspect < 0.8 ? (60 / 1080, 220 / 1920, 340 / 1920) : (0.06, 0.08, 0.08)
        case .even: return aspect < 0.8 ? (0.06, 0.06 * aspect, 0.06 * aspect) : (0.05 / aspect, 0.05, 0.05)
        case .bleed: return (0.012, 0.012 * aspect, 0.012 * aspect)
        }
    }

    /// Where the platform's own interface covers a frame of `aspect`, as shares
    /// of the frame: its header, its caption and buttons, and the button column
    /// on the right. The same numbers as the stage's safe-area guides and the
    /// titles (StudioKit's SafeAreaGuides and TitleArt.insets).
    public static func platform(aspect: Float) -> (top: Float, bottom: Float, right: Float) {
        if aspect < 0.62 { return (0.10, 0.22, 0.18) }  // Reels, TikTok, Shorts
        if aspect < 0.9 { return (0.06, 0.12, 0) }      // portrait feed posts
        return (0, 0, 0)
    }
}

/// Turning the whole grid like a wall seen at an angle.
public struct Wall: Codable, Hashable, Sendable {
    /// Degrees; positive tips the top away.
    public var pitch: Float = 0
    /// Degrees; positive turns the right side away.
    public var yaw: Float = 0
    /// A mirror floor under the wall, 0…1.
    public var reflection: Float = 0

    public init(pitch: Float = 0, yaw: Float = 0, reflection: Float = 0) {
        self.pitch = pitch
        self.yaw = yaw
        self.reflection = reflection
    }

    public static let flat = Wall()
    public static let lean = Wall(pitch: 10)
    public static let angle = Wall(pitch: 4, yaw: -18, reflection: 0.3)

    public var isFlat: Bool { abs(pitch) < 0.01 && abs(yaw) < 0.01 }
}

/// Which slide goes in which cell.
public enum SlideOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    /// In order; with odd rows and odd columns the cover takes the middle cell.
    case reading
    case shuffle
    /// The cover in the middle cell, whatever the grid.
    case coverCentre

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .reading: return "In order"
        case .shuffle: return "Shuffled"
        case .coverCentre: return "Cover in the middle"
        }
    }
}

public struct GridSettings: Codable, Hashable, Sendable {
    public var columns = 3
    public var rows = 5
    /// Pixels at 1080 on the short side, 0…80.
    public var gap: Float = 20
    /// Corner radius in pixels at 1080, 0…40.
    public var corner: Float = 12
    public var margins: Margins = .safe
    public var shape: CellShape = .auto
    public var wall = Wall.flat
    public var order: SlideOrder = .reading
    /// With more slides than cells, resting cells turn over on the downbeats to
    /// show the rest; off keeps the first ones.
    public var rotate = true

    public init() {}

    public var cellCount: Int { max(1, columns) * max(1, rows) }

    public static let columnRange = 1...12
    public static let rowRange = 1...20
}

/// How the cards arrive.
public enum Entrance: String, Codable, CaseIterable, Identifiable, Sendable {
    case deal, rise, depth, flip, drop, assemble, unfold, blinds, page, weave

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .deal: return "Deal"
        case .rise: return "Rise"
        case .depth: return "Depth"
        case .flip: return "Flip"
        case .drop: return "Drop"
        case .assemble: return "Assemble"
        case .unfold: return "Unfold"
        case .blinds: return "Blinds"
        case .page: return "Page"
        case .weave: return "Weave"
        }
    }
    public var summary: String {
        switch self {
        case .deal: return "Dealt from a stack, arcing into place."
        case .rise: return "Up from just below, settling with a little spring."
        case .depth: return "Out of the distance, coming into focus."
        case .flip: return "Turning face on, column by column."
        case .drop: return "Falling in from above with one bounce."
        case .assemble: return "Gathering from a scatter."
        case .unfold: return "Opening like folded paper."
        case .blinds: return "Slats turning face on, top to bottom."
        case .page: return "Laid down like a page, from its left edge."
        case .weave: return "Threads sliding in from both sides and knitting together."
        }
    }
}

/// What the grid does on a drop, after the breath before it.
public enum DropMove: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Every slide lights from the middle out, with a flash and a push in.
    case light
    /// The slides come apart into threads over the bar before, and knit back on the hit.
    case weave
    /// The grid breaks into a tunnel of slides on the hit and comes home on a later downbeat.
    case tunnel
    /// Fanned out like a hand of cards, then home.
    case fan
    /// One strip of slides that steps along on every beat, then home.
    case strip

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .light: return "Light"
        case .weave: return "Weave"
        case .tunnel: return "Tunnel"
        case .fan: return "Fan"
        case .strip: return "Strip"
        }
    }
    public var summary: String {
        switch self {
        case .light: return "Every slide lights from the middle out, with a flash and a push in."
        case .weave: return "Over the bar before, each slide comes apart into threads; on the hit they knit back together."
        case .tunnel: return "On the hit the grid breaks into a tunnel of slides that turns towards you, then comes home on a downbeat."
        case .fan: return "On the hit the slides fan out like a hand of cards, the cover on top, then come home on a downbeat."
        case .strip: return "On the hit the grid becomes one strip of slides that steps along on every beat, then comes home on a downbeat."
        }
    }

    /// The grid leaves its cells for a shape and comes home.
    public var reforms: Bool { self == .tunnel || self == .fan || self == .strip }
}

/// How a featured slide is brought forward.
public enum FeatureStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// It steps out of the grid towards the camera.
    case lift
    /// The camera moves in on it where it hangs, and the grid falls away round the edges.
    case zoom

    public var id: String { rawValue }
    public var title: String { self == .lift ? "Step out" : "Zoom in" }
}

/// How a cell turns over to show another slide.
public enum TurnStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case flip, blinds, wipe, page

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .flip: return "Flip"
        case .blinds: return "Blinds"
        case .wipe: return "Wipe"
        case .page: return "Page"
        }
    }
}

/// The order cards land in.
public enum StaggerOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case centreOut, diagonal, reading, spiral, columns, rows, random

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .centreOut: return "Centre out"
        case .diagonal: return "Diagonal"
        case .reading: return "Reading"
        case .spiral: return "Spiral"
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .random: return "Random"
        }
    }
}

public struct IntroSettings: Codable, Hashable, Sendable {
    /// Frame 0 is the first slide, large and lit: the cover, never black.
    public var coldOpen = true
    public var entrance: Entrance = .deal
    public var order: StaggerOrder = .centreOut
    /// Bars, or 0 for the fewest of 1, 2 or 4 bars that last at least 1.6 seconds.
    public var bars = 0

    public init() {}
}

/// How the clip ends.
public enum Outro: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Loop for clips of 30 seconds or less, Close for longer ones.
    case auto
    /// The cards gather back into the cover, so the last frame meets the first.
    case loop
    /// The cards leave in reverse and the cover rises to hold the end.
    case close
    /// The slides go dark one by one; the cover goes last and holds.
    case lightsOut
    case none

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .loop: return "Loop"
        case .close: return "Close"
        case .lightsOut: return "Lights out"
        case .none: return "None"
        }
    }
}

/// How often one slide steps out of the grid to be read.
public enum FeatureEvery: Int, Codable, CaseIterable, Identifiable, Sendable {
    case off = 0, oneBar = 1, twoBars = 2, fourBars = 4, eightBars = 8, sixteenBars = 16

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .off: return "Off"
        case .oneBar: return "1 bar"
        case .twoBars: return "2 bars"
        default: return "\(rawValue) bars"
        }
    }
}

/// Everything about the picture that is not the slides, the song or the canvas.
public struct BeatSettings: Codable, Hashable, Sendable {
    public var mode: BeatMode = .pulse
    public var rest = CellState.rest
    public var lit = CellState.lit
    public var motion = Motion()
    public var grid = GridSettings()
    public var intro = IntroSettings()
    public var outro: Outro = .auto
    public var feature: FeatureEvery = .fourBars
    /// Spotlight: the grid behind a featured slide steps right back.
    public var spotlight = false
    public var featureStyle: FeatureStyle = .lift
    /// 0…1: how readily the grid answers, and how much of it.
    public var sensitivity: Float = 0.6
    public var listen: Listen = .everything
    /// 0…1: backdrop pulse, camera punch and glow around the grid.
    public var atmosphere: Float = 0.5
    /// The breath before a drop and the hit on it.
    public var drops = true
    public var dropMove: DropMove = .light
    /// How cells turn over to show the rest of a big deck.
    public var turn: TurnStyle = .flip
    /// Ripple: how long a ring takes to cross the grid, in beats, 0.25…2.
    public var spread: Float = 0.75
    /// Read-through steps, in beats, or 0 to fit one pass of the deck to four bars.
    public var step: Double = 0
    /// Equaliser columns grow from the middle row instead of the bottom.
    public var fromMiddle = false
    public var seed: UInt32 = 1

    public init() {}
}

/// The part of the song a video uses.
public enum ClipLength: Int, Codable, CaseIterable, Identifiable, Sendable {
    case whole = 0, s15 = 15, s30 = 30, s60 = 60, s90 = 90

    public var id: Int { rawValue }
    public var title: String { self == .whole ? "Whole song" : "\(rawValue) s" }
    public var seconds: Double? { self == .whole ? nil : Double(rawValue) }
}

public struct Clip: Codable, Hashable, Sendable {
    public var length: ClipLength = .s30
    /// Seconds into the song; ignored for the whole song.
    public var start: Double = 0
    /// The start follows the best part of the song.
    public var bestPart = true

    public init(length: ClipLength = .s30, start: Double = 0, bestPart: Bool = true) {
        self.length = length
        self.start = start
        self.bestPart = bestPart
    }

    /// The start and length within a song of `duration`.
    public func range(duration: Double) -> (start: Double, length: Double) {
        guard let seconds = length.seconds, seconds < duration - 0.5 else { return (0, max(duration, 0.5)) }
        let s = min(max(start, 0), max(0, duration - seconds))
        return (s, seconds)
    }
}

// MARK: - Reading saved settings

// Projects saved by an older or newer Deck Beat open as they were: a setting
// the file leaves out, or one this version cannot read, keeps its default
// rather than failing the whole project.

extension KeyedDecodingContainer {
    /// Overwrites `value` with the saved one when the key is there and readable.
    public func update<T: Decodable>(_ value: inout T, _ key: Key) {
        if let v = try? decodeIfPresent(T.self, forKey: key) { value = v }
    }
}

extension CellState {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(scale: 1, brightness: 1, colour: 1, lift: 0, glow: 0)
        c.update(&scale, .scale)
        c.update(&brightness, .brightness)
        c.update(&colour, .colour)
        c.update(&lift, .lift)
        c.update(&glow, .glow)
        c.update(&opacity, .opacity)
        c.update(&blur, .blur)
        c.update(&tilt, .tilt)
        c.update(&shadow, .shadow)
        c.update(&open, .open)
        c.update(&tint, .tint)
        c.update(&tintColour, .tintColour)
    }
}

extension Motion {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        c.update(&attack, .attack)
        c.update(&hold, .hold)
        c.update(&release, .release)
        c.update(&bounce, .bounce)
        c.update(&idle, .idle)
        c.update(&idleAmount, .idleAmount)
    }
}

extension Wall {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        c.update(&pitch, .pitch)
        c.update(&yaw, .yaw)
        c.update(&reflection, .reflection)
    }
}

extension GridSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        c.update(&columns, .columns)
        c.update(&rows, .rows)
        c.update(&gap, .gap)
        c.update(&corner, .corner)
        c.update(&margins, .margins)
        c.update(&shape, .shape)
        c.update(&wall, .wall)
        c.update(&order, .order)
        c.update(&rotate, .rotate)
    }
}

extension IntroSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        c.update(&coldOpen, .coldOpen)
        c.update(&entrance, .entrance)
        c.update(&order, .order)
        c.update(&bars, .bars)
    }
}

extension BeatSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        c.update(&mode, .mode)
        c.update(&rest, .rest)
        c.update(&lit, .lit)
        c.update(&motion, .motion)
        c.update(&grid, .grid)
        c.update(&intro, .intro)
        c.update(&outro, .outro)
        c.update(&feature, .feature)
        c.update(&spotlight, .spotlight)
        c.update(&featureStyle, .featureStyle)
        c.update(&sensitivity, .sensitivity)
        c.update(&listen, .listen)
        c.update(&atmosphere, .atmosphere)
        c.update(&drops, .drops)
        c.update(&dropMove, .dropMove)
        c.update(&turn, .turn)
        c.update(&spread, .spread)
        c.update(&step, .step)
        c.update(&fromMiddle, .fromMiddle)
        c.update(&seed, .seed)
    }
}

extension Clip {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        c.update(&length, .length)
        c.update(&start, .start)
        c.update(&bestPart, .bestPart)
    }
}
