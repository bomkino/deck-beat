import AppKit
import AVFoundation
import BeatKit
import Observation
import QuartzCore
import StudioKit
import SwiftUI
import UniformTypeIdentifiers

/// Editor state for one window: the project, its slides and song, and the
/// worked-out choreography the stage plays.
@Observable
@MainActor
final class BeatSession: StageSource {
    @ObservationIgnored let document: BeatDocument
    @ObservationIgnored weak var undoManager: UndoManager?

    private(set) var project: BeatProject
    /// Increments whenever anything visible changes; the stage redraws on change.
    private(set) var version = 0
    let clock = PlaybackClock()

    var textures: [UUID: MediaTexture] = [:]
    var thumbnails: [UUID: CGImage] = [:]
    var importing = 0
    var selection: UUID?
    var showExport = false
    var message: String?
    private(set) var song: Song?
    private(set) var songLoading = false
    private(set) var preparingSamples = false

    @ObservationIgnored private var pending: BeatProject?
    @ObservationIgnored private var pendingName: String?
    @ObservationIgnored private let sound = SoundPreview()
    @ObservationIgnored private var lastSoundTime: Double?
    @ObservationIgnored private var planCache: [Int: Planned] = [:]
    @ObservationIgnored private var audioCache: (key: Int, track: AudioTrack)?
    @ObservationIgnored private lazy var placeholder = MediaLoader.placeholder()
    @ObservationIgnored private var clipDurations: [UUID: Double] = [:]
    @ObservationIgnored private var paletteCache: (key: Int, palette: Palette?)?

    /// A plan and what goes with it, for one canvas.
    struct Planned {
        var clip: ClipRange
        var layout: GridLayout
        var plan: BeatPlan
        var modulate: @Sendable (Double, inout StageLook, inout BackdropSettings) -> Void
    }

    static let slideTypes: [UTType] = [.image, .pdf, .movie, .mpeg4Movie, .quickTimeMovie]

    init(document: BeatDocument) {
        self.document = document
        project = document.project
        clock.duration = 30
    }

    /// Loads the song and the slides once the window is up, and fills an empty
    /// project with the sample deck so it plays straight away.
    func start() {
        if song == nil, !songLoading { loadSong() }
        if project.slides.isEmpty { addStarterSlides() } else { loadMedia() }
    }

    // MARK: Editing with undo

    func update(_ name: String, _ change: (inout BeatProject) -> Void) {
        if pending != nil { commit(pendingName ?? "Edit") }
        let before = project
        var after = project
        change(&after)
        guard after != before else { return }
        set(after)
        registerUndo(before, name)
    }

    /// Start of a continuous gesture, such as a slider drag.
    func begin(_ name: String? = nil) {
        if pending != nil, pendingName != name { commit(pendingName ?? "Edit") }
        if pending == nil {
            pending = project
            pendingName = name
        }
    }

    func live(_ change: (inout BeatProject) -> Void) {
        var p = project
        change(&p)
        if p != project { set(p) }
    }

    func commit(_ name: String) {
        guard let p = pending else { return }
        pending = nil
        pendingName = nil
        if p != project { registerUndo(p, name) }
    }

    private func set(_ p: BeatProject) {
        let songChanged = p.song != project.song
        project = p
        document.project = p
        version += 1
        if songChanged { loadSong() }
        let d = loopDuration
        if abs(clock.duration - d) > 1e-6 {
            clock.duration = d
            if clock.time > d { clock.time = wrap(clock.time, d) }
        }
    }

    private func registerUndo(_ old: BeatProject, _ name: String) {
        guard let um = undoManager else { return }
        let current = project
        um.registerUndo(withTarget: document) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.set(old)
                self.registerUndo(current, name)
                self.loadMedia()
            }
        }
        um.setActionName(name)
    }

    // MARK: Stage source

    func touch() { version += 1 }
    var fps: Int { project.fps }
    var format: CanvasFormat { project.format }
    var look: Look { Looks.look(project.look) }
    var exportName: String { "Deck Beat " + look.name }
    var soundTitle: String? { song?.title }

    var loopDuration: Double { loopDuration(for: project.format) }

    func loopDuration(for format: CanvasFormat) -> Double {
        planned(for: format)?.plan.length ?? 30
    }

    /// The clip as it stands, once the song is ready.
    var clip: ClipRange? {
        guard let song else { return nil }
        return project.clip.resolve(song.analysis, settings: project.settings, landOnDrop: project.landOnDrop)
    }

    var exportCaption: String? {
        guard let c = clip else { return nil }
        return "\(timecode(c.start))–\(timecode(c.start + c.length)) of the song, \(c.outro == .loop ? "looping" : "with its ending")."
    }

    /// The slides' usual shape.
    var slideAspect: Float {
        Composer.typicalAspect(project.slides.map { textures[$0.id]?.aspect ?? $0.aspect })
    }

    var starred: Set<Int> { Set(project.slides.indices.filter { project.slides[$0].featured }) }

    func planned(for format: CanvasFormat) -> Planned? {
        guard let song, !project.slides.isEmpty else { return nil }
        let aspect = Float(format.aspect)
        let slideAspect = self.slideAspect
        let clip = project.clip.resolve(song.analysis, settings: project.settings, landOnDrop: project.landOnDrop)
        var h = Hasher()
        h.combine(ObjectIdentifier(song))
        h.combine(project.settings)
        h.combine(clip)
        h.combine(aspect)
        h.combine(slideAspect)
        h.combine(project.slides.count)
        h.combine(starred)
        let key = h.finalize()
        if let hit = planCache[key] { return hit }
        let (layout, plan) = Composer.plan(song.analysis, settings: project.settings, clip: clip, aspect: aspect, slideAspect: slideAspect,
                                           slides: project.slides.count, starred: starred)
        let made = Planned(clip: clip, layout: layout, plan: plan,
                           modulate: Atmosphere.modulate(plan: plan, atmosphere: project.settings.atmosphere))
        if planCache.count > 24 { planCache.removeAll() }
        planCache[key] = made
        return made
    }

    func composition() -> Composition? { composition(for: project.format) }

    func composition(for format: CanvasFormat) -> Composition? { composition(of: project, format: format) }

    /// A composition of `p`, which may be the project with another look tried on.
    func composition(of p: BeatProject, format: CanvasFormat) -> Composition? {
        guard let song, !p.slides.isEmpty else { return nil }
        let planned: Planned
        if p.settings == project.settings, p.slides == project.slides, p.clip == project.clip, p.landOnDrop == project.landOnDrop,
           let mine = self.planned(for: format) {
            planned = mine
        } else {
            let clip = p.clip.resolve(song.analysis, settings: p.settings, landOnDrop: p.landOnDrop)
            let starred = Set(p.slides.indices.filter { p.slides[$0].featured })
            let (layout, plan) = Composer.plan(song.analysis, settings: p.settings, clip: clip, aspect: Float(format.aspect),
                                               slideAspect: slideAspect, slides: p.slides.count, starred: starred)
            planned = Planned(clip: clip, layout: layout, plan: plan, modulate: Atmosphere.modulate(plan: plan, atmosphere: p.settings.atmosphere))
        }
        let textures = p.slides.map { self.textures[$0.id]?.texture ?? placeholder.texture }
        let aspects = p.slides.map { self.textures[$0.id]?.aspect ?? $0.aspect }
        var videos: [Int: VideoClip] = [:]
        for (i, item) in p.slides.enumerated() where item.kind == .video {
            if let d = clipDurations[item.id], d > 0 { videos[i] = VideoClip(url: document.media.url(for: item.file), duration: d) }
        }
        return Composer.composition(plan: planned.plan, layout: planned.layout, settings: p.settings, stage: p.stage,
                                    backdrop: p.backdrop, textures: textures, aspects: aspects, focals: p.slides.map(\.focal),
                                    canvasAspect: Float(format.aspect), videos: videos, modulate: planned.modulate)
    }

    /// Downbeats in the clip, for the transport.
    var beats: [Double] {
        guard let p = planned(for: project.format)?.plan else { return [] }
        return p.downbeats.filter { $0 >= -0.01 && $0 <= p.length + 0.01 }
    }

    // MARK: Sound

    /// The clip's sound: short edge fades for a loop, a long fade-out for an ending.
    func clipAudio() -> AudioTrack? {
        guard let song, let c = planned(for: project.format)?.clip else { return nil }
        var h = Hasher()
        h.combine(ObjectIdentifier(song))
        h.combine(c)
        let key = h.finalize()
        if let cached = audioCache, cached.key == key { return cached.track }
        let loop = c.outro == .loop
        let track = song.slice(from: c.start, length: c.length, fadeIn: loop ? 0.03 : 0.012, fadeOut: loop ? 0.03 : min(1.5, c.length * 0.2))
        audioCache = (key, track)
        return track
    }

    func soundClock(playing: Bool, time: Double) -> Double? {
        guard playing, !StudioSnapshot.isRequested, let track = clipAudio(), let key = audioCache?.key else {
            if sound.isPlaying { sound.stop() }
            lastSoundTime = nil
            return nil
        }
        let loop = loopDuration
        // Restart when the sound changed or the playhead was moved by hand.
        let moved = lastSoundTime.map { abs(wrap(time - $0 + loop / 2, loop) - loop / 2) > 0.05 } ?? true
        if !sound.isPlaying || sound.signature != key || moved {
            sound.play(track, signature: key, loop: loop, from: time)
        }
        let t = sound.position() ?? time
        lastSoundTime = t
        return t
    }

    func exportAudio(duration: Double) -> AudioTrack? {
        clipAudio()?.repeated(toFrames: Int((duration * Double(AudioTrack.sampleRate)).rounded()))
    }

    // MARK: Transport

    func togglePlay() {
        clock.playing.toggle()
        touch()
    }

    func rewind() {
        clock.time = 0
        touch()
    }

    // MARK: Song

    static let songTypes: [UTType] = [.audio]

    private func loadSong() {
        let file = project.song
        songLoading = true
        let url = file.map { document.media.url(for: $0.file) }
        Task.detached(priority: .userInitiated) {
            var loaded: Song?
            var failure: String?
            if let url {
                do { loaded = try await Song.load(url) } catch { failure = error.localizedDescription }
            }
            let result = loaded ?? Song.demo()
            await MainActor.run {
                // A newer choice may have arrived while this one decoded.
                guard self.project.song == file else { return }
                self.song = result
                self.songLoading = false
                if let failure { self.message = "The song could not be read, so the demo groove is playing. \(failure)" }
                self.planCache.removeAll()
                self.audioCache = nil
                self.version += 1
                self.clock.duration = self.loopDuration
                if self.clock.time > self.clock.duration { self.clock.time = 0 }
            }
        }
    }

    /// Takes a song (or the sound of a movie) into the project.
    func importSong(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let stored = try? document.media.importFile(url) else {
            message = "That file could not be added as the song."
            return
        }
        let title = url.deletingPathExtension().lastPathComponent
        update("Choose Song") { p in
            p.song = SongFile(file: stored, title: title)
            p.clip.bestPart = true
        }
        clock.time = 0
    }

    func useDemoSong() {
        update("Use the Demo Groove") { $0.song = nil }
    }

    // MARK: Slides

    func importSlides(_ urls: [URL], at index: Int? = nil) {
        var added: [MediaItem] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let entries = MediaLoader.inspect(url)
            guard !entries.isEmpty, let stored = try? document.media.importFile(url) else { continue }
            let base = url.deletingPathExtension().lastPathComponent
            for e in entries {
                let name = entries.count > 1 ? "\(base) · \(e.page + 1)" : base
                added.append(MediaItem(name: name, file: stored, kind: e.kind, page: e.page, aspect: 16.0 / 9.0, focal: SIMD2(0.5, 0.45)))
            }
        }
        guard !added.isEmpty else {
            message = "Those files could not be added. Try images, PDFs or movies."
            return
        }
        // Real slides replace the untouched samples in the same step.
        let replaces = !project.slides.isEmpty && project.slides.allSatisfy(\.isSample)
        update(added.count == 1 ? "Add Slide" : "Add \(added.count) Slides") { p in
            if replaces { p.slides.removeAll() }
            let at = min(index ?? p.slides.count, p.slides.count)
            p.slides.insert(contentsOf: added, at: at)
        }
        if replaces || selection == nil { selection = added.first?.id }
        loadMedia()
    }

    /// Sorts dropped files: sound becomes the song, everything else a slide.
    func receive(_ urls: [URL]) {
        var slides: [URL] = []
        for url in urls {
            let type = UTType(filenameExtension: url.pathExtension.lowercased())
            if let type, type.conforms(to: .audio) { importSong(url) } else { slides.append(url) }
        }
        if !slides.isEmpty { importSlides(slides) }
    }

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        update(ids.count == 1 ? "Remove Slide" : "Remove Slides") { p in p.slides.removeAll { ids.contains($0.id) } }
        if let s = selection, ids.contains(s) { selection = project.slides.first?.id }
    }

    func move(from source: IndexSet, to destination: Int) {
        update("Reorder") { p in p.slides.move(fromOffsets: source, toOffset: destination) }
    }

    func toggleStar(_ id: UUID) {
        update("Star") { p in
            if let i = p.slides.firstIndex(where: { $0.id == id }) { p.slides[i].featured.toggle() }
        }
    }

    private func addStarterSlides() {
        guard project.slides.isEmpty, !preparingSamples else { return }
        preparingSamples = true
        let store = document.media
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var items: [MediaItem] = []
            for i in 0..<DemoDeck.count {
                let image = DemoDeck.slide(index: i)
                let rep = NSBitmapImageRep(cgImage: image)
                guard let data = rep.representation(using: .png, properties: [:]) else { continue }
                let file = MediaItem.samplePrefix + UUID().uuidString + ".png"
                try? store.write(data, as: file)
                items.append(MediaItem(name: DemoDeck.titles[i], file: file, kind: .image,
                                       aspect: Float(DemoDeck.width) / Float(DemoDeck.height), focal: SIMD2(0.5, 0.45)))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.preparingSamples = false
                guard self.project.slides.isEmpty else { return }
                self.live { $0.slides = items }
                // Steps recorded before the samples arrived hold an empty deck.
                self.undoManager?.removeAllActions(withTarget: self.document)
                self.loadMedia()
            }
        }
    }

    /// Loads textures and thumbnails for slides that have none yet.
    func loadMedia() {
        let side = MediaLoader.textureSide(forItems: project.slides.count)
        let missing = project.slides.filter { textures[$0.id] == nil }
        guard !missing.isEmpty else { return }
        importing += missing.count
        let store = document.media
        for item in missing {
            let url = store.url(for: item.file)
            let kind = item.kind, page = item.page, id = item.id
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let tex = try? MediaLoader.load(url: url, kind: kind, page: page, maxSide: side)
                let thumb = MediaLoader.cgImage(url: url, kind: kind, page: page, maxSide: 360)
                let duration: Double? = kind == .video ? AVURLAsset(url: url).duration.seconds : nil
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.importing = max(0, self.importing - 1)
                    if let duration, duration.isFinite { self.clipDurations[id] = duration }
                    if let tex {
                        self.textures[id] = tex
                        if let i = self.project.slides.firstIndex(where: { $0.id == id }), abs(self.project.slides[i].aspect - tex.aspect) > 0.001 {
                            // The true shape, recorded without an undo step.
                            var p = self.project
                            p.slides[i].aspect = tex.aspect
                            self.project = p
                            self.document.project = p
                        }
                    }
                    if let thumb { self.thumbnails[id] = thumb }
                    self.version += 1
                    self.clock.duration = self.loopDuration
                }
            }
        }
    }

    var isReady: Bool { song != nil && !preparingSamples && importing == 0 && !project.slides.isEmpty }

    /// The deck's own colours, once there are thumbnails to read.
    var deckPalette: Palette? {
        var h = Hasher()
        for item in project.slides { h.combine(item.id); h.combine(thumbnails[item.id] != nil) }
        let key = h.finalize()
        if let cached = paletteCache, cached.key == key { return cached.palette }
        let images = project.slides.compactMap { thumbnails[$0.id] }
        let palette = images.isEmpty ? nil : Palette.extract(from: images, id: "deck", name: "From your slides")
        paletteCache = (key, palette)
        return palette
    }

    // MARK: Looks and grid

    /// `p` wearing `look`, keeping its grid, slides, song and clip.
    func wearing(_ look: Look, on p: BeatProject) -> BeatProject {
        var q = p
        q.look = look.id
        q.settings = Looks.settings(look, over: p.settings)
        q.backdrop = look.backdrop(deckPalette)
        q.backdrop.seed = p.backdrop.seed
        if p.followDeck, let deck = deckPalette { q.backdrop.palette = deck }
        q.stage = look.stage
        return q
    }

    func choose(_ look: Look) {
        let next = wearing(look, on: project)
        update("Choose \(look.name)") { p in p = next }
        clock.time = 0
        clock.playing = true
    }

    func reroll() {
        update("New Variation") { p in
            p.settings.seed = p.settings.seed &+ 7919
            p.backdrop.seed = p.backdrop.seed &+ 131
        }
    }

    func setGrid(columns: Int, rows: Int, shape: CellShape? = nil) {
        update("Grid") { p in
            p.settings.grid.columns = min(max(columns, 1), 12)
            p.settings.grid.rows = min(max(rows, 1), 20)
            if let shape { p.settings.grid.shape = shape }
        }
    }

    func fitDeck() {
        let f = GridLayout.fit(count: project.slides.count, aspect: Float(project.format.aspect), slideAspect: slideAspect,
                               base: project.settings.grid)
        update("Fit the Grid") { p in
            p.settings.grid.columns = f.columns
            p.settings.grid.rows = f.rows
            p.settings.grid.shape = .auto
        }
    }

    /// Cells too small to read with nothing stepping forward.
    var hardToRead: Bool {
        guard project.settings.feature == .off, project.settings.mode != .readThrough,
              let layout = planned(for: project.format)?.layout else { return false }
        return layout.cells[0].size.x / layout.px < 240
    }

    func followDeck(_ on: Bool) {
        update("Backdrop Colours") { p in
            p.followDeck = on
            if on, let deck = deckPalette { p.backdrop.palette = deck } else if !on {
                p.backdrop.palette = Looks.look(p.look).backdrop(nil).palette
            }
        }
    }

    // MARK: Clip

    func setClip(_ length: ClipLength) {
        update("Clip Length") { p in
            p.clip.length = length
            p.clip.bestPart = true
        }
        clock.time = 0
    }

    func moveClip(to start: Double) {
        live { p in
            p.clip.start = max(0, start)
            p.clip.bestPart = false
        }
    }

    func bestPart() {
        update("Best Part") { $0.clip.bestPart = true }
        clock.time = 0
    }
}

func timecode(_ t: Double) -> String {
    let s = max(0, Int(t.rounded(.down)))
    return String(format: "%d:%02d", s / 60, s % 60)
}
