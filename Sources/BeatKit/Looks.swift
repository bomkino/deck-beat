import BackdropKit
import Foundation
import RenderCore
import StageKit

/// A finished look: how the music lights the grid, how the slides rest and
/// play, how they arrive, and the room they hang in. A look never changes the
/// rows, the columns, the gap, the shape, the slides or the song.
public struct Look: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    /// Sets the mode, the states, the motion and the intro.
    public let apply: @Sendable (inout BeatSettings) -> Void
    /// The backdrop, taking the deck's own colours when the look follows them.
    public let backdrop: @Sendable (_ deck: Palette?) -> BackdropSettings
    /// The surface and the finish.
    public let stage: StageLook

    public init(id: String, name: String, summary: String, apply: @escaping @Sendable (inout BeatSettings) -> Void,
                backdrop: @escaping @Sendable (_ deck: Palette?) -> BackdropSettings, stage: StageLook) {
        self.id = id
        self.name = name
        self.summary = summary
        self.apply = apply
        self.backdrop = backdrop
        self.stage = stage
    }
}

public enum Looks {
    public static let defaultID = "screening-room"

    public static func look(_ id: String) -> Look { all.first { $0.id == id } ?? all[0] }

    /// Settings with `look` applied over `base`, keeping its grid, seed and clip choices.
    public static func settings(_ look: Look, over base: BeatSettings) -> BeatSettings {
        var s = BeatSettings()
        s.grid = base.grid
        s.grid.wall = .flat
        s.seed = base.seed
        look.apply(&s)
        return s
    }

    static func stage(surface: SurfaceKind, bloom: Float, grain: Float, vignette: Float, bend: Float = 0,
                      shadow: Float = 0.55) -> StageLook {
        var look = StageLook()
        look.surface = surface
        look.bend = bend > 0 ? .paper : .rigid
        look.bendAmount = bend
        // 0.375 makes the stage's corner factor exactly 1, so corners come out in pixels.
        look.corners = 0.375
        look.depthOfField = 0
        look.shutter = 0.4
        look.shadow = shadow
        look.shadowSoftness = 0.6
        look.finish.bloom = bloom
        look.finish.grain = grain
        look.finish.grainSize = 0.3
        look.finish.vignette = vignette
        return look
    }

    static func studio(_ hexes: [String], brightness: Float = 1, accent: Float = 0.35, detail: Float = 0.55) -> BackdropSettings {
        var b = BackdropCatalog.style("studio").defaults
        b.palette = Palette("Studio", hexes)
        b.brightness = brightness
        b.accent = accent
        b.detail = detail
        b.motion = 0.25
        return b
    }

    public static let all: [Look] = [
        Look(id: "screening-room", name: "Screening Room",
             summary: "Slides wait in the dark and come up in colour on the beat. Every fourth bar, one steps forward to be read.",
             apply: { s in
                 s.mode = .pulse
                 s.sensitivity = 0.6
             },
             backdrop: { _ in studio(["#0B0C0D", "#141517", "#1B1D20", "#26292E", "#33373D"]) },
             stage: stage(surface: .satin, bloom: 0.15, grain: 0.06, vignette: 0.25)),

        Look(id: "night-shift", name: "Night Shift",
             summary: "A block of flats after dark. The music decides who is home.",
             apply: { s in
                 s.mode = .lightsOn
                 s.sensitivity = 0.7
                 s.feature = .off
                 s.rest = CellState(scale: 0.95, brightness: 0.15, colour: 0, lift: 0, glow: 0, shadow: 0.3, tint: 0.15, tintColour: "#8FA6BF")
                 s.lit = CellState(scale: 1, brightness: 1, colour: 1, lift: 0, glow: 0.45, shadow: 1, tint: 0.2, tintColour: "#FFB46B")
                 s.motion.attack = 0.02
                 s.motion.hold = 0
                 s.motion.release = 1.5
                 s.motion.bounce = 0
                 s.motion.idle = .off
                 s.intro.entrance = .rise
                 s.intro.order = .random
                 s.intro.bars = 2
                 s.outro = .lightsOut
             },
             backdrop: { _ in studio(["#000000", "#030304", "#07080A", "#0D0F12", "#15181C"], brightness: 0.8, accent: 0.2) },
             stage: stage(surface: .original, bloom: 0.3, grain: 0.12, vignette: 0.4)),

        Look(id: "ripple", name: "Ripple",
             summary: "Each kick sends a ring out from the middle. Snares start smaller rings of their own.",
             apply: { s in
                 s.mode = .ripple
                 s.spread = 0.75
                 s.feature = .eightBars
                 s.rest = CellState(scale: 0.95, brightness: 0.35, colour: 0.2, lift: 0, glow: 0, blur: 2, shadow: 0.4)
                 s.lit = CellState(scale: 1.05, brightness: 1, colour: 1, lift: 0.05, glow: 0.35, tilt: 4, shadow: 1.2)
                 s.motion.bounce = 0.1
                 s.motion.idle = .float
                 s.motion.idleAmount = 0.2
                 s.intro.entrance = .depth
                 s.intro.order = .centreOut
             },
             backdrop: { deck in
                 var b = BackdropCatalog.style("aurora").defaults
                 if let deck { b.palette = darkened(deck) }
                 b.brightness = 0.7
                 return b
             },
             stage: stage(surface: .satin, bloom: 0.25, grain: 0.08, vignette: 0.3)),

        Look(id: "read-through", name: "Read-through",
             summary: "The light reads the deck in order, one slide per beat.",
             apply: { s in
                 s.mode = .readThrough
                 s.step = 0
                 s.feature = .off
                 s.rest = CellState(scale: 0.95, brightness: 0.55, colour: 0.5, lift: 0, glow: 0, blur: 1, shadow: 0.4)
                 s.lit = CellState(scale: 1.1, brightness: 1, colour: 1, lift: 0.06, glow: 0.15, tilt: 2, shadow: 1.3, open: 1)
                 s.motion.bounce = 0.12
                 s.intro.entrance = .deal
                 s.intro.order = .reading
                 s.intro.coldOpen = false
             },
             backdrop: { _ in
                 var b = BackdropCatalog.style("dotgrid").defaults
                 b.palette = Palettes.named("graphite")
                 b.brightness = 0.75
                 return b
             },
             stage: stage(surface: .print, bloom: 0.1, grain: 0.08, vignette: 0.25)),

        Look(id: "equaliser", name: "Equaliser",
             summary: "Bass on the left, cymbals on the right. Each column fills to the level of its part of the song.",
             apply: { s in
                 s.mode = .equaliser
                 s.fromMiddle = false
                 s.feature = .eightBars
                 s.rest = CellState(scale: 0.95, brightness: 0.3, colour: 0, lift: 0, glow: 0, shadow: 0.4)
                 s.lit = CellState(scale: 1.03, brightness: 1.1, colour: 1, lift: 0.02, glow: 0.2, shadow: 1)
                 s.motion.bounce = 0
                 s.intro.entrance = .rise
                 s.intro.order = .columns
             },
             backdrop: { _ in
                 var b = BackdropCatalog.style("halftone").defaults
                 b.palette = Palettes.named("sumi")
                 b.brightness = 0.55
                 return b
             },
             stage: stage(surface: .original, bloom: 0, grain: 0.08, vignette: 0.3)),

        Look(id: "gallery-wall", name: "Gallery Wall",
             summary: "The grid hung on an angled wall above a polished floor. For slower songs and quieter work.",
             apply: { s in
                 s.mode = .pulse
                 s.sensitivity = 0.45
                 s.grid.wall = .angle
                 s.rest = CellState(scale: 0.95, brightness: 0.6, colour: 0.7, lift: 0, glow: 0, shadow: 0.6)
                 s.lit = CellState(scale: 1.04, brightness: 1, colour: 1, lift: 0.12, glow: 0.15, tilt: 2, shadow: 2)
                 s.motion.release = 2
                 s.motion.bounce = 0.06
                 s.motion.idle = .sway
                 s.motion.idleAmount = 0.2
                 s.intro.entrance = .unfold
                 s.intro.order = .columns
             },
             backdrop: { _ in studio(["#17120D", "#221B14", "#2E251C", "#3D3226", "#53443A"], brightness: 0.85, accent: 0.45) },
             stage: stage(surface: .satin, bloom: 0.12, grain: 0.08, vignette: 0.3, bend: 0.3, shadow: 0.7)),

        Look(id: "light-box", name: "Light Box",
             summary: "A pale room for light decks. Resting slides go grey; playing slides come back in colour.",
             apply: { s in
                 s.mode = .pulse
                 s.rest = CellState(scale: 0.95, brightness: 0.95, colour: 0, lift: 0, glow: 0, opacity: 0.7, shadow: 0.3)
                 s.lit = CellState(scale: 1.05, brightness: 1, colour: 1, lift: 0.05, glow: 0, tilt: 2, shadow: 1.5)
                 s.intro.entrance = .rise
                 s.intro.order = .diagonal
             },
             backdrop: { _ in studio(["#D9D9D6", "#E3E3E0", "#EDEDEB", "#F3F3F1", "#FAFAF8"], brightness: 1, accent: 0.2, detail: 0.4) },
             stage: stage(surface: .print, bloom: 0, grain: 0.05, vignette: 0.08, bend: 0.2, shadow: 0.35)),
    ]

    /// The deck's colours, pulled down so the backdrop stays behind the slides.
    static func darkened(_ p: Palette) -> Palette {
        let sorted = p.sorted
        let colors = sorted.enumerated().map { i, c -> RGB in
            let k: Float = 0.25 + 0.45 * Float(i) / Float(max(sorted.count - 1, 1))
            return RGB(c.r * k, c.g * k, c.b * k)
        }
        return Palette(id: "deck", name: "From your slides", colors: colors)
    }
}

// MARK: - Atmosphere

/// What the song does to the room around the grid: the backdrop lifts on the
/// kick and holds its breath before a drop, the exposure flashes on it, and
/// the bloom follows how loud the song is. Scaled by `atmosphere`.
public enum Atmosphere {
    public static func modulate(plan: BeatPlan, atmosphere: Float) -> @Sendable (Double, inout StageLook, inout BackdropSettings) -> Void {
        let k = max(0, min(atmosphere, 1)) / 0.5
        // Loudness over the last three seconds.
        let loud = plan.loud
        var loud3 = [Float](repeating: 0, count: loud.count)
        let span = Int(3 * BeatPlan.rate)
        var sum: Float = 0
        for i in 0..<loud.count {
            sum += loud[i]
            if i >= span { sum -= loud[i - span] }
            loud3[i] = sum / Float(min(i + 1, span))
        }
        let smoothed = loud3
        return { t, look, backdrop in
            guard k > 0.001 else { return }
            let time = t > plan.length + 1e-6 ? wrap(t, plan.length) : max(t, 0)
            let kick = BeatPlan.sample(plan.pulse, time)
            let inhale = plan.inhale(at: time)
            let flash = plan.flash(at: time)
            let l3 = BeatPlan.sample(smoothed, time)
            // The loop's last moments ease back to how it began.
            var settle: Float = 1
            if plan.outro.kind == .loop {
                settle = smoothstep(0, 0.5, Float(time)) * (1 - smoothstep(Float(plan.length - 0.5), Float(plan.length), Float(time)))
            }
            backdrop.brightness *= max(0.2, 1 + (0.12 * kick - 0.2 * inhale) * k * settle)
            look.finish.exposure += 0.25 * flash * k
            look.finish.bloom = max(0, look.finish.bloom + 0.2 * (l3 - 0.5) * k * settle)
            look.finish.vignette += (0.05 * inhale + 0.1 * flash) * k
        }
    }
}
