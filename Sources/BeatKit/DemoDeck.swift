import CoreGraphics
import CoreText
import Foundation

/// Fifteen slides of an invented pitch deck, drawn in code, so a new window
/// plays straight away. Brightside is made up: rooftop solar, shared by a street.
public enum DemoDeck {
    public static let count = 15
    public static let width = 1600
    public static let height = 900

    public static let titles = [
        "Cover", "The problem", "2.1 million roofs", "How it works", "Installs", "What councils say", "Every roof",
        "The app", "Traction", "Pricing", "Market", "Team", "Roadmap", "The ask", "Thank you",
    ]

    // Ink and paper.
    static let night = rgb(0x0F1A2E), navy = rgb(0x16233F), paper = rgb(0xF6F1E7), ink = rgb(0x14161A)
    static let amber = rgb(0xFFB140), coral = rgb(0xFF6B4A), teal = rgb(0x1FB5A8), violet = rgb(0x7A5CFF), lime = rgb(0xB8E04A)
    static let mist = rgb(0x8B95A7)

    /// Slide `index` (0…14) as an image.
    public static func slide(index: Int) -> CGImage {
        let w = width, h = height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let d = Draw(ctx: ctx, w: CGFloat(w), h: CGFloat(h))
        switch index % count {
        case 0: cover(d)
        case 1: problem(d)
        case 2: bigNumber(d)
        case 3: howItWorks(d)
        case 4: barChart(d)
        case 5: quote(d)
        case 6: skyline(d)
        case 7: app(d)
        case 8: traction(d)
        case 9: pricing(d)
        case 10: market(d)
        case 11: team(d)
        case 12: roadmap(d)
        case 13: ask(d)
        default: thanks(d)
        }
        return ctx.makeImage()!
    }

    // MARK: Slides

    static func cover(_ d: Draw) {
        d.fill(night)
        d.gradientCircle(centre: CGPoint(x: 1240, y: 300), radius: 520, colour: amber, alpha: 0.55)
        d.circle(centre: CGPoint(x: 1240, y: 300), radius: 150, colour: amber)
        d.text("BRIGHTSIDE", x: 120, y: 330, size: 132, weight: .heavy, colour: paper, tracking: 6)
        d.text("Rooftop solar, shared by the street.", x: 124, y: 470, size: 46, weight: .regular, colour: paper.alpha(0.82))
        d.rect(CGRect(x: 124, y: 560, width: 120, height: 8), colour: amber)
        d.text("SERIES A · 2026", x: 124, y: 610, size: 28, weight: .demi, colour: mist, tracking: 4)
    }

    static func problem(_ d: Draw) {
        d.fill(paper)
        d.label("THE PROBLEM", x: 120, y: 120, colour: coral)
        d.text("Cities leave 40% of", x: 120, y: 200, size: 92, weight: .bold, colour: ink)
        d.text("their roofs doing nothing.", x: 120, y: 310, size: 92, weight: .bold, colour: ink)
        for i in 0..<10 {
            let x = 120 + CGFloat(i) * 136
            d.roundRect(CGRect(x: x, y: 520, width: 112, height: 220), radius: 14, colour: i < 4 ? coral : ink.alpha(0.1))
        }
        d.text("4 in 10 roofs could make power. Almost none do.", x: 120, y: 780, size: 30, weight: .regular, colour: ink.alpha(0.6))
    }

    static func bigNumber(_ d: Draw) {
        d.fill(teal)
        d.text("2.1M", x: 110, y: 120, size: 360, weight: .heavy, colour: paper)
        d.text("roofs in London alone", x: 124, y: 560, size: 64, weight: .demi, colour: night)
        d.text("could each power a home and a half.", x: 124, y: 650, size: 44, weight: .regular, colour: night.alpha(0.75))
    }

    static func howItWorks(_ d: Draw) {
        d.fill(navy)
        d.label("HOW IT WORKS", x: 120, y: 110, colour: amber)
        let steps = [("1", "Map", "We find the roofs\nthat face the sun.", amber),
                     ("2", "Install", "Panels go up in a\nday, at no cost.", teal),
                     ("3", "Share", "The street splits the\npower and the bill.", coral)]
        for (i, s) in steps.enumerated() {
            let x = 120 + CGFloat(i) * 470
            d.circle(centre: CGPoint(x: x + 70, y: 330), radius: 70, colour: s.3)
            d.text(s.0, x: x + 46, y: 280, size: 80, weight: .heavy, colour: night)
            d.text(s.1, x: x, y: 450, size: 64, weight: .bold, colour: paper)
            for (k, line) in s.2.split(separator: "\n").enumerated() {
                d.text(String(line), x: x, y: 550 + CGFloat(k) * 50, size: 36, weight: .regular, colour: paper.alpha(0.72))
            }
        }
    }

    static func barChart(_ d: Draw) {
        d.fill(paper)
        d.label("INSTALLS PER MONTH", x: 120, y: 110, colour: violet)
        d.text("Up 12× in a year", x: 120, y: 170, size: 72, weight: .bold, colour: ink)
        let values: [CGFloat] = [4, 6, 7, 11, 13, 18, 22, 27, 31, 38, 44, 48]
        for (i, v) in values.enumerated() {
            let x = 130 + CGFloat(i) * 112
            let bh = v / 48 * 470
            d.roundRect(CGRect(x: x, y: 800 - bh, width: 80, height: bh), radius: 10, colour: i == values.count - 1 ? violet : violet.alpha(0.35))
        }
        d.rect(CGRect(x: 120, y: 802, width: 1360, height: 3), colour: ink.alpha(0.2))
    }

    static func quote(_ d: Draw) {
        d.fill(coral)
        d.text("“", x: 100, y: 40, size: 300, weight: .heavy, colour: paper.alpha(0.5))
        d.text("The easiest yes we", x: 140, y: 260, size: 100, weight: .bold, colour: paper)
        d.text("gave all year.”", x: 140, y: 380, size: 100, weight: .bold, colour: paper)
        d.text("Head of estates, a London borough", x: 144, y: 600, size: 38, weight: .demi, colour: night)
    }

    static func skyline(_ d: Draw) {
        d.verticalGradient(top: rgb(0x2B3A67), bottom: rgb(0xFF9E6B))
        d.gradientCircle(centre: CGPoint(x: 1120, y: 560), radius: 360, colour: rgb(0xFFE3A8), alpha: 0.75)
        d.circle(centre: CGPoint(x: 1120, y: 560), radius: 110, colour: rgb(0xFFE9B8))
        var x: CGFloat = 0
        var k = 0
        while x < 1600 {
            let bw = CGFloat(90 + (k * 53) % 120)
            let bh = CGFloat(160 + (k * 97) % 260)
            d.rect(CGRect(x: x, y: 900 - bh, width: bw - 6, height: bh), colour: rgb(0x121A2C))
            // Panels on the roofs.
            d.rect(CGRect(x: x + 12, y: 900 - bh - 10, width: bw - 30, height: 10), colour: k % 2 == 0 ? amber : teal)
            x += bw
            k += 1
        }
        d.text("Every roof,", x: 120, y: 110, size: 96, weight: .heavy, colour: paper)
        d.text("a power station.", x: 120, y: 220, size: 96, weight: .heavy, colour: paper)
    }

    static func app(_ d: Draw) {
        d.fill(night)
        d.label("THE APP", x: 120, y: 120, colour: teal)
        d.text("Your street's", x: 120, y: 200, size: 84, weight: .bold, colour: paper)
        d.text("power, live.", x: 120, y: 300, size: 84, weight: .bold, colour: paper)
        d.text("See what your roof made today,", x: 120, y: 460, size: 36, weight: .regular, colour: paper.alpha(0.7))
        d.text("and what the street saved.", x: 120, y: 510, size: 36, weight: .regular, colour: paper.alpha(0.7))
        let phone = CGRect(x: 1020, y: 90, width: 380, height: 760)
        d.roundRect(phone, radius: 56, colour: rgb(0x26324D))
        d.roundRect(phone.insetBy(dx: 18, dy: 18), radius: 42, colour: paper)
        d.text("Today", x: 1070, y: 150, size: 34, weight: .bold, colour: ink)
        d.text("14.2 kWh", x: 1070, y: 200, size: 60, weight: .heavy, colour: teal)
        for i in 0..<7 {
            let bh = CGFloat([60, 110, 170, 220, 190, 120, 70][i])
            d.roundRect(CGRect(x: 1070 + CGFloat(i) * 40, y: 520 - bh, width: 26, height: bh), radius: 6, colour: amber)
        }
        d.roundRect(CGRect(x: 1062, y: 580, width: 296, height: 90), radius: 18, colour: teal.alpha(0.15))
        d.text("Saved £312 this year", x: 1084, y: 606, size: 26, weight: .demi, colour: ink)
    }

    static func traction(_ d: Draw) {
        d.fill(paper)
        d.label("TRACTION", x: 120, y: 110, colour: teal)
        d.text("1,840 homes", x: 120, y: 170, size: 96, weight: .heavy, colour: ink)
        d.text("on shared roofs across 6 boroughs", x: 124, y: 290, size: 38, weight: .regular, colour: ink.alpha(0.6))
        let pts: [CGFloat] = [0.05, 0.08, 0.1, 0.16, 0.2, 0.28, 0.35, 0.47, 0.58, 0.7, 0.84, 1]
        let path = CGMutablePath()
        for (i, p) in pts.enumerated() {
            let pt = CGPoint(x: 140 + CGFloat(i) * 120, y: 800 - p * 380)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        d.stroke(path, colour: teal, width: 12)
        d.circle(centre: CGPoint(x: 140 + 11 * 120, y: 420), radius: 22, colour: teal)
    }

    static func pricing(_ d: Draw) {
        d.fill(violet)
        d.label("PRICING", x: 120, y: 120, colour: paper.alpha(0.8))
        d.text("£18", x: 110, y: 190, size: 300, weight: .heavy, colour: paper)
        d.text("a month per home.", x: 124, y: 540, size: 60, weight: .demi, colour: paper)
        d.text("No install fee. Bills fall by a third.", x: 124, y: 630, size: 40, weight: .regular, colour: paper.alpha(0.75))
        d.roundRect(CGRect(x: 1080, y: 260, width: 380, height: 380), radius: 40, colour: paper.alpha(0.14))
        d.text("−34%", x: 1130, y: 380, size: 110, weight: .heavy, colour: lime)
        d.text("average bill", x: 1136, y: 520, size: 34, weight: .regular, colour: paper)
    }

    static func market(_ d: Draw) {
        d.fill(night)
        d.label("MARKET", x: 120, y: 110, colour: lime)
        let c = CGPoint(x: 1080, y: 470)
        d.circle(centre: c, radius: 360, colour: lime.alpha(0.18))
        d.circle(centre: c, radius: 230, colour: lime.alpha(0.4))
        d.circle(centre: c, radius: 110, colour: lime)
        d.text("£9.4B", x: 120, y: 200, size: 110, weight: .heavy, colour: paper)
        d.text("UK rooftop power", x: 124, y: 340, size: 38, weight: .regular, colour: paper.alpha(0.7))
        d.text("£1.2B", x: 120, y: 450, size: 80, weight: .bold, colour: lime)
        d.text("shared-roof streets we can reach by 2030", x: 124, y: 560, size: 32, weight: .regular, colour: paper.alpha(0.7))
    }

    static func team(_ d: Draw) {
        d.fill(paper)
        d.label("TEAM", x: 120, y: 110, colour: coral)
        d.text("Built by people who've done it.", x: 120, y: 170, size: 64, weight: .bold, colour: ink)
        let people = [("AO", "Ada Okafor", "CEO · ex-grid operator", coral), ("MR", "Max Reyes", "CTO · solar firmware", teal),
                      ("JL", "June Lund", "Ops · 900 installs", amber), ("SK", "Sam Kaur", "Policy · councils", violet)]
        for (i, p) in people.enumerated() {
            let x = 120 + CGFloat(i) * 350
            d.circle(centre: CGPoint(x: x + 110, y: 440), radius: 110, colour: p.3)
            d.text(p.0, x: x + 50, y: 395, size: 80, weight: .heavy, colour: paper)
            d.text(p.1, x: x, y: 590, size: 40, weight: .bold, colour: ink)
            d.text(p.2, x: x, y: 645, size: 28, weight: .regular, colour: ink.alpha(0.6))
        }
    }

    static func roadmap(_ d: Draw) {
        d.fill(navy)
        d.label("ROADMAP", x: 120, y: 110, colour: amber)
        d.text("Ten cities by 2028.", x: 120, y: 170, size: 80, weight: .bold, colour: paper)
        d.rect(CGRect(x: 120, y: 520, width: 1360, height: 6), colour: paper.alpha(0.25))
        let stops = [("2026", "London, 6 boroughs"), ("2027 H1", "Manchester, Leeds"), ("2027 H2", "Bristol, Glasgow"), ("2028", "Ten cities")]
        for (i, s) in stops.enumerated() {
            let x = 140 + CGFloat(i) * 440
            d.circle(centre: CGPoint(x: x, y: 523), radius: i == 0 ? 26 : 18, colour: i == 0 ? amber : paper)
            d.text(s.0, x: x - 20, y: 580, size: 44, weight: .heavy, colour: i == 0 ? amber : paper)
            d.text(s.1, x: x - 20, y: 645, size: 30, weight: .regular, colour: paper.alpha(0.7))
        }
    }

    static func ask(_ d: Draw) {
        d.fill(amber)
        d.label("THE ASK", x: 120, y: 120, colour: night)
        d.text("£6M", x: 110, y: 180, size: 320, weight: .heavy, colour: night)
        d.text("to light up ten cities.", x: 124, y: 560, size: 72, weight: .bold, colour: night)
        d.text("60% installs · 25% software · 15% team", x: 124, y: 670, size: 36, weight: .regular, colour: night.alpha(0.7))
    }

    static func thanks(_ d: Draw) {
        d.fill(night)
        d.gradientCircle(centre: CGPoint(x: 800, y: 1000), radius: 760, colour: amber, alpha: 0.5)
        d.text("Thank you.", x: 120, y: 270, size: 150, weight: .heavy, colour: paper)
        d.text("hello@brightside.example", x: 124, y: 480, size: 48, weight: .demi, colour: amber)
        d.text("BRIGHTSIDE", x: 124, y: 760, size: 32, weight: .heavy, colour: paper.alpha(0.6), tracking: 6)
    }

    // MARK: Drawing

    struct Colour {
        var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1
        func alpha(_ x: CGFloat) -> Colour { Colour(r: r, g: g, b: b, a: x) }
        var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    }

    static func rgb(_ hex: UInt32) -> Colour {
        Colour(r: CGFloat((hex >> 16) & 255) / 255, g: CGFloat((hex >> 8) & 255) / 255, b: CGFloat(hex & 255) / 255)
    }

    enum Weight { case regular, demi, bold, heavy }

    /// Draws in a top-left coordinate space, like a slide is laid out.
    struct Draw {
        let ctx: CGContext
        let w: CGFloat
        let h: CGFloat

        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height) }
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: h - p.y) }

        func fill(_ c: Colour) { rect(CGRect(x: 0, y: 0, width: w, height: h), colour: c) }

        func rect(_ r: CGRect, colour: Colour) {
            ctx.setFillColor(colour.cg)
            ctx.fill(flip(r))
        }

        func roundRect(_ r: CGRect, radius: CGFloat, colour: Colour) {
            ctx.setFillColor(colour.cg)
            ctx.addPath(CGPath(roundedRect: flip(r), cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }

        func circle(centre: CGPoint, radius: CGFloat, colour: Colour) {
            let c = flip(centre)
            ctx.setFillColor(colour.cg)
            ctx.fillEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }

        func gradientCircle(centre: CGPoint, radius: CGFloat, colour: Colour, alpha: CGFloat) {
            let c = flip(centre)
            let colours = [colour.alpha(alpha).cg, colour.alpha(0).cg] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours, locations: [0, 1]) else { return }
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
        }

        func verticalGradient(top: Colour, bottom: Colour) {
            let colours = [bottom.cg, top.cg] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
        }

        func stroke(_ path: CGPath, colour: Colour, width: CGFloat) {
            var t = CGAffineTransform(translationX: 0, y: h).scaledBy(x: 1, y: -1)
            guard let flipped = path.copy(using: &t) else { return }
            ctx.setStrokeColor(colour.cg)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(flipped)
            ctx.strokePath()
        }

        func label(_ s: String, x: CGFloat, y: CGFloat, colour: Colour) {
            text(s, x: x, y: y, size: 28, weight: .heavy, colour: colour, tracking: 5)
        }

        /// Text whose top sits at `y`.
        func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: Weight, colour: Colour, tracking: CGFloat = 0) {
            let name: String
            switch weight {
            case .regular: name = "AvenirNext-Regular"
            case .demi: name = "AvenirNext-DemiBold"
            case .bold: name = "AvenirNext-Bold"
            case .heavy: name = "AvenirNext-Heavy"
            }
            let font = CTFontCreateWithName(name as CFString, size, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour.cg,
                NSAttributedString.Key(kCTKernAttributeName as String): tracking,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
            let ascent = CTFontGetAscent(font)
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: x, y: h - y - ascent)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }
}
