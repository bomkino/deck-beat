import Foundation

// Ready-made settings that don't need the room: idle and active pairs, and
// the moves behind the Looks new in 6.0. Pure values, so beat-lab can check
// them without a GPU.

/// A pair of states: how a slide looks idle (at rest) and active (lit).
public struct StatePreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let idle: CellState
    public let active: CellState
    /// Spring overshoot it brings, if it changes it.
    public let bounce: Float?

    public init(id: String, name: String, summary: String, idle: CellState, active: CellState, bounce: Float? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.idle = idle
        self.active = active
        self.bounce = bounce
    }

    /// Sets the idle and active states (and the bounce, where the preset has one).
    public func apply(_ s: inout BeatSettings) {
        s.rest = idle
        s.lit = active
        if let bounce { s.motion.bounce = bounce }
    }

    /// The settings already wear this pair.
    public func matches(_ s: BeatSettings) -> Bool {
        s.rest == idle && s.lit == active && (bounce == nil || s.motion.bounce == bounce)
    }

    public static let all: [StatePreset] = [
        StatePreset(id: "dim-bright", name: "Dim to bright", summary: "Waiting in the dark, full and lifted on the beat.",
                    idle: .rest, active: .lit),
        StatePreset(id: "grey-colour", name: "Grey to colour", summary: "Every slide in full light but grey; the beat brings the colour.",
                    idle: CellState(scale: 0.97, brightness: 0.95, colour: 0, lift: 0, glow: 0, shadow: 0.5),
                    active: CellState(scale: 1.04, brightness: 1, colour: 1.1, lift: 0.03, glow: 0.1, tilt: 1.5, shadow: 1.2)),
        StatePreset(id: "soft-sharp", name: "Soft to sharp", summary: "Out of focus and a little small; the beat pulls a slide sharp.",
                    idle: CellState(scale: 0.92, brightness: 0.7, colour: 0.6, lift: 0, glow: 0, blur: 8, shadow: 0.3),
                    active: CellState(scale: 1.05, brightness: 1, colour: 1, lift: 0.05, glow: 0.15, tilt: 2, shadow: 1.3)),
        StatePreset(id: "ghost", name: "Ghost", summary: "Faint and see-through; the beat makes a slide solid and glowing.",
                    idle: CellState(scale: 0.95, brightness: 0.8, colour: 0.3, lift: 0, glow: 0, opacity: 0.25, shadow: 0),
                    active: CellState(scale: 1.04, brightness: 1.05, colour: 1, lift: 0.04, glow: 0.35, shadow: 1)),
        StatePreset(id: "spotlight", name: "Spotlight", summary: "Nearly black; the beat throws a slide into a bright, glowing pool.",
                    idle: CellState(scale: 0.94, brightness: 0.08, colour: 0.2, lift: 0, glow: 0, shadow: 0.2),
                    active: CellState(scale: 1.08, brightness: 1.15, colour: 1.05, lift: 0.06, glow: 0.4, tilt: 3, shadow: 1.8)),
        StatePreset(id: "neon", name: "Neon", summary: "Cool and dark at rest; warm, rich and glowing on the beat.",
                    idle: CellState(scale: 0.95, brightness: 0.25, colour: 0.4, lift: 0, glow: 0, shadow: 0.3, tint: 0.35, tintColour: "#5B7CFA"),
                    active: CellState(scale: 1.06, brightness: 1.1, colour: 1.2, lift: 0.04, glow: 0.6, shadow: 1, tint: 0.25, tintColour: "#FF5FA2")),
        StatePreset(id: "paper", name: "Paper", summary: "Pale prints lying flat; the beat lifts one off the wall, crisp.",
                    idle: CellState(scale: 0.96, brightness: 0.9, colour: 0.5, lift: 0, glow: 0, shadow: 0.25),
                    active: CellState(scale: 1.03, brightness: 1.02, colour: 1.05, lift: 0.07, glow: 0.05, tilt: 1.5, shadow: 1.6)),
        StatePreset(id: "pop", name: "Pop", summary: "Small and quiet; the beat makes a slide big, with a bounce.",
                    idle: CellState(scale: 0.85, brightness: 0.55, colour: 0.5, lift: 0, glow: 0, shadow: 0.3),
                    active: CellState(scale: 1.15, brightness: 1.05, colour: 1.15, lift: 0.06, glow: 0.2, tilt: 3, shadow: 1.4),
                    bounce: 0.2),
    ]

    public static func preset(_ id: String) -> StatePreset? { all.first { $0.id == id } }
}

/// The moves of the Looks new in 6.0, without their rooms.
public enum LookMoves {
    /// Beat by Beat: the board builds on the beat from the empty room, each
    /// slide comes in and answers by its own sound, and leaves on the beat.
    public static func beatByBeat(_ s: inout BeatSettings) {
        s.mode = .voices
        s.sensitivity = 0.6
        s.intro.pace = .beats
        s.intro.entrance = .voices
        s.intro.order = .scatter
        s.intro.coldOpen = false
        s.outro = .leave
        s.motion.feel = 0.6
        s.motion.idle = .breathe
        s.motion.idleAmount = 0.2
        s.rest = CellState(scale: 0.95, brightness: 0.35, colour: 0.25, lift: 0, glow: 0, shadow: 0.45)
        s.lit = CellState(scale: 1.06, brightness: 1, colour: 1, lift: 0.04, glow: 0.25, tilt: 2, shadow: 1.2)
        s.feature = .eightBars
        s.featureStyle = .zoom
        s.dropMove = .light
        s.atmosphere = 0.55
    }

    /// Paste-up: a loose board of prints, built on the song's own hits,
    /// that drifts away at the end.
    public static func pasteUp(_ s: inout BeatSettings) {
        s.mode = .pulse
        s.sensitivity = 0.55
        s.loose = 0.55
        s.intro.pace = .hits
        s.intro.entrance = .voices
        s.intro.order = .scatter
        s.intro.coldOpen = false
        s.outro = .driftAway
        s.motion.feel = 0.75
        s.motion.idle = .sway
        s.motion.idleAmount = 0.15
        StatePreset.preset("paper")?.apply(&s)
        s.feature = .fourBars
        s.featureStyle = .lift
        s.dropMove = .fan
        s.turn = .page
    }

    /// Mosaic: a wall of fifty slides or more. Rings of light cross it, it
    /// builds on every hit, the camera reads one every four bars, and the
    /// slides take a curtain call. Every slide stays on the wall.
    public static func mosaic(_ s: inout BeatSettings) {
        s.mode = .ripple
        s.spread = 0.6
        s.sensitivity = 0.6
        s.intro.pace = .hits
        s.intro.entrance = .voices
        s.intro.order = .scatter
        s.intro.coldOpen = false
        s.outro = .curtainCall
        s.motion.feel = 0.4
        s.motion.bounce = 0.06
        s.motion.idle = .off
        s.rest = CellState(scale: 0.96, brightness: 0.4, colour: 0.35, lift: 0, glow: 0, shadow: 0.3)
        s.lit = CellState(scale: 1.04, brightness: 1.05, colour: 1.05, lift: 0.03, glow: 0.3, tilt: 2, shadow: 1)
        s.feature = .fourBars
        s.featureStyle = .zoom
        s.dropMove = .light
        s.grid.rotate = false
    }

    /// Afterglow: slow and warm. A gentle pulse brings slides into focus,
    /// a long tail lets them glow, and the board drifts away round the cover.
    public static func afterglow(_ s: inout BeatSettings) {
        s.mode = .pulse
        s.sensitivity = 0.4
        s.intro.pace = .beats
        s.intro.entrance = .depth
        s.intro.order = .scatter
        s.intro.coldOpen = false
        s.outro = .driftAway
        StatePreset.preset("soft-sharp")?.apply(&s)
        s.lit.glow = 0.3
        s.motion.release = 2.5
        s.motion.hold = 0.4
        s.motion.bounce = 0.04
        s.motion.feel = 0.5
        s.motion.idle = .float
        s.motion.idleAmount = 0.25
        s.feature = .eightBars
        s.featureStyle = .lift
        s.dropMove = .light
        s.atmosphere = 0.4
    }
}
