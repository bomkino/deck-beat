import AVFoundation
import BeatKit
import CoreGraphics
import CoreMedia
import Foundation
import Metal
import RenderCore
import StageKit
import StudioKit

/// What `beat-lab check` proves on the GPU about a transparent export, as
/// Drift's verify does: ProRes 4444 holds straight alpha that matches the PNG
/// still, with and without a caption over it; the shadows reach the alpha;
/// the room around the grid is clear; and HEVC keeps transparency too.
enum TransparentExport {
    /// Runs the checks, prints a line for each, and returns how many failed.
    /// Without a Metal device it says so and passes.
    static func run() async -> Int {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("skipped: transparent export, no Metal device")
            return 0
        }
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String) {
            print("\(ok ? "ok  " : "FAIL") \(name): \(detail)")
            if !ok { failures += 1 }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("beat-lab-transparent", isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let song = Song.demo()
            let media = try (0..<DemoDeck.count).map { try MediaLoader.texture(from: DemoDeck.slide(index: $0)) }
            let exporter = try Exporter()
            let width = 540, height = 960
            let caption = ReelTitle(text: "Brightside raises its Series A", kicker: "pitch.dog · 2026", placement: .corner, timing: .throughout)
            for (variant, title) in [("plain", nil), ("caption", caption)] as [(String, ReelTitle?)] {
                let comp = composition(song: song, media: media, title: title, width: width, height: height)
                // The PNG still: premultiplied on the GPU, as PNG frames are.
                let still = try exporter.still(comp, at: 0, width: width, height: height, samples: 1, fps: 30, transparent: true)
                // 0.2 s of ProRes 4444; its first frame is the same moment.
                let movie = dir.appendingPathComponent("clear-\(variant).mov")
                let settings = ExportSettings(width: width, height: height, fps: 30, duration: 0.2, format: .video(.prores4444), samples: 1,
                                              transparent: true)
                try await exporter.export(comp, settings: settings, to: movie)
                let frame = try await firstFrame(of: movie)
                guard let a = straightPixels(still), let b = straightPixels(frame), frame.width == width, frame.height == height else {
                    check("transparent (\(variant))", false, "could not read the frames (movie \(frame.width)×\(frame.height))")
                    continue
                }
                let s = stats(still: a, movie: b)
                // The error on opaque pixels says how far decoding alone moves colours, for reading a failure.
                let detail = String(format: "straight-error %.2f shadow-share %.3f clear-share %.3f (opaque-error %.2f)",
                                    s.straightError, s.shadowShare, s.clearShare, s.opaqueError)
                // Drift's thresholds (scripts/verify.sh): straight alpha matches the PNG,
                // over 1 % of the frame is soft shadow, and over 0.5 % is fully clear.
                check("transparent (\(variant))", s.straightError < 3 && s.shadowShare > 0.01 && s.clearShare > 0.005, detail)
            }

            // HEVC with alpha: a QuickTime movie whose track says it carries alpha,
            // and whose first frame decodes with the room around the grid clear.
            let comp = composition(song: song, media: media, title: nil, width: width, height: height)
            let hevc = dir.appendingPathComponent("clear.hevc.mov")
            let settings = ExportSettings(width: width, height: height, fps: 30, duration: 0.2, format: .video(.hevcAlpha), samples: 1,
                                          transparent: true)
            try await exporter.export(comp, settings: settings, to: hevc)
            let asset = AVURLAsset(url: hevc)
            var hasAlpha = false
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let traits = try await track.load(.mediaCharacteristics)
                let descriptions = try await track.load(.formatDescriptions)
                let flagged = descriptions.contains { d in
                    (CMFormatDescriptionGetExtension(d, extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel) as? Bool) == true
                }
                hasAlpha = traits.contains(.containsAlphaChannel) || flagged
            }
            let frame = try await firstFrame(of: hevc)
            var clear = 0.0
            if let px = straightPixels(frame) {
                var n = 0
                for i in stride(from: 3, to: px.count, by: 4) where px[i] < 5 { n += 1 }
                clear = Double(n) / Double(max(1, px.count / 4))
            }
            check("transparent (HEVC)", hasAlpha && clear > 0.005,
                  String(format: "track %@ alpha, clear-share %.3f", hasAlpha ? "has" : "has no", clear))
        } catch {
            check("transparent export", false, "\(error)")
        }
        try? FileManager.default.removeItem(at: dir)
        return failures
    }

    /// The default Look on the demo deck and groove in a Reel, seen from just
    /// after the intro, so the grid is up with its shadows in an export's first frame.
    static func composition(song: Song, media: [MediaTexture], title: ReelTitle?, width: Int, height: Int) -> Composition {
        let made = Render.compose(Looks.look(Looks.defaultID), song: song, media: media, clip: Clip(length: .s15),
                                  aspect: Float(width) / Float(height), title: title, canvas: (w: width, h: height))
        let plan = made.plan
        let moment = min(plan.intro.end + 2 * plan.period, plan.length * 0.5)
        var comp = made.composition
        comp.scene = FromMoment(base: comp.scene, offset: moment)
        if let modulate = comp.modulate {
            comp.modulate = { t, look, backdrop in modulate(t + moment, &look, &backdrop) }
        }
        comp.transparent = true
        return comp
    }

    /// A movie's first frame, decoded as a player would, honouring its alpha.
    static func firstFrame(of url: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: .zero).image
    }

    /// Straight RGBA, 0…255, row by row. Drawn in the image's own colour space,
    /// so nothing is colour-managed on the way (the movie says ITU-R 709, the
    /// still sRGB, and the renderer writes the same values to both), and in
    /// floating point where it can be, so only the image's own rounding remains.
    static func straightPixels(_ image: CGImage) -> [Float]? {
        let own = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        for space in [own, CGColorSpace(name: CGColorSpace.sRGB)].compactMap({ $0 }) {
            if let px = premultiplied(image, space: space) { return unpremultiplied(px) }
        }
        return nil
    }

    /// The image drawn as premultiplied RGBA, 0…1.
    static func premultiplied(_ image: CGImage, space: CGColorSpace) -> [Float]? {
        let w = image.width, h = image.height
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        var out = [Float](repeating: 0, count: w * h * 4)
        let drawn = out.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue) else { return false }
            ctx.setBlendMode(.copy)
            ctx.draw(image, in: rect)
            return true
        }
        // Anything outside 0…1 means the floats were not laid out as expected.
        if drawn, out.allSatisfy({ $0.isFinite && $0 >= -0.001 && $0 <= 1.001 }) { return out }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setBlendMode(.copy)
            ctx.draw(image, in: rect)
            return true
        }
        return ok ? bytes.map { Float($0) / 255 } : nil
    }

    /// Premultiplied RGBA, 0…1, as straight RGBA, 0…255.
    static func unpremultiplied(_ px: [Float]) -> [Float] {
        var out = px
        for i in stride(from: 0, to: out.count, by: 4) {
            let a = min(1, max(0, out[i + 3]))
            for c in 0..<3 { out[i + c] = a > 1e-6 ? min(1, max(0, out[i + c] / a)) * 255 : 0 }
            out[i + 3] = a * 255
        }
        return out
    }

    struct Stats {
        var straightError: Double
        var shadowShare: Double
        var clearShare: Double
        var opaqueError: Double
    }

    /// Drift's measures, from the still's alpha: the mean colour difference on
    /// pixels between 5 % and 95 % alpha; the share of dark pixels between 5 %
    /// and 60 % alpha (soft shadow); and the share with no alpha at all.
    static func stats(still a: [Float], movie b: [Float]) -> Stats {
        let n = min(a.count, b.count) / 4
        var error = 0.0, semi = 0, shadow = 0, clear = 0, opaqueError = 0.0, opaque = 0
        for p in 0..<n {
            let i = p * 4
            let alpha = a[i + 3] / 255
            let diff = Double(abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2])) / 3
            if a[i + 3] < 0.5 { clear += 1 }
            if alpha >= 0.99 {
                opaque += 1
                opaqueError += diff
            }
            guard alpha > 0.05, alpha < 0.95 else { continue }
            semi += 1
            error += diff
            if alpha < 0.6, max(a[i], a[i + 1], a[i + 2]) < 40 { shadow += 1 }
        }
        return Stats(straightError: semi > 0 ? error / Double(semi) : 0, shadowShare: Double(shadow) / Double(max(n, 1)),
                     clearShare: Double(clear) / Double(max(n, 1)), opaqueError: opaque > 0 ? opaqueError / Double(opaque) : 0)
    }
}

/// A scene seen from `offset` seconds in, so a moment partway through is an export's first frame.
struct FromMoment: StageScene {
    let base: any StageScene
    let offset: Double

    var id: String { base.id }
    var name: String { base.name }
    var summary: String { base.summary }
    var dials: [(DialKey, String)] { base.dials }
    var defaults: SceneDials { base.defaults }
    var allowsMotionBlur: Bool { base.allowsMotionBlur }
    func loopDuration(_ ctx: SceneContext) -> Double { base.loopDuration(ctx) }
    func frame(at t: Double, _ ctx: SceneContext) -> StageFrame { base.frame(at: t + offset, ctx) }
    func soundEvents(_ ctx: SceneContext) -> [SoundEvent] { base.soundEvents(ctx) }
}
