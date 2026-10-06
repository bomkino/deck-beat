import AppKit
import BeatKit
import StudioKit
import SwiftUI

/// A transport that knows the song: the clip's waveform with its bars, drops
/// and featured moments, and below it the whole song with the clip marked,
/// to slide along or to snap back to the best part.
struct SongTransport: View {
    let session: BeatSession
    @Bindable var clock: PlaybackClock
    @AppStorage("previewMuted") private var muted = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                IconButton(clock.playing ? "pause.fill" : "play.fill", label: clock.playing ? "Pause" : "Play", size: 15) {
                    session.togglePlay()
                }
                .keyboardShortcut(clock.typing ? nil : KeyboardShortcut(.space, modifiers: []))
                IconButton("backward.end.fill", label: "Back to the Start") { session.rewind() }
                ClipTimeline(session: session, clock: clock)
                    .frame(height: 46)
                HStack(spacing: 4) {
                    Text(stamp(clock.time)).textStyle(.data).foregroundStyle(.primary)
                    Text("/").textStyle(.data).foregroundStyle(.tertiary)
                    Text(stamp(clock.duration)).textStyle(.data).foregroundStyle(.secondary)
                }
                .fixedSize()
                IconButton(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: muted ? "Sound Off" : "Sound On") {
                    muted.toggle()
                }
                .help(muted ? "Play with the sound on" : "Watch with the sound off, as most Reels first play")
            }
            HStack(spacing: 12) {
                Text("Clip").textStyle(.label).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                SongStrip(session: session)
                    .frame(height: 24)
                ChoiceRow(ClipLength.allCases.map { ($0, $0 == .whole ? "Whole" : "\($0.rawValue) s") },
                          selection: Binding(get: { session.project.clip.length }, set: { session.setClip($0) }))
                    .frame(width: 270)
                Button("Best Part") { session.bestPart() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(session.project.clip.bestPart || session.project.clip.length == .whole)
                    .help("Move the clip to the strongest stretch of the song")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surround)
    }

    private func stamp(_ t: Double) -> String {
        let total = max(0, t)
        return String(format: "%d:%04.1f", Int(total) / 60, total.truncatingRemainder(dividingBy: 60))
    }
}

/// The clip, drawn as the song's shape: bar lines, the drop, the moments a
/// slide steps forward, the intro and the ending. Drag to scrub.
struct ClipTimeline: View {
    let session: BeatSession
    @Bindable var clock: PlaybackClock
    @State private var scrubbing = false
    @State private var wasPlaying = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let marks = Marks(session)
            let f = CGFloat(clock.time / max(clock.duration, 0.001))
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in marks.draw(in: ctx, size: size) }
                    .allowsHitTesting(false)
                Rectangle().fill(Theme.accent)
                    .frame(width: 2, height: geo.size.height)
                    .offset(x: max(0, min(w, f * w)) - 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !scrubbing { scrubbing = true; wasPlaying = clock.playing; clock.playing = false }
                    clock.time = Double(max(0, min(1, g.location.x / max(w, 1)))) * clock.duration
                    session.touch()
                }
                .onEnded { _ in
                    scrubbing = false
                    clock.playing = wasPlaying
                })
        }
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityValue(String(format: "%.1f of %.1f seconds", clock.time, clock.duration))
    }

    /// What the timeline shows, read once per redraw.
    struct Marks {
        var outline: [Float] = []
        var downbeats: [Double] = []
        var beats: [Double] = []
        var drops: [Double] = []
        var features: [(Double, Double)] = []
        var introEnd: Double = 0
        var outroStart: Double = 0
        var length: Double = 1

        @MainActor
        init(_ session: BeatSession) {
            guard let song = session.song, let planned = session.planned(for: session.project.format) else { return }
            let plan = planned.plan
            length = max(plan.length, 0.001)
            let clip = planned.clip
            let slots = song.outline.count
            if slots > 1, song.duration > 0 {
                let a = min(max(0, Int(clip.start / song.duration * Double(slots))), slots - 1)
                let b = min(slots, max(a + 1, Int((clip.start + clip.length) / song.duration * Double(slots))))
                outline = Array(song.outline[a..<b])
            }
            downbeats = plan.downbeats.filter { $0 >= 0 && $0 <= length }
            beats = plan.beats.filter { $0 >= 0 && $0 <= length }
            drops = plan.drops
            features = plan.features.map { ($0.land, $0.leave) }
            introEnd = plan.intro.end
            outroStart = plan.outro.start
        }

        func draw(in ctx: GraphicsContext, size: CGSize) {
            let w = size.width, h = size.height
            func x(_ t: Double) -> CGFloat { CGFloat(t / length) * w }
            let mid = h * 0.5
            // Intro and ending, shaded.
            ctx.fill(Path(CGRect(x: 0, y: 0, width: x(introEnd), height: h)), with: .color(.secondary.opacity(0.08)))
            if outroStart < length {
                ctx.fill(Path(CGRect(x: x(outroStart), y: 0, width: w - x(outroStart), height: h)), with: .color(.secondary.opacity(0.08)))
            }
            // The song's shape.
            if !outline.isEmpty {
                let n = outline.count
                let step = max(1, n / max(Int(w / 3), 1))
                var i = 0
                while i < n {
                    let v = CGFloat(outline[i..<min(n, i + step)].max() ?? 0)
                    let px = CGFloat(i) / CGFloat(n) * w
                    let bh = max(1.5, v * (h - 12))
                    let shade: Double = v > 0.75 ? 0.62 : (v > 0.45 ? 0.45 : 0.3)
                    ctx.fill(Path(roundedRect: CGRect(x: px, y: mid - bh / 2, width: max(1.5, w / CGFloat(n) * CGFloat(step) - 1), height: bh),
                                  cornerRadius: 0.75), with: .color(.secondary.opacity(shade)))
                    i += step
                }
            }
            // Beats short, downbeats tall, every fourth bar numbered.
            for b in beats { ctx.fill(Path(CGRect(x: x(b) - 0.5, y: h - 4, width: 1, height: 4)), with: .color(.secondary.opacity(0.4))) }
            for (k, d) in downbeats.enumerated() {
                ctx.fill(Path(CGRect(x: x(d) - 0.5, y: h - 9, width: 1, height: 9)), with: .color(.secondary.opacity(0.7)))
                if k % 4 == 0 {
                    ctx.draw(Text("\(k + 1)").font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary),
                             at: CGPoint(x: x(d) + 3, y: h - 6), anchor: .leading)
                }
            }
            // Featured slides step forward here.
            for (a, b) in features {
                ctx.fill(Path(roundedRect: CGRect(x: x(a), y: 1, width: max(3, x(b) - x(a)), height: 4), cornerRadius: 2),
                         with: .color(.primary.opacity(0.45)))
            }
            // Drops.
            for d in drops {
                var p = Path()
                p.move(to: CGPoint(x: x(d) - 5, y: 0))
                p.addLine(to: CGPoint(x: x(d) + 5, y: 0))
                p.addLine(to: CGPoint(x: x(d), y: 7))
                p.closeSubpath()
                ctx.fill(p, with: .color(.orange))
                ctx.fill(Path(CGRect(x: x(d) - 0.75, y: 0, width: 1.5, height: h)), with: .color(.orange.opacity(0.5)))
            }
        }
    }
}

/// The whole song, with the clip as a bracket to drag along it.
struct SongStrip: View {
    let session: BeatSession
    @State private var grab: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let song = session.song
            let duration = max(song?.duration ?? 1, 0.001)
            let clip = session.clip
            let x0 = CGFloat((clip?.start ?? 0) / duration) * w
            let x1 = CGFloat(((clip?.start ?? 0) + (clip?.length ?? 0)) / duration) * w
            let outline = song?.outline ?? []
            let drops = song?.analysis.drops ?? []
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let n = outline.count
                    guard n > 1 else { return }
                    let columns = max(1, Int(size.width / 2))
                    for c in 0..<columns {
                        let a = c * n / columns, b = max(a + 1, (c + 1) * n / columns)
                        let v = CGFloat(outline[a..<min(n, b)].max() ?? 0)
                        let px = CGFloat(c) / CGFloat(columns) * size.width
                        let inside = px >= x0 && px <= x1
                        let bh = max(1, v * (size.height - 6))
                        ctx.fill(Path(CGRect(x: px, y: (size.height - bh) / 2, width: 1.2, height: bh)),
                                 with: .color(.secondary.opacity(inside ? 0.7 : 0.28)))
                    }
                    for d in drops {
                        let px = CGFloat(d / duration) * size.width
                        ctx.fill(Path(CGRect(x: px - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(.orange.opacity(0.7)))
                    }
                }
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.accent.opacity(0.08)))
                    .frame(width: max(6, x1 - x0), height: h)
                    .offset(x: x0)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { g in
                    guard let c = session.clip, session.project.clip.length != .whole else { return }
                    let t = Double(g.location.x / max(w, 1)) * duration
                    if grab == nil {
                        // Grabbed inside the bracket it carries; outside, it centres there.
                        grab = (t >= c.start && t <= c.start + c.length) ? t - c.start : c.length / 2
                        session.begin("Move Clip")
                    }
                    session.moveClip(to: min(max(0, t - (grab ?? 0)), max(0, duration - c.length)))
                }
                .onEnded { _ in
                    grab = nil
                    session.commit("Move Clip")
                })
            .help("Drag the clip along the song")
        }
    }
}
