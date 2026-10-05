import AppKit
import BeatKit
import StudioKit
import SwiftUI
import UniformTypeIdentifiers

struct BeatRoot: View {
    @State private var session: BeatSession
    @Environment(\.undoManager) private var undoManager
    @AppStorage("appearance") private var appearance = AppearanceChoice.dark.rawValue

    init(document: BeatDocument) {
        _session = State(initialValue: BeatSession(document: document))
    }

    var body: some View {
        BeatWindow(session: session)
            .onAppear {
                session.undoManager = undoManager
                session.start()
            }
            .onChange(of: undoManager) { _, um in session.undoManager = um }
            .preferredColorScheme(AppearanceChoice(rawValue: appearance)?.colorScheme)
            .focusedSceneValue(\.beatSession, session)
            .modifier(BeatSnapshotHost(session: session))
    }
}

struct BeatWindow: View {
    @Bindable var session: BeatSession
    @State private var showInspector = true
    @Environment(\.snapshotStage) private var snapshotStage

    private var subtitle: String {
        let f = session.project.format
        var parts = ["\(f.width) × \(f.height)"]
        if let song = session.song {
            parts.append(song.title)
            if song.analysis.confidence >= 0.4 { parts.append("\(Int(song.analysis.tempo.rounded())) bpm") }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationSplitView {
            SlideRail(session: session)
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            VStack(spacing: 0) {
                BeatStage(session: session, still: snapshotStage)
                Hairline()
                SongTransport(session: session, clock: session.clock)
            }
            .background(Theme.surround)
            .inspector(isPresented: $showInspector) {
                BeatInspector(session: session)
                    .inspectorColumnWidth(min: 300, ideal: 332, max: 420)
            }
        }
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                FormatPicker(current: session.project.format) { f in session.update("Canvas") { $0.format = f } }
                Button { BeatPanels.addSlides(session) } label: { Label("Add Slides", systemImage: "rectangle.stack.badge.plus") }
                    .help("Add slides: images, PDFs or clips")
                Button { BeatPanels.chooseSong(session) } label: { Label("Choose Song", systemImage: "music.note") }
                    .help("Choose the song; you can also drop one anywhere")
                Button { session.reroll() } label: { Label("New Variation", systemImage: "dice") }
                    .help("Shuffle who lights when, keeping the look")
                Button { session.showExport = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
                        Text("Export")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!session.isReady)
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
            }
        }
        .sheet(isPresented: $session.showExport) { ExportSheet(source: session) }
        .alert("Deck Beat", isPresented: Binding(get: { session.message != nil }, set: { if !$0 { session.message = nil } })) {
            Button("OK") { session.message = nil }
        } message: { Text(session.message ?? "") }
        .dropDestination(for: URL.self) { urls, _ in
            session.receive(urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
            return !urls.isEmpty
        }
        .frame(minWidth: 1040, minHeight: 680)
    }
}

// MARK: - Stage

struct BeatStage: View {
    let session: BeatSession
    let still: CGImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            StageNote(session: session)
                .frame(height: 40)
            GeometryReader { geo in
                let pad: CGFloat = 28
                let avail = CGSize(width: max(40, geo.size.width - pad * 2), height: max(40, geo.size.height - pad))
                let aspect = CGFloat(session.project.format.aspect)
                let fitted = avail.width / avail.height > aspect
                    ? CGSize(width: avail.height * aspect, height: avail.height)
                    : CGSize(width: avail.width, height: avail.width / aspect)
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let k = min(1, 2400 / max(fitted.width, fitted.height) / scale)
                let px = CGSize(width: (fitted.width * scale * k).rounded(), height: (fitted.height * scale * k).rounded())
                ZStack {
                    Theme.surround
                    Group {
                        if let still {
                            Image(decorative: still, scale: 1).resizable()
                        } else if session.song != nil, !session.project.slides.isEmpty {
                            StagePreview(source: session, pixelSize: px)
                        } else {
                            ZStack {
                                Color.black
                                VStack(spacing: 10) {
                                    ProgressView().controlSize(.small)
                                    Text(session.songLoading ? "Listening to the song…" : "Setting out the slides…")
                                        .textStyle(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.18), radius: scheme == .dark ? 28 : 14, y: 4)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

/// One quiet line above the stage: samples waiting to be replaced, or slides too small to read.
struct StageNote: View {
    let session: BeatSession

    var body: some View {
        HStack(spacing: 8) {
            if session.hardToRead {
                Image(systemName: "eye").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text("Slides will be hard to read at this size.").textStyle(.label)
                Button("Turn on Feature") { session.update("Feature") { $0.settings.feature = .fourBars } }
                    .buttonStyle(QuietButtonStyle())
            } else if !session.project.slides.isEmpty, session.project.slides.allSatisfy(\.isSample) {
                Text("Sample slides").textStyle(.label)
                Text("Drop your deck anywhere to replace them, and a song to play them to.").textStyle(.caption).foregroundStyle(.secondary)
            } else if session.project.song == nil, session.song != nil {
                Text("Demo groove").textStyle(.label)
                Text("Drop a song anywhere and the grid will play to it.").textStyle(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Slide rail

struct SlideRail: View {
    @Bindable var session: BeatSession

    var body: some View {
        VStack(spacing: 0) {
            SongCard(session: session)
                .padding(12)
            Hairline()
            List(selection: $session.selection) {
                Section {
                    ForEach(Array(session.project.slides.enumerated()), id: \.element.id) { i, item in
                        SlideRow(index: i, item: item, thumb: session.thumbnails[item.id], isCover: i == coverIndex) {
                            session.toggleStar(item.id)
                        }
                        .tag(item.id)
                        .contextMenu {
                            Button(item.featured ? "Unstar" : "Star") { session.toggleStar(item.id) }
                            Divider()
                            Button("Remove", role: .destructive) { session.remove([item.id]) }
                        }
                    }
                    .onMove { session.move(from: $0, to: $1) }
                } header: {
                    HStack {
                        Text("Slides")
                        Spacer()
                        Text("\(session.project.slides.count)").monospacedDigit()
                    }
                }
            }
            .listStyle(.sidebar)
            .onDeleteCommand {
                if let s = session.selection { session.remove([s]) }
            }
            Hairline()
            HStack(spacing: 8) {
                Button { BeatPanels.addSlides(session) } label: { Label("Add Slides…", systemImage: "plus") }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Theme.chrome)
    }

    /// The slide that opens and closes the video: the first starred, or the first.
    private var coverIndex: Int {
        session.project.slides.firstIndex(where: \.featured) ?? 0
    }
}

struct SlideRow: View {
    let index: Int
    let item: MediaItem
    let thumb: CGImage?
    let isCover: Bool
    let star: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)").textStyle(.data).foregroundStyle(.tertiary).frame(width: 20, alignment: .trailing)
            ZStack {
                Theme.well
                if let thumb { Image(decorative: thumb, scale: 2).resizable().aspectRatio(contentMode: .fill) }
                if item.kind == .video {
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(4).background(Circle().fill(.black.opacity(0.5)))
                }
            }
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).textStyle(.bodyCompact).lineLimit(1).truncationMode(.middle)
                if isCover { Text("Cover").textStyle(.badge).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Button(action: star) {
                Image(systemName: item.featured ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.featured ? Color.yellow : Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help(item.featured ? "Starred: steps forward twice as often" : "Star: step forward twice as often")
        }
        .padding(.vertical, 2)
    }
}

struct SongCard: View {
    let session: BeatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well)
                    Image(systemName: session.songLoading ? "waveform" : "music.note")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                        .symbolEffect(.variableColor, isActive: session.songLoading)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.song?.title ?? (session.songLoading ? "Listening…" : "No song")).textStyle(.label).lineLimit(1)
                    Text(detail).textStyle(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Button(session.project.song == nil ? "Choose Song…" : "Replace…") { BeatPanels.chooseSong(session) }
                    .buttonStyle(QuietButtonStyle())
                if session.project.song != nil {
                    Button("Demo Groove") { session.useDemoSong() }.buttonStyle(QuietButtonStyle())
                }
            }
            .padding(.leading, -8)
        }
    }

    private var detail: String {
        guard let song = session.song else { return "Drop a song anywhere" }
        let a = song.analysis
        var parts: [String] = []
        if a.confidence >= 0.4 { parts.append("\(Int(a.tempo.rounded())) bpm") } else { parts.append("free time") }
        parts.append(timecode(song.duration))
        if let d = a.drops.first { parts.append("drop at \(timecode(d))") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Snapshot support

/// Headless stills for checks and docs:
/// `DeckBeat --still out.png [--look id] [--format reel] [--mode pulse] [--clip 15] [--time 3]`,
/// or `--snapshot window.png` for the whole window.
struct BeatSnapshotHost: ViewModifier {
    let session: BeatSession
    @State private var still: CGImage?
    @State private var started = false

    func body(content: Content) -> some View {
        content
            .environment(\.snapshotStage, still)
            .onAppear {
                guard StudioSnapshot.isRequested, !started else { return }
                started = true
                session.clock.playing = false
                waitUntilReady(0)
            }
    }

    @MainActor
    private func waitUntilReady(_ tries: Int) {
        guard session.isReady || tries > 300 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { waitUntilReady(tries + 1) } }
            return
        }
        if let id = StudioSnapshot.arg("--look") { session.choose(Looks.look(id)) }
        if let fmt = StudioSnapshot.arg("--format"), let f = CanvasFormat.presets.first(where: { $0.id == fmt }) {
            session.update("Canvas") { $0.format = f }
        }
        if let m = StudioSnapshot.arg("--mode"), let mode = BeatMode(rawValue: m) { session.update("Mode") { $0.settings.mode = mode } }
        if let c = StudioSnapshot.arg("--clip").flatMap(Int.init).flatMap(ClipLength.init(rawValue:)) { session.setClip(c) }
        session.clock.playing = false
        session.clock.time = Double(StudioSnapshot.arg("--time") ?? "") ?? 3
        let f = session.project.format
        if let comp = session.composition() {
            still = try? Exporter().still(comp, at: session.clock.time, width: f.width, height: f.height, samples: 4)
        }
        if let path = StudioSnapshot.arg("--still") {
            guard let still else {
                print("still: nothing to render")
                exit(1)
            }
            try? ImageOutput.writePNG(still, to: URL(fileURLWithPath: path))
            print("still \(path) \(still.width)x\(still.height)")
            exit(0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(StudioSnapshot.arg("--settle") ?? "") ?? 3)) {
            MainActor.assumeIsolated { StudioSnapshot.captureWindow() }
        }
    }
}
