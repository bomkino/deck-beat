import BeatKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Metal
import RenderCore
import StageKit
import StudioKit
import UniformTypeIdentifiers

// beat-lab: headless checks and renders, for CI and visual review.
//
//   beat-lab check                 song analysis, layout, plans and scenes, on the CPU; and
//                                  transparent exports on the GPU, where there is one
//   beat-lab bench                 how long listening and planning take, on the CPU
//   beat-lab render --out <dir>    contact sheets of every Look, of wide decks and of the 3.0
//                                  moves, a demo clip with sound, and export timings old and new

let usage = "usage: beat-lab check | beat-lab bench | beat-lab render --out <dir>"
let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "check":
    var failed = Checks.run()
    failed += await TransparentExport.run()
    print(failed == 0 ? "All checks passed." : "\(failed) checks failed.")
    exit(failed == 0 ? 0 : 1)

case "bench":
    Bench.run()

case "render":
    guard let i = args.firstIndex(of: "--out"), i + 1 < args.count else {
        print(usage)
        exit(2)
    }
    guard MTLCreateSystemDefaultDevice() != nil else {
        print("skipped: no Metal device")
        exit(0)
    }
    do {
        try await Render.run(to: URL(fileURLWithPath: args[i + 1]))
    } catch {
        print("render failed: \(error)")
        exit(1)
    }

default:
    print(usage)
    exit(2)
}

/// Every Look at four moments, and one finished clip, from the demo deck and groove.
enum Render {
    static func run(to dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let t0 = Date()
        let song = Song.demo()
        print(String(format: "song: %.2f BPM, drops at %@, %.1f s", song.analysis.tempo,
                     song.analysis.drops.map { String(format: "%.2f", $0) }.joined(separator: ", ") as NSString, song.duration))
        let slides = (0..<DemoDeck.count).map { DemoDeck.slide(index: $0) }
        let media = try slides.map { try MediaLoader.texture(from: $0) }
        let palettes = slides.map { Palette.extract(from: [$0], name: "") }
        let exporter = try Exporter()

        // The contact sheet: a column per Look, a row per moment.
        let tile = (w: 270, h: 480), label = 34
        let looks = Looks.all
        let names = ["Cold open", "Intro", "Groove", "Drop"]
        let sheet = CGContext(data: nil, width: tile.w * looks.count, height: (tile.h + label) * names.count, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        sheet.setFillColor(CGColor(gray: 0.06, alpha: 1))
        sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
        for (column, look) in looks.enumerated() {
            let made = compose(look, song: song, media: media, clip: Clip(length: .s30), aspect: Float(tile.w) / Float(tile.h), palettes: palettes)
            let plan = made.plan
            let groove = plan.features.first.map { $0.land + 0.3 } ?? min(plan.intro.end + 4 * plan.period * 2, plan.length * 0.4)
            let drop = plan.drops.first.map { $0 + 0.12 } ?? plan.length * 0.6
            let moments = [0, plan.intro.end * 0.55, groove, drop]
            for (row, t) in moments.enumerated() {
                let img = try exporter.still(made.composition, at: t, width: tile.w, height: tile.h, samples: 4)
                let top = row * (tile.h + label)
                sheet.draw(img, in: CGRect(x: column * tile.w, y: sheet.height - top - label - tile.h, width: tile.w, height: tile.h))
                text(row == 0 ? look.name : String(format: "%@ · %.1f s", names[row] as NSString, t), in: sheet,
                     at: CGPoint(x: column * tile.w + 10, y: sheet.height - top - label + 11), bold: row == 0)
            }
            print(String(format: "%-15@ intro %.2f s, %@ from %.2f s of %.2f s", look.id as NSString, plan.intro.end,
                         plan.outro.kind.title as NSString, plan.outro.start, plan.length))
        }
        let sheetImage = sheet.makeImage()!
        let sheetURL = dir.appendingPathComponent("contact-sheet.png")
        try ImageOutput.writePNG(sheetImage, to: sheetURL)
        print(String(format: "wrote %@ in %.1f s", sheetURL.lastPathComponent as NSString, Date().timeIntervalSince(t0)))
        let wideSheets = try WideDecks.render(song: song, exporter: exporter, to: dir) + NewMoves.render(song: song, exporter: exporter, to: dir)

        // A 15-second clip of the default Look in the Reel frame, with its sound.
        let t1 = Date()
        let look = Looks.look(Looks.defaultID)
        let width = 540, height = 960
        let made = compose(look, song: song, media: media, clip: Clip(length: .s15), aspect: Float(width) / Float(height))
        let audio = song.slice(from: made.clip.start, length: made.clip.length, fadeIn: 0.03, fadeOut: 0.03)
        let settings = ExportSettings(width: width, height: height, fps: 30, duration: made.clip.length, format: .video(.h264), samples: 2,
                                      audio: audio)
        let clipURL = dir.appendingPathComponent("demo-clip.mp4")
        try? FileManager.default.removeItem(at: clipURL)
        try await exporter.export(made.composition, settings: settings, to: clipURL, progress: { p in
            if p.frame % 90 == 0 || p.frame == p.total { print("frame \(p.frame)/\(p.total)") }
        })
        print(String(format: "wrote %@ (%.1f s from %.2f s, %@) in %.1f s", clipURL.lastPathComponent as NSString, made.clip.length,
                     made.clip.start, made.clip.outro.title as NSString, Date().timeIntervalSince(t1)))

        try await ExportBench.run(song: song, media: media, exporter: exporter)

        // Small copies of the sheets in the log, for reviewers who can't download the artifact.
        printThumbnail(sheetImage, name: "contact-sheet", width: 945, prefix: "b64")
        for (name, image) in wideSheets { printThumbnail(image, name: name, width: image.width, prefix: "b64-\(name)") }
    }

    static func printThumbnail(_ image: CGImage, name: String, width: Int, prefix: String) {
        guard let thumb = scaled(image, width: width), let data = jpeg(thumb, quality: 0.72) else { return }
        let b64 = data.base64EncodedString()
        print("thumbnail: \(name).jpg, \(data.count) bytes, base64 in \((b64.count + 999) / 1000) lines")
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 1000, limitedBy: b64.endIndex) ?? b64.endIndex
            print(prefix + " " + b64[i..<j])
            i = j
        }
    }

    struct Made {
        var clip: ClipRange
        var plan: BeatPlan
        var layout: GridLayout
        var composition: Composition
    }

    /// The composition the app would make for `look` with the demo deck and groove.
    static func compose(_ look: Look, song: Song, media: [MediaTexture], clip: Clip, aspect: Float,
                        grid: ((GridSettings) -> GridSettings)? = nil, title: ReelTitle? = nil, canvas: (w: Int, h: Int) = (1080, 1920),
                        palettes: [Palette?] = [], tweak: ((inout BeatSettings) -> Void)? = nil) -> Made {
        var settings = Looks.settings(look, over: BeatSettings())
        if let grid { settings.grid = grid(settings.grid) }
        tweak?(&settings)
        let aspects = media.map(\.aspect)
        let range = clip.resolve(song.analysis, settings: settings)
        var clear = Clearance.none
        if let title, title.timing == .throughout {
            let reach = TitleArt.reach(title, width: canvas.w, height: canvas.h)
            clear = Clearance(top: Float(reach.top), bottom: Float(reach.bottom))
        }
        let (layout, plan) = Composer.plan(song.analysis, settings: settings, clip: range, aspect: aspect,
                                           slideAspect: Composer.typicalAspect(aspects), slides: media.count, clear: clear)
        var comp = Composer.composition(plan: plan, layout: layout, settings: settings, stage: look.stage, backdrop: look.backdrop(nil),
                                        textures: media.map(\.texture), aspects: aspects, canvasAspect: aspect)
        if let title { comp.overlay = TitleArt.overlay(title, light: true, cues: WordTiming.cues(title, plan: plan)) }
        comp.itemPalettes = palettes
        return Made(clip: range, plan: plan, layout: layout, composition: comp)
    }

    static func text(_ s: String, in ctx: CGContext, at p: CGPoint, bold: Bool) {
        let font = CTFontCreateWithName((bold ? "AvenirNext-DemiBold" : "AvenirNext-Regular") as CFString, bold ? 15 : 13, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: bold ? 0.92 : 0.6),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        ctx.textPosition = p
        CTLineDraw(line, ctx)
    }

    static func scaled(_ image: CGImage, width: Int) -> CGImage? {
        let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
