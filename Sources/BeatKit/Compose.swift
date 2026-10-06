import BackdropKit
import Foundation
import Metal
import RenderCore
import StageKit

/// Where a clip sits in a song, and how it ends.
public struct ClipRange: Hashable, Sendable {
    public var start: Double
    public var length: Double
    /// The ending, with Auto settled: Loop for 30 seconds or less, Close otherwise.
    public var outro: Outro

    public init(start: Double, length: Double, outro: Outro) {
        self.start = start
        self.length = length
        self.outro = outro
    }
}

public extension Clip {
    /// The clip in `song`: it starts on a downbeat after any silence, lands the
    /// intro on an early drop when asked, and a loop runs whole bars.
    func resolve(_ a: SongAnalysis, settings s: BeatSettings, landOnDrop: Bool = true) -> ClipRange {
        let freeTime = a.confidence < 0.4 || a.tempo <= 0
        let period = a.tempo > 0 ? 60 / a.tempo : 0.5
        let bar = period * 4
        let downs = a.beats.filter(\.isDownbeat).map(\.time)
        let begin = max(0, a.start - 0.05)
        let end = max(min(a.duration, a.end + 0.5), begin + 0.5)
        func snap(_ t: Double) -> Double {
            guard !freeTime, let d = downs.min(by: { abs($0 - t) < abs($1 - t) }), abs(d - t) < bar * 0.5 else { return t }
            return d
        }
        let intro = Double(Composer.introBars(s, bar: bar)) * bar
        var start: Double
        var seconds: Double
        if let want = length.seconds, want < end - begin - 0.5 {
            seconds = want
            start = snap(bestPart ? a.bestSection(length: want, lead: intro) : self.start)
            // The cover lands on a drop that comes early in the clip.
            if landOnDrop, !freeTime, s.intro.coldOpen,
               let d = a.drops.first(where: { $0 > start + intro * 0.5 && $0 < start + 8 * bar }), d - intro >= begin - 0.02 {
                start = d - intro
            }
            start = min(max(start, 0), max(0, a.duration - seconds))
        } else {
            let first = downs.first(where: { $0 >= begin - 0.02 })
            start = first.map { $0 - begin < bar ? $0 : begin } ?? begin
            seconds = end - start
        }
        var outro = s.outro
        if outro == .auto { outro = seconds <= 30.5 ? .loop : .close }
        // A loop runs whole bars, so its last frame meets its first on the beat.
        if outro == .loop, !freeTime, bar > 0.2 {
            var bars = max(2, Int((seconds / bar).rounded()))
            while bars > 2, start + Double(bars) * bar > a.duration + 0.01 { bars -= 1 }
            seconds = Double(bars) * bar
            if let i = downs.firstIndex(where: { abs($0 - start) < 0.08 }), i + bars < downs.count {
                seconds = downs[i + bars] - start
            }
        }
        return ClipRange(start: start, length: max(0.5, seconds), outro: outro)
    }
}

/// Builds what the stage draws, for the app and the lab alike.
public enum Composer {
    /// Intro length in bars: as set, or the fewest of 1, 2 or 4 that last 1.6 s.
    public static func introBars(_ s: BeatSettings, bar: Double) -> Int {
        if s.intro.bars > 0 { return s.intro.bars }
        var bars = 1
        while bars < 4, Double(bars) * bar < 1.6 { bars *= 2 }
        return bars
    }

    /// The slides' usual shape: the middle of their aspects.
    public static func typicalAspect(_ aspects: [Float]) -> Float {
        guard !aspects.isEmpty else { return 16.0 / 9.0 }
        let sorted = aspects.sorted()
        return sorted[sorted.count / 2]
    }

    /// The choreography for a clip of `song` on a canvas of `aspect`.
    public static func plan(_ a: SongAnalysis, settings: BeatSettings, clip: ClipRange, aspect: Float, slideAspect: Float,
                            slides: Int, starred: Set<Int> = [], clear: Clearance = .none) -> (layout: GridLayout, plan: BeatPlan) {
        var s = settings
        s.outro = clip.outro
        let layout = GridLayout(settings: s.grid, aspect: aspect, slideAspect: slideAspect, clear: clear)
        let plan = Choreographer.plan(a, settings: s, layout: layout, slides: slides, clipStart: clip.start, clipLength: clip.length,
                                      starred: starred)
        return (layout, plan)
    }

    /// The composition: the grid scene over the backdrop, with the song moving the room.
    public static func composition(plan: BeatPlan, layout: GridLayout, settings: BeatSettings, stage: StageLook,
                                   backdrop: BackdropSettings, textures: [MTLTexture], aspects: [Float], focals: [SIMD2<Float>] = [],
                                   canvasAspect: Float, videos: [Int: VideoClip] = [:],
                                   modulate: (@Sendable (Double, inout StageLook, inout BackdropSettings) -> Void)? = nil) -> Composition {
        let items = aspects.enumerated().map { SceneItem(media: $0.offset, occurrence: $0.offset, aspect: $0.element) }
        let ctx = SceneContext(items: items, aspect: canvasAspect, dials: SceneDials(), seed: settings.seed)
        let scene = BeatScene(plan: plan, layout: layout, settings: settings, cornerScale: 0.4 + 1.6 * stage.corners, focals: focals)
        var comp = Composition(scene: scene, context: ctx, textures: textures, backdrop: backdrop, look: stage, backdropLoop: 14,
                               videos: videos)
        comp.modulate = modulate ?? Atmosphere.modulate(plan: plan, atmosphere: settings.atmosphere)
        return comp
    }
}
