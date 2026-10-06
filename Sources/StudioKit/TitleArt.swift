import AppKit
import CoreText
import Foundation

extension ReelTitle.Face {
    /// PostScript names of the title, then the line above it. The pitch.dog
    /// faces come from the bundled fonts; these are what they fall back to.
    var fontNames: (title: String, kicker: String) {
        switch self {
        case .pitchdog: return ("AvenirNext-DemiBold", "AvenirNext-Medium")
        case .pitchdogItalic: return ("AvenirNext-DemiBoldItalic", "AvenirNext-Medium")
        case .modern: return ("AvenirNext-Bold", "AvenirNext-DemiBold")
        case .grotesk: return ("HelveticaNeue-Bold", "HelveticaNeue-Medium")
        case .editorial: return ("Didot", "AvenirNext-DemiBold")
        case .poster: return ("Futura-CondensedExtraBold", "Futura-Medium")
        }
    }

    /// Line height and tracking (in em) the title is set with.
    var titleSetting: (lineHeight: CGFloat, tracking: CGFloat) {
        switch self {
        // The type system's social.display: PD Head 600, 0.88 leading, −0.043 em.
        case .pitchdog, .pitchdogItalic: return (0.88, -0.043)
        case .modern: return (1.04, -0.018)
        case .grotesk: return (1.02, -0.024)
        case .editorial: return (1.06, -0.012)
        case .poster: return (0.96, 0.004)
        }
    }

    /// How large the title runs against the others at the same setting, so each
    /// face reads at about the same weight on the frame.
    var scale: CGFloat {
        switch self {
        case .pitchdog, .pitchdogItalic: return 1.06
        case .modern, .grotesk: return 1
        case .editorial: return 1.14
        case .poster: return 1.2
        }
    }

    /// The title's font at `size`: PD Head at 600 for pitch.dog, upright or italic.
    public func titleFont(_ size: CGFloat) -> CTFont {
        switch self {
        case .pitchdog: return PDType.head(size, weight: 600) ?? Faces.font(fontNames.title, size: size)
        case .pitchdogItalic: return PDType.head(size, weight: 600, italic: true) ?? Faces.font(fontNames.title, size: size)
        default: return Faces.font(fontNames.title, size: size)
        }
    }

    /// The line above's font at `size`: PD Eyebrow 500 at its narrow width for pitch.dog (social.metadata).
    func kickerFont(_ size: CGFloat) -> CTFont {
        switch self {
        case .pitchdog, .pitchdogItalic: return PDType.eyebrow(size) ?? Faces.font(fontNames.kicker, size: size)
        default: return Faces.font(fontNames.kicker, size: size)
        }
    }

    /// Tracking of the line above's capitals, in em.
    var kickerTracking: CGFloat {
        switch self {
        case .pitchdog, .pitchdogItalic: return 0.055
        default: return 0.16
        }
    }
}

/// Sets a reel title into a transparent frame: the line above in small
/// tracked capitals, the title beneath it, each sized to the frame.
public enum TitleArt {
    /// `title` ready to draw over a composition, in light or dark ink; nil when
    /// it has no words. `cues` land its words on the beat, one per group, when
    /// the title asks for that.
    public static func overlay(_ title: ReelTitle, light: Bool, cues: [WordCue] = []) -> TitleOverlay? {
        guard !title.isEmpty else { return nil }
        var h = Hasher()
        h.combine(title)
        h.combine(light)
        var overlay = TitleOverlay(key: h.finalize(), timing: title.timing, scrim: title.placement == .centre ? 0.5 : 0) { w, hgt in
            image(title, light: light, width: w, height: hgt)
        }
        if title.beat, !cues.isEmpty {
            overlay.cues = cues
            overlay.pieces = { w, hgt in pieces(title, width: w, height: hgt) }
            overlay.motion = title.motion
        }
        return overlay
    }

    static let paper = CGColor(srgbRed: 0.97, green: 0.965, blue: 0.955, alpha: 1)
    static let ink = CGColor(srgbRed: 0.075, green: 0.078, blue: 0.086, alpha: 1)

    /// The most words a title takes before it reads as a paragraph.
    public static func maxWords(_ placement: ReelTitle.Placement) -> Int { placement == .centre ? 10 : 14 }

    /// Lines of one block, broken to a width.
    struct Block {
        var lines: [CTLine]
        var lineHeight: CGFloat
        var cap: CGFloat
        var descent: CGFloat

        /// From the top of the first line's capitals to the bottom of the last line's descenders.
        var height: CGFloat { cap + lineHeight * CGFloat(lines.count - 1) + descent }

        func width(_ line: CTLine) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
        }
    }

    static func block(_ text: String, font: CTFont, tracking: CGFloat, lineHeight: CGFloat, maxLines: Int,
                      color: CGColor, maxWidth: CGFloat, balanced: Bool = false) -> Block? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let size = CTFontGetSize(font)
        guard !trimmed.isEmpty, size > 1 else { return nil }
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking * size,
        ]
        let string = NSAttributedString(string: trimmed, attributes: attrs)
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        let length = string.length
        var width = maxWidth
        if balanced {
            // Break at the narrowest width that takes no more lines, so a title
            // ends on a full line rather than one stray word. A width that would
            // break inside a word counts as too narrow.
            let chars = string.string as NSString
            func count(_ w: CGFloat) -> Int {
                var n = 0, at = 0
                while at < length, n <= maxLines {
                    at += max(1, CTTypesetterSuggestLineBreak(typesetter, at, Double(w)))
                    n += 1
                    if at < length, let last = UnicodeScalar(chars.character(at: at - 1)),
                       !CharacterSet.whitespacesAndNewlines.contains(last), last != "-", last != "\u{2013}", last != "/" {
                        return maxLines + 1
                    }
                }
                return n
            }
            let lines = count(maxWidth)
            if lines > 1, lines <= maxLines {
                var lo = maxWidth * 0.45, hi = maxWidth
                for _ in 0..<12 {
                    let mid = (lo + hi) / 2
                    if count(mid) == lines { hi = mid } else { lo = mid }
                }
                width = hi
            }
        }
        var lines: [CTLine] = []
        var start = 0
        while start < length {
            if lines.count == max(maxLines, 1) - 1 {
                // The last line allowed takes the rest, cut short with an ellipsis if need be.
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: length - start))
                let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))
                lines.append(CTLineCreateTruncatedLine(rest, Double(maxWidth), .end, ellipsis) ?? rest)
                break
            }
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return Block(lines: lines, lineHeight: lineHeight * size, cap: CTFontGetCapHeight(font), descent: CTFontGetDescent(font))
    }

    /// Where platform interface covers the frame, as the stage's safe-area guides show it.
    static func insets(_ w: CGFloat, _ h: CGFloat) -> (top: CGFloat, bottom: CGFloat, right: CGFloat) {
        let aspect = w / max(h, 1)
        if aspect < 0.62 { return (h * 0.10, h * 0.22, w * 0.18) }  // reel
        if aspect < 0.9 { return (h * 0.06, h * 0.12, 0) }          // portrait
        return (0, 0, 0)
    }

    /// Title size in pixels: a share of the frame's width or height, whichever is smaller.
    static func titleSize(card: Bool, _ w: CGFloat, _ h: CGFloat) -> CGFloat {
        card ? min(0.104 * w, 0.086 * h) : min(0.066 * w, 0.054 * h)
    }

    static func kickerSize(_ w: CGFloat, _ h: CGFloat) -> CGFloat { min(0.027 * w, 0.022 * h) }

    /// The words set and placed for a frame: each block with its point size,
    /// the gap between them, and the top of the stack measured down from the
    /// top of the frame.
    struct Setting {
        var stack: [(Block, CGFloat)]
        var gap: CGFloat
        var top: CGFloat
        var total: CGFloat
        var card: Bool
        var margin: CGFloat
        /// Whether the first block is the line above the title.
        var hasKicker: Bool
    }

    static func setting(_ title: ReelTitle, color: CGColor, width W: CGFloat, height H: CGFloat) -> Setting? {
        let card = title.placement == .centre
        let inset = insets(W, H)
        let margin = 0.055 * min(W, H)
        let face = title.face
        let titlePt = titleSize(card: card, W, H) * face.scale
        let kickerPt = kickerSize(W, H)
        let titleSetting = face.titleSetting

        // Measure: a caption stays in its corner's column; a title card stays
        // clear of a reel's side controls on both sides, so it stays centred.
        let side = card ? max(inset.right, margin * 1.6) : margin
        let maxWidth = card ? W - 2 * side : min(W * 0.62, W - 2 * margin - inset.right)
        let kicker = block(title.kicker.uppercased(), font: face.kickerFont(kickerPt), tracking: face.kickerTracking, lineHeight: 1.25,
                           maxLines: 2, color: color.copy(alpha: 0.82) ?? color, maxWidth: maxWidth)
        let main = block(title.text, font: face.titleFont(titlePt), tracking: titleSetting.tracking,
                         lineHeight: titleSetting.lineHeight, maxLines: 4, color: color, maxWidth: maxWidth, balanced: true)
        let gap = kickerPt * 1.0 + titlePt * 0.16
        let stack: [(Block, CGFloat)] = [kicker.map { ($0, kickerPt) }, main.map { ($0, titlePt) }].compactMap { $0 }
        guard !stack.isEmpty else { return nil }
        let total = stack.map(\.0.height).reduce(0, +) + (stack.count > 1 ? gap : 0)

        // Place: y measured down from the top of the frame.
        let top: CGFloat
        if card {
            let upper = inset.top, lower = H - inset.bottom
            top = upper + (lower - upper - total) / 2
        } else if inset.bottom > H * 0.15 {
            // A reel's captions and buttons cover its foot, so its caption hangs from the top.
            top = inset.top + margin
        } else {
            top = H - inset.bottom - margin - total
        }
        return Setting(stack: stack, gap: gap, top: top, total: total, card: card, margin: margin, hasKicker: kicker != nil)
    }

    /// How far a caption reaches into the frame from the edge it sits on, as
    /// shares of the frame's height, with a little air: what a grid of
    /// pictures should keep clear of. Zero for a title card, which dims the
    /// stage behind it instead.
    public static func reach(_ title: ReelTitle, width: Int, height: Int) -> (top: Double, bottom: Double) {
        guard title.placement == .corner, !title.isEmpty, width > 8, height > 8,
              let s = setting(title, color: ink, width: CGFloat(width), height: CGFloat(height)) else { return (0, 0) }
        let H = CGFloat(height)
        let air = s.margin * 0.6
        if s.top < H / 2 { return (Double((s.top + s.total + air) / H), 0) }
        return (0, Double((H - s.top + air) / H))
    }

    /// Where each group of words that lands on the beat sits in a frame of this
    /// pixel size: the line above as one piece, then the title's groups line by
    /// line. The pieces tile the frame, split halfway across the space between
    /// groups and between lines, so each carries its words' shadow with it.
    public static func pieces(_ title: ReelTitle, width: Int, height: Int) -> [TitlePiece] {
        let W = CGFloat(width), H = CGFloat(height)
        guard width > 8, height > 8, let s = setting(title, color: ink, width: W, height: H) else { return [] }
        let groups = ReelTitle.groups(title.text)
        let first = s.hasKicker ? 1 : 0
        struct Row {
            var top: CGFloat
            var bottom: CGFloat
            var spans: [(x0: CGFloat, x1: CGFloat, cue: Int)]
        }
        var rows: [Row] = []
        var top = s.top
        for (k, (b, _)) in s.stack.enumerated() {
            let kicker = s.hasKicker && k == 0
            var baseline = top + b.cap
            for line in b.lines {
                let wide = b.width(line)
                let x = s.card ? (W - wide) / 2 : s.margin
                var spans: [(x0: CGFloat, x1: CGFloat, cue: Int)] = []
                if kicker {
                    spans = [(x, x + wide, 0)]
                } else {
                    let r = CTLineGetStringRange(line)
                    let lo = r.location, hi = r.location + r.length
                    for (g, range) in groups.enumerated() where range.lowerBound < hi && range.upperBound > lo {
                        let a = CTLineGetOffsetForStringIndex(line, max(range.lowerBound, lo), nil)
                        let e = CTLineGetOffsetForStringIndex(line, min(range.upperBound, hi), nil)
                        spans.append((x + min(max(a, 0), wide), x + min(max(e, 0), wide), first + g))
                    }
                }
                if !spans.isEmpty { rows.append(Row(top: baseline - b.cap, bottom: baseline + b.descent, spans: spans)) }
                baseline += b.lineHeight
            }
            top += b.height + s.gap
        }
        var out: [TitlePiece] = []
        for (i, row) in rows.enumerated() {
            let y0 = i == 0 ? 0 : (rows[i - 1].bottom + row.top) / 2
            let y1 = i == rows.count - 1 ? H : (row.bottom + rows[i + 1].top) / 2
            for (j, span) in row.spans.enumerated() {
                let x0 = j == 0 ? 0 : (row.spans[j - 1].x1 + span.x0) / 2
                let x1 = j == row.spans.count - 1 ? W : (span.x1 + row.spans[j + 1].x0) / 2
                let words = SIMD4(Float(span.x0 / W), Float(row.top / H), Float(span.x1 / W), Float(row.bottom / H))
                out.append(TitlePiece(rect: SIMD4(Float(x0 / W), Float(y0 / H), Float(x1 / W), Float(y1 / H)), cue: span.cue, words: words))
            }
        }
        return out
    }

    /// The title over a transparent frame of this pixel size.
    static func image(_ title: ReelTitle, light: Bool, width: Int, height: Int) -> CGImage? {
        guard width > 8, height > 8,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let W = CGFloat(width), H = CGFloat(height)
        guard let set = setting(title, color: light ? paper : ink, width: W, height: H) else { return nil }
        let card = set.card, margin = set.margin, gap = set.gap, stack = set.stack
        var top = set.top

        ctx.textMatrix = .identity
        for (b, size) in stack {
            if light {
                // A soft shadow keeps light words legible over bright passages.
                ctx.setShadow(offset: CGSize(width: 0, height: -0.03 * size), blur: 0.45 * size,
                              color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.34))
            }
            var baseline = top + b.cap
            for line in b.lines {
                let x = card ? (W - b.width(line)) / 2 : margin
                ctx.textPosition = CGPoint(x: x, y: H - baseline)
                CTLineDraw(line, ctx)
                baseline += b.lineHeight
            }
            top += b.height + gap
        }
        return ctx.makeImage()
    }
}
