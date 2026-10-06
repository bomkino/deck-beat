import BeatKit
import CoreGraphics
import Foundation
import RenderCore
import StageKit
import StudioKit

/// Decks made for wide screens in a 1080 × 1920 Reel: 2576 × 1080 and
/// 1920 × 1080 slides, on the default grid and on the grid fitted to the deck,
/// with a caption, and opening wide in Read-through. Two sheets of four
/// columns, a row per moment.
enum WideDecks {
    struct Column {
        var name: String
        var slide: (w: Int, h: Int)
        var count: Int
        var look = Looks.defaultID
        var fitted = true
        var shape: CellShape?
        var title: ReelTitle?
    }

    static let ultrawide = (w: 2576, h: 1080), hd = (w: 1920, h: 1080)

    static let sheets: [(name: String, columns: [Column])] = [
        ("wide-sheet-1", [
            Column(name: "2576 · 15 · as set", slide: ultrawide, count: 15, fitted: false),
            Column(name: "2576 · 15 · fitted", slide: ultrawide, count: 15),
            Column(name: "2576 · 30 · fitted", slide: ultrawide, count: 30),
            Column(name: "2576 · 24 · caption", slide: ultrawide, count: 24,
                   title: ReelTitle(text: "Brightside raises its Series A", kicker: "pitch.dog · 2026", placement: .corner, timing: .throughout)),
        ]),
        ("wide-sheet-2", [
            Column(name: "1920 · 15 · as set", slide: hd, count: 15, fitted: false),
            Column(name: "1920 · 20 · fitted", slide: hd, count: 20),
            Column(name: "1920 · 30 · fitted", slide: hd, count: 30),
            Column(name: "2576 · Read-through", slide: ultrawide, count: 15, look: "read-through", fitted: false, shape: .fill),
        ]),
    ]

    /// Renders both sheets into `dir` and returns them by name.
    static func render(song: Song, exporter: Exporter, to dir: URL) throws -> [(String, CGImage)] {
        let t0 = Date()
        var decks: [String: [MediaTexture]] = [:]
        func deck(_ size: (w: Int, h: Int), _ count: Int) throws -> [MediaTexture] {
            let key = "\(size.w)x\(size.h)x\(count)"
            if let d = decks[key] { return d }
            let made = try (0..<count).map { try MediaLoader.texture(from: DemoDeck.slide(index: $0, width: size.w, height: size.h, number: $0 + 1)) }
            decks[key] = made
            return made
        }
        let tile = (w: 270, h: 480), label = 34
        let names = ["Cold open", "Intro", "Out front", "Drop"]
        var out: [(String, CGImage)] = []
        for sheetSpec in sheets {
            let columns = sheetSpec.columns
            let sheet = CGContext(data: nil, width: tile.w * columns.count, height: (tile.h + label) * names.count, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sheet.setFillColor(CGColor(gray: 0.06, alpha: 1))
            sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
            for (column, spec) in columns.enumerated() {
                let media = try deck(spec.slide, spec.count)
                let slideAspect = Float(spec.slide.w) / Float(spec.slide.h)
                let aspect = Float(tile.w) / Float(tile.h)
                let made = Render.compose(Looks.look(spec.look), song: song, media: media, clip: Clip(length: .s30), aspect: aspect, grid: { base in
                    var g = spec.fitted ? base.fitted(count: spec.count, aspect: aspect, slideAspect: slideAspect) : base
                    if let shape = spec.shape { g.shape = shape }
                    return g
                }, title: spec.title)
                let plan = made.plan, layout = made.layout
                let forward = plan.features.first.map { $0.land + 0.3 } ?? plan.length * 0.4
                let drop = plan.drops.first.map { $0 + 0.12 } ?? plan.length * 0.6
                let moments = [0, plan.intro.end * 0.55, forward, drop]
                for (row, t) in moments.enumerated() {
                    let img = try exporter.still(made.composition, at: t, width: tile.w, height: tile.h, samples: 4)
                    let top = row * (tile.h + label)
                    sheet.draw(img, in: CGRect(x: column * tile.w, y: sheet.height - top - label - tile.h, width: tile.w, height: tile.h))
                    let caption = row == 0
                        ? spec.name
                        : String(format: "%@ · %.1f s", names[row] as NSString, t)
                    Render.text(caption, in: sheet, at: CGPoint(x: column * tile.w + 10, y: sheet.height - top - label + 11), bold: row == 0)
                }
                let cell = layout.cells[0].size / layout.px
                print(String(format: "%-22@ %d×%d %@ cells %.0f×%.0f px, %.0f%% cropped", spec.name as NSString, layout.columns, layout.rows,
                             layout.shape.rawValue as NSString, cell.x, cell.y, layout.crop * 100))
            }
            let image = sheet.makeImage()!
            try ImageOutput.writePNG(image, to: dir.appendingPathComponent(sheetSpec.name + ".png"))
            out.append((sheetSpec.name, image))
        }
        print(String(format: "wrote the wide-deck sheets in %.1f s", Date().timeIntervalSince(t0)))
        return out
    }
}

/// How long a Reel export takes on the old path (every card on the fine mesh,
/// one frame at a time) and on the new one (flat cards as two triangles, the
/// next frame encoded while the GPU draws the last).
enum ExportBench {
    static func run(song: Song, media: [MediaTexture], exporter: Exporter) async throws {
        let look = Looks.look(Looks.defaultID)
        let width = 1080, height = 1920, seconds = 5.0
        for (name, columns, rows) in [("3×5", 3, 5), ("12×20", 12, 20)] {
            let made = Render.compose(look, song: song, media: media, clip: Clip(length: .s15), aspect: Float(width) / Float(height), grid: { base in
                var g = base
                g.columns = columns
                g.rows = rows
                return g
            })
            let settings = ExportSettings(width: width, height: height, fps: 30, duration: seconds, format: .video(.h264), samples: 8)
            var times: [Double] = []
            for (quads, overlap) in [(false, false), (true, false), (true, true)] {
                exporter.renderer.flatQuads = quads
                exporter.overlapFrames = overlap
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("beat-lab-bench-\(name).mp4")
                try? FileManager.default.removeItem(at: url)
                let t = Date()
                try await exporter.export(made.composition, settings: settings, to: url)
                times.append(Date().timeIntervalSince(t))
                try? FileManager.default.removeItem(at: url)
            }
            exporter.renderer.flatQuads = true
            exporter.overlapFrames = true
            print(String(format: "export %@ grid, %d×%d, 8 samples, %d frames: v1 path %.2f s, flat quads %.2f s, overlapped %.2f s (%.2f× as fast)",
                         name as NSString, width, height, settings.frameCount, times[0], times[1], times[2], times[0] / max(times[2], 1e-6)))
        }
    }
}

/// Listening and planning, timed on the CPU: what the app does when a song
/// arrives and every time a setting changes.
enum Bench {
    static func run() {
        func ms(_ f: () -> Void) -> Double {
            let t = Date()
            f()
            return Date().timeIntervalSince(t) * 1000
        }
        let stereo = DemoGroove.render()
        var mono = [Float](repeating: 0, count: stereo.count / 2)
        for i in mono.indices { mono[i] = 0.5 * (stereo[2 * i] + stereo[2 * i + 1]) }
        // A three-minute song: the groove six times over.
        var long: [Float] = []
        for _ in 0..<6 { long += mono }
        var a: SongAnalysis!
        let listen = ms { a = SongAnalyzer.analyze(mono: long, sampleRate: Double(DemoGroove.sampleRate)) }
        print(String(format: "listen to a %.0f s song: %.0f ms (%.1f BPM, %d drops)", a.duration, listen, a.tempo, a.drops.count))
        var best = 0.0
        let section = ms { for _ in 0..<20 { best = a.bestSection(length: 30, lead: 2) } } / 20
        print(String(format: "find the best 30 s: %.2f ms (from %.1f s)", section, best))
        let tall: Float = 1080.0 / 1920.0
        for (columns, rows) in [(3, 5), (5, 12), (12, 20)] {
            var line = "plan \(columns)×\(rows):"
            for mode in BeatMode.allCases {
                var s = BeatSettings()
                s.mode = mode
                s.grid.columns = columns
                s.grid.rows = rows
                let layout = GridLayout(settings: s.grid, aspect: tall, slideAspect: 16.0 / 9.0)
                var plan: BeatPlan!
                let t = ms { plan = Choreographer.plan(a, settings: s, layout: layout, slides: columns * rows, clipStart: 20, clipLength: 30) }
                let scene = BeatScene(plan: plan, layout: layout, settings: s)
                let ctx = SceneContext(items: (0..<(columns * rows)).map { SceneItem(media: $0, occurrence: $0, aspect: 16.0 / 9.0) },
                                       aspect: tall, dials: SceneDials())
                let frames = ms { var t = 0.0; while t < 30 { _ = scene.frame(at: t, ctx); t += 1.0 / 30 } } / 900
                line += String(format: "  %@ %.1f ms (frame %.3f ms)", mode.title as NSString, t, frames)
            }
            print(line)
        }
        // Mosaic on 60 and 100 slides of mixed shapes, laid out as a collage and built on every hit.
        let shapes: [Float] = [16.0 / 9.0, 4.0 / 3.0, 1, 9.0 / 16.0, 2576.0 / 1080.0, 3.0 / 4.0, 1.5, 4.0 / 5.0, 21.0 / 9.0, 2.0 / 3.0]
        for n in [60, 100] {
            let aspects = (0..<n).map { shapes[$0 % shapes.count] }
            var s = BeatSettings()
            LookMoves.mosaic(&s)
            s.grid = GridSettings().fitted(count: n, aspect: tall, slideAspect: 16.0 / 9.0, aspects: aspects)
            var layout: GridLayout!
            let lay = ms { layout = GridLayout(settings: s.grid, aspect: tall, slideAspect: 16.0 / 9.0, aspects: aspects) }
            var plan: BeatPlan!
            let t = ms { plan = Choreographer.plan(a, settings: s, layout: layout, slides: n, clipStart: 20, clipLength: 30) }
            let scene = BeatScene(plan: plan, layout: layout, settings: s)
            let ctx = SceneContext(items: aspects.enumerated().map { SceneItem(media: $0.offset, occurrence: $0.offset, aspect: $0.element) },
                                   aspect: tall, dials: SceneDials())
            let frames = ms { var t = 0.0; while t < 30 { _ = scene.frame(at: t, ctx); t += 1.0 / 30 } } / 900
            print(String(format: "Mosaic, %d mixed slides as a %@ of %d: layout %.1f ms, plan %.1f ms (frame %.3f ms)",
                         n, s.grid.arrangement.title as NSString, layout.count, lay, t, frames))
        }
    }
}
