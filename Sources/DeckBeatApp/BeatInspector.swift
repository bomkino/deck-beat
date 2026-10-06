import AppKit
import BeatKit
import StudioKit
import SwiftUI

enum InspectorPage: String, CaseIterable, Identifiable {
    case beat, grid, cells, intro, title, stage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .beat: return "Beat"
        case .grid: return "Grid"
        case .cells: return "Cells"
        case .intro: return "Intro"
        case .title: return "Title"
        case .stage: return "Stage"
        }
    }
}

struct BeatInspector: View {
    @Bindable var session: BeatSession
    @AppStorage("inspectorPage") private var page = InspectorPage.beat.rawValue

    var body: some View {
        VStack(spacing: 0) {
            ChoiceRow(InspectorPage.allCases.map { ($0.rawValue, $0.title) }, selection: $page)
                .padding(12)
            Hairline()
            ScrollView {
                VStack(spacing: 0) {
                    switch InspectorPage(rawValue: page) ?? .beat {
                    case .beat: BeatPage(session: session)
                    case .grid: GridPage(session: session)
                    case .cells: CellsPage(session: session)
                    case .intro: IntroPage(session: session)
                    case .title: TitlePage(session: session)
                    case .stage: StagePage(session: session)
                    }
                }
                .padding(.bottom, 24)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .background(Theme.chrome)
    }
}

// MARK: - Shared rows

/// Sliders and switches bound to the project, with one undo step per gesture.
@MainActor
struct Rows {
    let session: BeatSession

    func slider(_ label: String, _ path: WritableKeyPath<BeatProject, Float>, _ range: ClosedRange<Float> = 0...1, reset: Float,
                format: @escaping (Float) -> String = { "\(Int(($0 * 100).rounded()))%" }) -> some View {
        ValueSlider(label, value: Binding(get: { session.project[keyPath: path] }, set: { v in session.live { $0[keyPath: path] = v } }),
                    range: range, defaultValue: reset, format: format,
                    onBegin: { session.begin(label) }, onCommit: { session.commit(label) })
    }

    func seconds(_ label: String, _ path: WritableKeyPath<BeatProject, Double>, _ range: ClosedRange<Float>, reset: Float,
                 format: @escaping (Float) -> String) -> some View {
        ValueSlider(label, value: Binding(get: { Float(session.project[keyPath: path]) },
                                          set: { v in session.live { $0[keyPath: path] = Double(v) } }),
                    range: range, defaultValue: reset, format: format,
                    onBegin: { session.begin(label) }, onCommit: { session.commit(label) })
    }

    func toggle(_ label: String, _ path: WritableKeyPath<BeatProject, Bool>, help: String = "") -> some View {
        Toggle(isOn: Binding(get: { session.project[keyPath: path] }, set: { v in session.update(label) { $0[keyPath: path] = v } })) {
            Text(label).textStyle(.bodyCompact).foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help(help)
    }

    func choice<T: Hashable>(_ label: String, _ path: WritableKeyPath<BeatProject, T>, _ options: [(T, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty { Text(label).textStyle(.bodyCompact).foregroundStyle(.secondary) }
            ChoiceRow(options, selection: Binding(get: { session.project[keyPath: path] }, set: { v in session.update(label.isEmpty ? "Change" : label) { $0[keyPath: path] = v } }))
        }
    }
}

func percent(_ v: Float) -> String { "\(Int((v * 100).rounded()))%" }
func px(_ v: Float) -> String { "\(Int(v.rounded())) px" }
func degrees(_ v: Float) -> String { "\(Int(v.rounded()))°" }
func times(_ v: Float) -> String { String(format: "%.2f×", v) }

// MARK: - Beat

struct BeatPage: View {
    let session: BeatSession
    @State private var more = false

    var body: some View {
        let r = Rows(session: session)
        let s = session.project.settings
        VStack(spacing: 0) {
            InspectorSection("Look", accessory: {
                Button { session.reroll() } label: { Image(systemName: "dice").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("New variation")
            }) {
                LookStrip(session: session)
                Text(session.look.summary).textStyle(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Hairline().padding(.horizontal, 16)
            InspectorSection("Music") {
                r.choice("", \.settings.mode, BeatMode.allCases.map { ($0, short($0)) })
                Text(s.mode.summary).textStyle(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 4) {
                    r.slider("Sensitivity", \.settings.sensitivity, reset: 0.6)
                    r.choice("Step forward every", \.settings.feature, FeatureEvery.allCases.map { ($0, $0 == .off ? "Off" : "\($0.rawValue)") })
                        .padding(.vertical, 4)
                }
            }
            Hairline().padding(.horizontal, 16)
            InspectorSection("Moves") {
                VStack(alignment: .leading, spacing: 10) {
                    r.choice("On the drop", \.settings.dropMove, DropMove.allCases.map { ($0, $0.title) })
                    Text(s.dropMove.summary).textStyle(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    if s.feature != .off {
                        r.choice("A slide comes forward by", \.settings.featureStyle, FeatureStyle.allCases.map { ($0, $0.title) })
                    }
                    r.choice("Cells turn over by", \.settings.turn, TurnStyle.allCases.map { ($0, $0.title) })
                }
            }
            Hairline().padding(.horizontal, 16)
            SongBeatSection(session: session)
            Hairline().padding(.horizontal, 16)
            InspectorSection("Slides") {
                VStack(spacing: 4) {
                    r.slider("Rest light", \.settings.rest.brightness, 0...1.5, reset: 0.4)
                    r.slider("Rest colour", \.settings.rest.colour, 0...1.3, reset: 0.2)
                    r.slider("Lit size", \.settings.lit.scale, 0.5...1.5, reset: 1.06, format: times)
                    r.slider("Lit lift", \.settings.lit.lift, -0.1...0.15, reset: 0.04, format: { String(format: "%.2f", $0) })
                    r.slider("Lit glow", \.settings.lit.glow, reset: 0.25)
                    r.seconds("Tail", \.settings.motion.release, 0.25...4, reset: 1, format: { String(format: "%.2g beat%@", $0, $0 == 1 ? "" : "s") })
                    r.choice("Idle", \.settings.motion.idle, IdleMotion.allCases.map { ($0, $0.title) })
                        .padding(.top, 4)
                }
            }
            Hairline().padding(.horizontal, 16)
            DisclosureGroup(isExpanded: $more) {
                VStack(alignment: .leading, spacing: 10) {
                    r.choice("Listen to", \.settings.listen, Listen.allCases.map { ($0, $0.title) })
                    switch s.mode {
                    case .ripple:
                        r.slider("Ring speed", \.settings.spread, 0.25...2, reset: 0.75, format: { String(format: "%.2g beat", $0) })
                    case .readThrough:
                        r.choice("Step", \.settings.step, [(0, "Auto"), (1, "Beat"), (0.5, "½"), (0.25, "¼")])
                    case .equaliser:
                        r.toggle("Grow from the middle", \.settings.fromMiddle)
                    default:
                        EmptyView()
                    }
                    r.toggle("Breathe in before a drop, and hit it", \.settings.drops)
                    r.toggle("Spotlight the slide that steps forward", \.settings.spotlight)
                    r.toggle("Turn cells over to show every slide", \.settings.grid.rotate)
                }
                .padding(.top, 8)
            } label: {
                Text("More").textStyle(.label)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func short(_ m: BeatMode) -> String {
        switch m {
        case .pulse: return "Pulse"
        case .ripple: return "Ripple"
        case .equaliser: return "EQ"
        case .readThrough: return "Read"
        case .lightsOn: return "Lights"
        }
    }
}

/// Corrections for a song whose beat was heard wrong.
struct SongBeatSection: View {
    let session: BeatSession

    var body: some View {
        let r = Rows(session: session)
        let fix = session.project.beat
        InspectorSection("Song’s beat", accessory: {
            if !fix.isNone {
                Button { session.setBeat("Reset the Beat") { $0 = .none } } label: { Text("Reset").textStyle(.caption) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Back to the beat as heard")
            }
        }) {
            Text(heard).textStyle(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Tempo").textStyle(.bodyCompact).foregroundStyle(.secondary)
                ChoiceRow(BeatFix.Speed.allCases.map { ($0, $0.title) },
                          selection: Binding(get: { fix.speed }, set: { v in session.setBeat("Tempo") { $0.speed = v } }))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Bars start on beat").textStyle(.bodyCompact).foregroundStyle(.secondary)
                ChoiceRow([(0, "1"), (1, "2"), (2, "3"), (3, "4")],
                          selection: Binding(get: { fix.barShift }, set: { v in session.setBeat("Bar One") { $0.barShift = v } }))
            }
            r.seconds("Nudge", \.beat.nudge, Float(BeatFix.nudgeRange.lowerBound)...Float(BeatFix.nudgeRange.upperBound), reset: 0,
                      format: { v in let ms = Int((v * 1000).rounded()); return ms > 0 ? "+\(ms) ms" : "\(ms) ms" })
        }
    }

    private var heard: String {
        guard let song = session.song, let a = session.analysis else { return "Listening…" }
        let asHeard = Int(song.analysis.tempo.rounded()), now = Int(a.tempo.rounded())
        let drops = a.drops.count == 1 ? "1 drop" : "\(a.drops.count) drops"
        let lead = now == asHeard ? "Heard at \(asHeard) BPM, \(drops)." : "Heard at \(asHeard) BPM, playing at \(now) BPM, \(drops)."
        return lead + " If the lights miss the beat: halve or double the tempo, move where bars start, or nudge it."
    }
}

/// The seven looks, each shown on this deck and song.
struct LookStrip: View {
    let session: BeatSession

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
            ForEach(Looks.all) { look in
                LookCard(session: session, look: look, selected: look.id == session.project.look) { session.choose(look) }
            }
        }
    }
}

struct LookCard: View {
    let session: BeatSession
    let look: Look
    let selected: Bool
    let action: () -> Void
    @State private var image: CGImage?
    @State private var loading: Task<Void, Never>?

    private var key: String {
        var h = Hasher()
        h.combine(look.id)
        h.combine(session.project.slides.map(\.id))
        h.combine(session.textures.count)
        h.combine(session.song.map { ObjectIdentifier($0) })
        h.combine(session.project.format.id)
        h.combine(session.project.settings.grid)
        h.combine(session.project.clip)
        h.combine(session.project.beat)
        return "look|\(h.finalize())"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    Theme.well
                    if let image { Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill) }
                }
                .frame(height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1))
                Text(look.name).textStyle(.caption).foregroundStyle(selected ? Theme.accentInk : .secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(look.summary)
        .onAppear(perform: load)
        .onChange(of: key) { _, _ in load() }
    }

    /// Redraws the card once a change settles: a slider drag replans the look
    /// once at the end, off the main thread, rather than on every step.
    private func load() {
        loading?.cancel()
        guard session.isReady else { return }
        let key = self.key
        if let cached = TileRenderer.shared.cachedImage(key) {
            image = cached
            return
        }
        let p = session.wearing(look, on: session.project)
        guard let job = session.planJob(for: p, format: .square) else { return }
        let settle = image == nil ? 0 : 250
        loading = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(settle))
            guard !Task.isCancelled else { return }
            let planned = await Task.detached(priority: .utility) { job() }.value
            // A square crop of the grid partway in, so the look is mid-song.
            guard !Task.isCancelled, let comp = session.composition(of: p, format: .square, planned: planned) else { return }
            let time = min(6.5, planned.plan.length * 0.3)
            TileRenderer.shared.still(key: key, comp: comp, time: time, size: CGSize(width: 280, height: 184)) { img in
                if let img { image = img }
            }
        }
    }
}

// MARK: - Grid

struct GridPage: View {
    let session: BeatSession

    var body: some View {
        let r = Rows(session: session)
        let g = session.project.settings.grid
        VStack(spacing: 0) {
            InspectorSection("Size") {
                // Sizes of about 15, 24, 30 and 60 cells, shaped for these slides: wide slides get more rows.
                let presets = presets(for: session)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(presets, id: \.self) { p in
                        let on = g.columns == p.columns && g.rows == p.rows
                        Button { session.usePreset(p) } label: {
                            Text("\(p.columns)×\(p.rows) · \(p.columns * p.rows)").textStyle(.caption).foregroundStyle(on ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity).frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.segmentOn : Theme.well.opacity(0.7)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 6) {
                    Button { session.fitDeck() } label: { Label("Fit my deck (\(session.project.slides.count) slides)", systemImage: "rectangle.3.group") }
                        .buttonStyle(QuietButtonStyle())
                        .padding(.leading, -10)
                    if session.project.gridFollowsDeck {
                        Spacer(minLength: 0)
                        Label("Follows the deck", systemImage: "checkmark").labelStyle(.titleAndIcon)
                            .textStyle(.caption).foregroundStyle(.tertiary)
                            .help("The grid refits as you add or remove slides, until you set its size by hand")
                    }
                }
                HStack {
                    Stepper(value: Binding(get: { g.columns }, set: { session.setGrid(columns: $0, rows: g.rows) }), in: GridSettings.columnRange) {
                        Text("\(g.columns) across").textStyle(.bodyCompact).monospacedDigit()
                    }
                    Spacer()
                    Stepper(value: Binding(get: { g.rows }, set: { session.setGrid(columns: g.columns, rows: $0) }), in: GridSettings.rowRange) {
                        Text("\(g.rows) down").textStyle(.bodyCompact).monospacedDigit()
                    }
                }
                VStack(spacing: 4) {
                    r.slider("Gap", \.settings.grid.gap, 0...80, reset: 20, format: px)
                    r.slider("Corners", \.settings.grid.corner, 0...40, reset: 12, format: px)
                }
            }
            Hairline().padding(.horizontal, 16)
            InspectorSection("Shape") {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cells").textStyle(.bodyCompact).foregroundStyle(.secondary)
                        ChoiceRow(CellShape.allCases.map { ($0, $0.title) }, selection: Binding(get: { g.shape }, set: { session.setShape($0) }))
                    }
                    if let layout = session.planned(for: session.project.format)?.layout {
                        Text(shapeNote(layout, auto: g.shape == .auto))
                            .textStyle(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    r.choice("Margins", \.settings.grid.margins, Margins.allCases.map { ($0, $0.title) })
                    r.choice("Wall", \.settings.grid.wall, [(Wall.flat, "Flat"), (Wall.lean, "Lean"), (Wall.angle, "Angle")])
                    r.slider("Mirror floor", \.settings.grid.wall.reflection, 0...0.5, reset: 0)
                }
            }
            Hairline().padding(.horizontal, 16)
            InspectorSection("Order") {
                r.choice("", \.settings.grid.order, SlideOrder.allCases.map { ($0, $0.title) })
                Text("Star a slide to make it the cover: it opens and closes the video, and steps forward twice as often.")
                    .textStyle(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension GridPage {
    /// About 15, 24, 30 and 60 cells, each fitted to the deck's slide shape, without repeats.
    func presets(for session: BeatSession) -> [GridSettings] {
        var seen = Set<Int>()
        return [15, 24, 30, 60].map { session.gridPreset(about: $0) }.filter { seen.insert($0.columns * 100 + $0.rows).inserted }
    }

    func shapeNote(_ layout: BeatKit.GridLayout, auto: Bool) -> String {
        let crop = Int((layout.crop * 100).rounded())
        if layout.shape == .fill, crop >= 1 {
            let lead = auto ? "Auto fills the frame" : "Filled cells"
            return "\(lead): about \(crop)% of each slide is cropped at rest, and it shows whole when it steps forward."
        }
        return auto ? "Auto keeps every slide whole." : "Every slide shows whole."
    }
}

// MARK: - Cells

struct CellsPage: View {
    let session: BeatSession
    @State private var lit = true

    var body: some View {
        let r = Rows(session: session)
        let state: WritableKeyPath<BeatProject, CellState> = lit ? \.settings.lit : \.settings.rest
        let d = lit ? CellState.lit : CellState.rest
        VStack(spacing: 0) {
            InspectorSection(lit ? "Lit" : "At rest") {
                ChoiceRow([(false, "Rest"), (true, "Lit")], selection: $lit)
                Text(lit ? "How a slide looks when the music lights it." : "How a slide waits for the music.")
                    .textStyle(.caption).foregroundStyle(.tertiary)
                VStack(spacing: 4) {
                    r.slider("Size", state.appending(path: \.scale), 0.5...1.5, reset: d.scale, format: times)
                    r.slider("Brightness", state.appending(path: \.brightness), 0...1.5, reset: d.brightness)
                    r.slider("Colour", state.appending(path: \.colour), 0...1.3, reset: d.colour)
                    r.slider("Lift", state.appending(path: \.lift), -0.1...0.15, reset: d.lift, format: { String(format: "%.2f", $0) })
                    r.slider("Glow", state.appending(path: \.glow), reset: d.glow)
                    r.slider("Opacity", state.appending(path: \.opacity), reset: d.opacity)
                    r.slider("Blur", state.appending(path: \.blur), 0...16, reset: d.blur, format: px)
                    r.slider("Shadow", state.appending(path: \.shadow), 0...2, reset: d.shadow, format: times)
                    r.slider("Tilt", state.appending(path: \.tilt), 0...12, reset: d.tilt, format: degrees)
                    r.slider("Tint", state.appending(path: \.tint), reset: d.tint)
                    if lit { r.slider("Open", state.appending(path: \.open), reset: 0) }
                }
                TintSwatches(session: session, path: state.appending(path: \.tintColour))
            }
            Hairline().padding(.horizontal, 16)
            InspectorSection("Motion") {
                VStack(spacing: 4) {
                    r.seconds("Attack", \.settings.motion.attack, 0...0.2, reset: 0.05, format: { "\(Int(($0 * 1000).rounded())) ms" })
                    r.seconds("Hold", \.settings.motion.hold, 0...0.5, reset: 0.25, format: { String(format: "%.2g beat", $0) })
                    r.seconds("Tail", \.settings.motion.release, 0.25...4, reset: 1, format: { String(format: "%.2g beat%@", $0, $0 == 1 ? "" : "s") })
                    r.slider("Bounce", \.settings.motion.bounce, 0...0.25, reset: 0.08)
                    r.choice("Idle", \.settings.motion.idle, IdleMotion.allCases.map { ($0, $0.title) })
                        .padding(.vertical, 4)
                    r.slider("Idle amount", \.settings.motion.idleAmount, reset: 0.25)
                }
            }
        }
    }
}

/// Gel colours: warm, cool and the deck's own.
struct TintSwatches: View {
    let session: BeatSession
    let path: WritableKeyPath<BeatProject, String>

    var body: some View {
        let current = session.project[keyPath: path]
        let deck = session.deckPalette?.colors.map(\.hex) ?? []
        let options = ["#FFFFFF", "#FFB46B", "#FF6B4A", "#8FA6BF", "#7FD1C7"] + deck.prefix(4)
        HStack(spacing: 6) {
            Text("Tint colour").textStyle(.bodyCompact).foregroundStyle(.secondary).frame(width: 86, alignment: .leading)
            ForEach(Array(options.enumerated()), id: \.offset) { _, hex in
                Button { session.update("Tint Colour") { $0[keyPath: path] = hex } } label: {
                    Circle().fill(Color(nsColor: NSColor(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF)))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(current.uppercased() == hex.uppercased() ? Theme.accent : Theme.hairline,
                                                       lineWidth: current.uppercased() == hex.uppercased() ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Intro

struct IntroPage: View {
    let session: BeatSession

    var body: some View {
        let r = Rows(session: session)
        let intro = session.project.settings.intro
        VStack(spacing: 0) {
            InspectorSection("Opening") {
                VStack(alignment: .leading, spacing: 10) {
                    r.toggle("Open on the cover", \.settings.intro.coldOpen,
                             help: "Frame 0 is the cover, large and lit; the deck deals out from behind it")
                    Text("Cards").textStyle(.bodyCompact).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(Entrance.allCases) { e in
                            let on = intro.entrance == e
                            Button { session.update("Entrance") { $0.settings.intro.entrance = e }; session.rewind() } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title).textStyle(.label).foregroundStyle(on ? Color.primary : Color.secondary)
                                    Text(e.summary).textStyle(.caption).foregroundStyle(.tertiary).lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Theme.segmentOn : Theme.well.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Picker(selection: Binding(get: { intro.order }, set: { v in session.update("Order") { $0.settings.intro.order = v }; session.rewind() })) {
                        ForEach(StaggerOrder.allCases) { o in Text(o.title).tag(o) }
                    } label: {
                        Text("Order").textStyle(.bodyCompact).foregroundStyle(.secondary)
                    }
                    r.choice("Length", \.settings.intro.bars, [(0, "Auto"), (1, "1 bar"), (2, "2 bars"), (4, "4 bars")])
                    r.toggle("Land the cover on an early drop", \.landOnDrop,
                             help: "When a drop comes in the clip's first bars, the clip starts so the cover lands on it")
                }
            }
            Hairline().padding(.horizontal, 16)
            InspectorSection("Ending") {
                r.choice("", \.settings.outro, Outro.allCases.map { ($0, $0.title) })
                Text(endingNote).textStyle(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var endingNote: String {
        switch session.clip?.outro ?? .loop {
        case .loop: return "The cards gather back into the cover, so the last frame meets the first and the video loops."
        case .close: return "The cards leave in reverse and the cover rises to hold the last moment."
        case .lightsOut: return "The slides go dark one by one; the cover stays lit to the end."
        default: return "The grid plays to the last frame."
        }
    }
}

// MARK: - Stage

struct StagePage: View {
    let session: BeatSession

    static let backdrops = ["studio", "solid", "linear", "radial", "conic", "softbloom", "mesh", "fade", "aurora", "halo", "bloom", "bokeh",
                            "silk", "iris", "caustics", "smoke", "dotgrid", "halftone"]

    /// A backdrop style's tile, painted in the project's palette.
    static func preview(_ style: BackdropStyle, palette: Palette) -> BackdropSettings {
        var s = style.defaults
        s.palette = palette
        return s
    }

    var body: some View {
        let r = Rows(session: session)
        let b = session.project.backdrop
        VStack(spacing: 0) {
            InspectorSection("Backdrop") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Self.backdrops, id: \.self) { id in
                        let style = BackdropCatalog.style(id)
                        BackdropTile(settings: Self.preview(style, palette: b.palette), title: style.name, selected: b.style == id, size: CGSize(width: 82, height: 52)) {
                            session.update("Backdrop") { p in
                                let palette = p.backdrop.palette
                                let seed = p.backdrop.seed
                                p.backdrop = style.defaults
                                p.backdrop.palette = palette
                                p.backdrop.seed = seed
                                p.backdrop.brightness = min(style.defaults.brightness, 0.85)
                            }
                        }
                    }
                }
                let deck = session.deckPalette.map { [$0] } ?? []
                PalettePicker(selected: b.palette.id, palettes: deck + Palettes.all) { p in
                    session.update("Palette") { $0.backdrop.palette = p }
                }
                Toggle(isOn: Binding(get: { session.project.followDeck }, set: { session.followDeck($0) })) {
                    Text("Take its colours from the slides").textStyle(.bodyCompact).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch).controlSize(.mini)
                VStack(spacing: 4) {
                    r.slider("Brightness", \.backdrop.brightness, 0.2...1.4, reset: 1)
                    r.slider("Motion", \.backdrop.motion, reset: 0.3)
                    r.slider("Slide colour", \.stage.mood, reset: 0.5)
                }
                Text("Slide colour: how far the room takes on the colours of the slides in view, so it warms or cools as a slide comes forward.")
                    .textStyle(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            Hairline().padding(.horizontal, 16)
            InspectorSection("Atmosphere") {
                r.slider("Amount", \.settings.atmosphere, reset: 0.5)
                Text("How much the room answers the song: the backdrop lifts on the kick, the camera leans in on loud bars, the light flares on a drop.")
                    .textStyle(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            Hairline().padding(.horizontal, 16)
            InspectorSection("Finish") {
                r.choice("Surface", \.stage.surface, [(SurfaceKind.original, "Original"), (.print, "Print"), (.satin, "Satin"), (.gloss, "Gloss")])
                VStack(spacing: 4) {
                    r.slider("Bloom", \.stage.finish.bloom, 0...0.6, reset: 0.15)
                    r.slider("Grain", \.stage.finish.grain, 0...0.4, reset: 0.06)
                    r.slider("Vignette", \.stage.finish.vignette, 0...0.6, reset: 0.25)
                    r.slider("Shadows", \.stage.shadow, reset: 0.55)
                    r.slider("Motion blur", \.stage.shutter, 0...1, reset: 0.4)
                }
            }
        }
    }
}
