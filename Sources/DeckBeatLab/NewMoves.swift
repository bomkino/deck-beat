import BeatKit
import CoreGraphics
import Foundation
import RenderCore
import StageKit
import StudioKit

/// The 3.0 moves in a 1080 × 1920 Reel, on decks of 2576 × 1080 and
/// 1920 × 1080 slides: each drop move through its hit, a zoom on a featured
/// slide, cells turning over as blinds and pages, and a title whose words
/// land on the beat. Two sheets of four columns, a row per moment.
enum NewMoves {
    struct Column {
        var name: String
        var slide: (w: Int, h: Int)
        var count: Int
        var look: String
        /// The grid fitted to the deck; off for a grid smaller than the deck, whose cells turn over.
        var fitted = true
        var tweak: (inout BeatSettings) -> Void = { _ in }
        var title: ReelTitle?
        /// Four moments to show, named, from the plan.
        var moments: (BeatPlan, [WordCue]) -> [(String, Double)]
    }

    static let ultrawide = WideDecks.ultrawide, hd = WideDecks.hd

    /// Four moments through a drop: the bar before, the hit, the shape held, and home.
    static func drop(_ p: BeatPlan, _: [WordCue]) -> [(String, Double)] {
        guard let m = p.moments.first(where: { $0.move != .light }) else {
            let d = p.drops.first ?? p.length * 0.5
            return [("Before", d - p.period), ("Hit", d + 0.05), ("After", d + p.period), ("Later", d + 4 * p.period)]
        }
        if m.move == .weave {
            return [("Tearing", m.time - p.period * 2.5), ("Threads", m.time - p.period * 0.5), ("Hit", m.time + 0.04),
                    ("Knitting", m.time + p.period * 0.9)]
        }
        return [("Flying", m.time + m.flyOut * 0.5), ("Shape", m.time + m.flyOut + p.period * 0.6),
                ("Shape, later", (m.time + m.flyOut + m.leave) / 2 + p.period * 0.5), ("Home", m.home + 0.05)]
    }

    static func zoom(_ p: BeatPlan, _: [WordCue]) -> [(String, Double)] {
        guard let f = p.features.first else { return [] }
        return [("Moving in", (f.liftOff + f.land) / 2), ("Zoomed", f.land + 0.2), ("Held", (f.land + f.leave) / 2),
                ("Going back", (f.leave + f.end) / 2)]
    }

    static func turn(_ p: BeatPlan, _: [WordCue]) -> [(String, Double)] {
        guard let t = p.swaps.flatMap({ $0 }).map(\.time).filter({ $0 > p.intro.end + 1 }).min() else { return [] }
        let f = p.flipTime
        return [("Turning", t - f * 0.3), ("Halfway", t - f * 0.08), ("Over", t + f * 0.12), ("Down", t + f * 0.32)]
    }

    static func words(_ p: BeatPlan, _ cues: [WordCue]) -> [(String, Double)] {
        guard cues.count >= 3, let last = cues.last else { return [] }
        return [("Line above", cues[0].land + 0.03), ("Falling", cues[1].land - cues[1].lead * 0.45), ("Landed", cues[2].land + 0.05),
                ("All in", last.land + 0.6)]
    }

    static let headline = ReelTitle(text: "Brightside raises its Series A", kicker: "pitch.dog · 2026", placement: .centre,
                                    timing: .opening, beat: true)

    static let sheets: [(name: String, columns: [Column])] = [
        ("moves-sheet-1", [
            Column(name: "Weave · 2576 · 15", slide: ultrawide, count: 15, look: "equaliser", moments: drop),
            Column(name: "Fan · 1920 · 20", slide: hd, count: 20, look: "screening-room", moments: drop),
            Column(name: "Tunnel · 2576 · 24", slide: ultrawide, count: 24, look: "ripple", moments: drop),
            Column(name: "Strip · 1920 · 15", slide: hd, count: 15, look: "read-through", moments: drop),
        ]),
        ("moves-sheet-2", [
            Column(name: "Zoom in · 2576 · 15", slide: ultrawide, count: 15, look: "screening-room", tweak: { $0.feature = .twoBars },
                   moments: zoom),
            Column(name: "Blinds · 1920 · 30", slide: hd, count: 30, look: "light-box", fitted: false, tweak: { s in
                s.grid.rotate = true
                s.turn = .blinds
            }, moments: turn),
            Column(name: "Page · 2576 · 30", slide: ultrawide, count: 30, look: "gallery-wall", fitted: false, tweak: { s in
                s.grid.rotate = true
                s.turn = .page
            }, moments: turn),
            Column(name: "Words on the beat · 1920", slide: hd, count: 15, look: "screening-room", title: headline, moments: words),
        ]),
    ]

    /// Renders both sheets into `dir` and returns them by name.
    static func render(song: Song, exporter: Exporter, to dir: URL) throws -> [(String, CGImage)] {
        let t0 = Date()
        var decks: [String: ([MediaTexture], [Palette?])] = [:]
        func deck(_ size: (w: Int, h: Int), _ count: Int) throws -> ([MediaTexture], [Palette?]) {
            let key = "\(size.w)x\(size.h)x\(count)"
            if let d = decks[key] { return d }
            let images = (0..<count).map { DemoDeck.slide(index: $0, width: size.w, height: size.h, number: $0 + 1) }
            let made = (try images.map { try MediaLoader.texture(from: $0) }, images.map { Palette.extract(from: [$0], name: "") })
            decks[key] = made
            return made
        }
        let tile = (w: 270, h: 480), label = 34
        var out: [(String, CGImage)] = []
        for sheetSpec in sheets {
            let columns = sheetSpec.columns
            let sheet = CGContext(data: nil, width: tile.w * columns.count, height: (tile.h + label) * 4, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sheet.setFillColor(CGColor(gray: 0.06, alpha: 1))
            sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
            for (column, spec) in columns.enumerated() {
                let (media, palettes) = try deck(spec.slide, spec.count)
                let slideAspect = Float(spec.slide.w) / Float(spec.slide.h)
                let aspect = Float(tile.w) / Float(tile.h)
                let made = Render.compose(Looks.look(spec.look), song: song, media: media, clip: Clip(length: .s30), aspect: aspect,
                                          grid: { spec.fitted ? $0.fitted(count: spec.count, aspect: aspect, slideAspect: slideAspect) : $0 },
                                          title: spec.title, palettes: palettes, tweak: spec.tweak)
                let cues = spec.title.map { WordTiming.cues($0, plan: made.plan) } ?? []
                let moments = spec.moments(made.plan, cues)
                for (row, (name, t)) in moments.prefix(4).enumerated() {
                    let img = try exporter.still(made.composition, at: t, width: tile.w, height: tile.h, samples: 4)
                    let top = row * (tile.h + label)
                    sheet.draw(img, in: CGRect(x: column * tile.w, y: sheet.height - top - label - tile.h, width: tile.w, height: tile.h))
                    let caption = row == 0 ? spec.name + " · " + name : String(format: "%@ · %.2f s", name as NSString, t)
                    Render.text(caption, in: sheet, at: CGPoint(x: column * tile.w + 10, y: sheet.height - top - label + 11), bold: row == 0)
                }
                let planned = made.plan.moments.map { "\($0.move.rawValue) at \(String(format: "%.2f", $0.time))" }.joined(separator: ", ")
                print(String(format: "%-26@ moments: %@; %d features, %d cues", spec.name as NSString, planned as NSString,
                             made.plan.features.count, cues.count))
                if moments.isEmpty { print("     no moment to show for \(spec.name)") }
            }
            let image = sheet.makeImage()!
            try ImageOutput.writePNG(image, to: dir.appendingPathComponent(sheetSpec.name + ".png"))
            out.append((sheetSpec.name, image))
        }
        print(String(format: "wrote the 3.0 moves sheets in %.1f s", Date().timeIntervalSince(t0)))
        return out
    }
}
