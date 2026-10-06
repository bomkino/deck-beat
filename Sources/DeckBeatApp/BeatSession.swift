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
    /// Each slide's own colours, for a room that takes the colour of the slide in view.
    @ObservationIgnored private var slidePalettes: [UUID: Palette] = [:]
    /// The plan and composition for the stage, kept until anything visible changes.
    @ObservationIgnored private var plannedMemo: [Float: (version: Int, planned: Planned)] = [:]
    @ObservationIgnored private var compositionMemo: [Float: (version: Int, composition: Composition)] = [:]
    @ObservationIgnored private var fixedAnalysis: (song: ObjectIdentifier, fix: BeatFix, analysis: SongAnalysis)?
    /// Slides being loaded now, so an import or undo meanwhile never queues them twice.
    @ObservationIgnored private var inFlight: Set<UUID> = []
    /// Slides whose files could not be read; they are not tried again.
    @ObservationIgnored private var failedMedia: Set<UUID> = []
    /// Names of slides that could not be read in the current batch.
    @ObservationIgnored private var unreadable: [String] = []
    /// Slides loading at a size since given up for a smaller one; they load again when they finish.
    @ObservationIgnored private var staleLoads: Set<UUID> = []
    /// The largest texture side loaded, so a deck grown past it loads smaller.
    @ObservationIgnored private var loadedSide: Int?
    /// A few at a time, in rail order: each load holds a full-size raster, and
    /// a 100-page PDF loaded all at once can take gigabytes.
    @ObservationIgnored private lazy var loadQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 3
        q.qualityOfService = .userInitiated
        return q
    }()

    /// A plan and what goes with it, for one canvas.
    struct Planned: Sendable {
        var clip: ClipRange
        var layout: BeatKit.GridLayout
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
    var soundTitle: String? { song?.title }

    /// Where this window's document is saved, or nil while it is untitled.
    @ObservationIgnored var documentURL: URL?

    /// The saved document's name and the look, so exports of different
    /// projects never share a name.
    var exportName: String {
        if let url = documentURL { return url.deletingPathExtension().lastPathComponent + " " + look.name }
        return "Deck Beat " + look.name
    }

    // MARK: Background

    var transparentBackground: Bool { project.transparent }

    /// Backdrop or transparent, for this project and, as a starting point, the next new one.
    func setTransparentBackground(_ on: Bool) {
        guard on != transparentBackground else { return }
        update(on ? "Transparent Background" : "Backdrop") { $0.transparent = on }
        UserDefaults.standard.set(on, forKey: BeatProject.transparentKey)
    }

    /// The stage holds still under the export sheet, so the export has the GPU to itself.
    var stageSuspended: Bool { showExport }

    /// What an export still waits for, or nil once the song and every slide are in.
    var exportWaitNote: String? {
        if isReady { return nil }
        if song == nil { return "Listening to the song…" }
        if project.slides.isEmpty { return preparingSamples ? "Setting out the slides…" : "Add slides to export a video." }
        let waiting = max(importing, 1)
        return "Waiting for \(waiting) slide\(waiting == 1 ? "" : "s") to load…"
    }

    var loopDuration: Double { loopDuration(for: project.format) }

    func loopDuration(for format: CanvasFormat) -> Double {
        planned(for: format)?.plan.length ?? 30
    }

    /// The song as heard, with the project's corrections to its beat.
    var analysis: SongAnalysis? {
        guard let song else { return nil }
        let fix = project.beat
        if fix.isNone { return song.analysis }
        if let f = fixedAnalysis, f.song == ObjectIdentifier(song), f.fix == fix { return f.analysis }
        let a = song.analysis.fixed(fix)
        fixedAnalysis = (ObjectIdentifier(song), fix, a)
        return a
    }

    /// The clip as it stands, once the song is ready.
    var clip: ClipRange? { planned(for: project.format)?.clip }

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
        let aspect = Float(format.aspect)
        // Asked for several times a frame (stage, sound, transport): worked out once per change.
        if let m = plannedMemo[aspect], m.version == version { return m.planned }
        guard let analysis, !project.slides.isEmpty else { return nil }
        let slideAspect = self.slideAspect
        let clip = project.clip.resolve(analysis, settings: project.settings, landOnDrop: project.landOnDrop)
        var h = Hasher()
        // The song's cache is cleared when the song changes; its corrections are part of the key.
        h.combine(project.beat)
        h.combine(project.settings)
        h.combine(clip)
        h.combine(aspect)
        h.combine(slideAspect)
        h.combine(project.slides.count)
        h.combine(starred)
        let clear = Self.clearance(for: project, format: format)
        h.combine(clear)
        let key = h.finalize()
        let made: Planned
        if let hit = planCache[key] {
            made = hit
        } else {
            made = Self.plan(analysis, settings: project.settings, clip: clip, aspect: aspect, slideAspect: slideAspect,
                             slides: project.slides.count, starred: starred, clear: clear)
            if planCache.count > 24 { planCache.removeAll() }
            planCache[key] = made
        }
        if plannedMemo.count > 8 { plannedMemo.removeAll() }
        plannedMemo[aspect] = (version, made)
        return made
    }

    nonisolated static func plan(_ analysis: SongAnalysis, settings: BeatSettings, clip: ClipRange, aspect: Float, slideAspect: Float,
                                 slides: Int, starred: Set<Int>, clear: Clearance) -> Planned {
        let (layout, plan) = Composer.plan(analysis, settings: settings, clip: clip, aspect: aspect, slideAspect: slideAspect,
                                           slides: slides, starred: starred, clear: clear)
        return Planned(clip: clip, layout: layout, plan: plan, modulate: Atmosphere.modulate(plan: plan, atmosphere: settings.atmosphere))
    }

    /// What it takes to plan `p` on `format`, ready to be worked out off the main thread.
    func planJob(for p: BeatProject, format: CanvasFormat) -> (@Sendable () -> Planned)? {
        guard let analysis, !p.slides.isEmpty else { return nil }
        let settings = p.settings, clip = p.clip, landOnDrop = p.landOnDrop, aspect = Float(format.aspect), slideAspect = slideAspect
        let count = p.slides.count, starred = Set(p.slides.indices.filter { p.slides[$0].featured })
        let clear = Self.clearance(for: p, format: format)
        return {
            let range = clip.resolve(analysis, settings: settings, landOnDrop: landOnDrop)
            return BeatSession.plan(analysis, settings: settings, clip: range, aspect: aspect, slideAspect: slideAspect, slides: count,
                                    starred: starred, clear: clear)
        }
    }

    /// The room a caption shown throughout takes at the top or foot of the frame, kept clear of the grid.
    nonisolated static func clearance(for p: BeatProject, format: CanvasFormat) -> Clearance {
        guard let title = p.title, title.timing == .throughout else { return .none }
        let reach = TitleArt.reach(title, width: format.width, height: format.height)
        return Clearance(top: Float(reach.top), bottom: Float(reach.bottom))
    }

    func composition() -> Composition? { composition(for: project.format) }

    func composition(for format: CanvasFormat) -> Composition? {
        let aspect = Float(format.aspect)
        if let m = compositionMemo[aspect], m.version == version { return m.composition }
        guard let made = composition(of: project, format: format) else { return nil }
        if compositionMemo.count > 8 { compositionMemo.removeAll() }
        compositionMemo[aspect] = (version, made)
        return made
    }

    /// A composition of `p`, which may be the project with another look tried
    /// on, using `planned` when it was worked out already.
    func composition(of p: BeatProject, format: CanvasFormat, planned given: Planned? = nil) -> Composition? {
        guard analysis != nil, !p.slides.isEmpty else { return nil }
        let planned: Planned
        if let given {
            planned = given
        } else if p.settings == project.settings, p.slides == project.slides, p.clip == project.clip, p.landOnDrop == project.landOnDrop,
                  let mine = self.planned(for: format) {
            planned = mine
        } else if let job = planJob(for: p, format: format) {
            planned = job()
        } else {
            return nil
        }
        let textures = p.slides.map { self.textures[$0.id]?.texture ?? placeholder.texture }
        let aspects = p.slides.map { self.textures[$0.id]?.aspect ?? $0.aspect }
        var videos: [Int: VideoClip] = [:]
        for (i, item) in p.slides.enumerated() where item.kind == .video {
            if let d = clipDurations[item.id], d > 0 { videos[i] = VideoClip(url: document.media.url(for: item.file), duration: d) }
        }
        var settings = p.settings
        // Over someone else's footage a mirror floor would hang below the grid in mid-air.
        if p.transparent { settings.grid.wall.reflection = 0 }
        var comp = Composer.composition(plan: planned.plan, layout: planned.layout, settings: settings, stage: p.stage,
                                        backdrop: p.backdrop, textures: textures, aspects: aspects, focals: p.slides.map(\.focal),
                                        canvasAspect: Float(format.aspect), videos: videos, modulate: planned.modulate)
        comp.overlay = titleOverlay(p, plan: planned.plan)
        comp.itemPalettes = p.slides.map { slidePalettes[$0.id] }
        comp.transparent = p.transparent
        return comp
    }

    // MARK: Title

    /// Light words over a dark backdrop, dark over a light one, unless chosen.
    func titleIsLight(_ p: BeatProject) -> Bool {
        guard let title = p.title else { return true }
        switch title.ink {
        case .light: return true
        case .dark: return false
        // Over footage nobody here can see, light ink with its shadow is the safe choice.
        case .auto: return title.placement == .centre || p.transparent
            || p.backdrop.palette.meanLightness * min(p.backdrop.brightness, 1.2) < 0.62
        }
    }

    /// The title over a composition of `p`, its words landing on the beats of `plan` when asked.
    func titleOverlay(_ p: BeatProject, plan: BeatPlan) -> TitleOverlay? {
        guard let title = p.title else { return nil }
        var overlay = TitleArt.overlay(title, light: titleIsLight(p), cues: WordTiming.cues(title, plan: plan))
        // A title card's dimming is a black veil over the footage below; half of it still sets the words apart.
        if p.transparent { overlay?.scrim *= 0.5 }
        return overlay
    }

    func setTitle(_ name: String, _ change: (inout ReelTitle) -> Void) {
        update(name) { p in
            var t = p.title ?? ReelTitle(placement: .centre, timing: .opening)
            change(&t)
            p.title = t
            Self.refit(&p)
        }
    }

    // MARK: Beat corrections

    func setBeat(_ name: String, _ change: (inout BeatFix) -> Void) {
        update(name) { p in change(&p.beat) }
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
            await MainActor.run { [failure] in
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
            p.beat = .none
        }
        clock.time = 0
    }

    func useDemoSong() {
        update("Use the Demo Groove") { p in
            p.song = nil
            p.beat = .none
        }
    }

    // MARK: Slides

    func importSlides(_ urls: [URL], at index: Int? = nil) {
        var added: [MediaItem] = []
        var decks: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if SlideFiles.isPresentation(url) { decks.append(url.lastPathComponent); continue }
            let entries = MediaLoader.inspect(url)
            guard !entries.isEmpty, let stored = try? document.media.importFile(url) else { continue }
            let base = url.deletingPathExtension().lastPathComponent
            for e in entries {
                let name = entries.count > 1 ? "\(base) · \(e.page + 1)" : base
                // The true shape now, so the grid can fit the deck in the same step.
                let aspect = SlideFiles.aspect(of: url, kind: e.kind, page: e.page) ?? 16.0 / 9.0
                added.append(MediaItem(name: name, file: stored, kind: e.kind, page: e.page, aspect: aspect, focal: BeatScene.defaultFocal))
            }
        }
        if !decks.isEmpty {
            message = SlideFiles.presentationAdvice(decks)
        }
        guard !added.isEmpty else {
            if decks.isEmpty { message = "Those files could not be added. Try images, PDFs or movies." }
            return
        }
        // Real slides replace the untouched samples in the same step.
        let replaces = !project.slides.isEmpty && project.slides.allSatisfy(\.isSample)
        update(added.count == 1 ? "Add Slide" : "Add \(added.count) Slides") { p in
            if replaces { p.slides.removeAll() }
            let at = min(index ?? p.slides.count, p.slides.count)
            p.slides.insert(contentsOf: added, at: at)
            Self.refit(&p)
        }
        if replaces || selection == nil { selection = added.first?.id }
        loadMedia()
    }

    /// Fits the grid to the deck while it follows the deck, on the canvas and
    /// around the caption it has now.
    static func refit(_ p: inout BeatProject) {
        guard p.gridFollowsDeck, !p.slides.isEmpty else { return }
        p.settings.grid = p.settings.grid.fitted(count: p.slides.count, aspect: Float(p.format.aspect),
                                                  slideAspect: Composer.typicalAspect(p.slides.map(\.aspect)),
                                                  clear: clearance(for: p, format: p.format))
    }

    func setFormat(_ format: CanvasFormat) {
        update("Canvas") { p in
            p.format = format
            Self.refit(&p)
        }
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
        update(ids.count == 1 ? "Remove Slide" : "Remove Slides") { p in
            p.slides.removeAll { ids.contains($0.id) }
            Self.refit(&p)
        }
        if let s = selection, ids.contains(s) { selection = project.slides.first?.id }
        // Lets go of the removed slides' textures; an undo loads them again.
        loadMedia()
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
                                       aspect: Float(DemoDeck.width) / Float(DemoDeck.height), focal: BeatScene.defaultFocal))
            }
            DispatchQueue.main.async { [items] in
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

    /// Loads textures and thumbnails for slides that have none yet, three at
    /// a time, and lets go of slides no longer in the project. When the deck
    /// has grown so far that its textures should shrink, loads them all again smaller.
    func loadMedia() {
        let ids = Set(project.slides.map(\.id))
        textures = textures.filter { ids.contains($0.key) }
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        slidePalettes = slidePalettes.filter { ids.contains($0.key) }
        clipDurations = clipDurations.filter { ids.contains($0.key) }
        failedMedia.formIntersection(ids)
        let side = MediaLoader.textureSide(forItems: project.slides.count)
        if let loaded = loadedSide, Double(side) < Double(loaded) * 0.8 {
            staleLoads = inFlight
            load(project.slides.filter { !inFlight.contains($0.id) && !failedMedia.contains($0.id) })
            loadedSide = side
            return
        }
        let missing = project.slides.filter { textures[$0.id] == nil && !inFlight.contains($0.id) && !failedMedia.contains($0.id) }
        load(missing)
    }

    private func load(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        if importing == 0 { unreadable = [] }
        importing += items.count
        inFlight.formUnion(items.map(\.id))
        let side = MediaLoader.textureSide(forItems: project.slides.count)
        loadedSide = items.count >= project.slides.count ? side : max(loadedSide ?? side, side)
        let store = document.media
        for item in items {
            let url = store.url(for: item.file)
            let kind = item.kind, page = item.page, id = item.id, name = item.name
            if kind == .video, clipDurations[id] == nil {
                // How long the clip runs, for a slide that plays it through.
                Task { [weak self] in
                    guard let d = try? await AVURLAsset(url: url).load(.duration).seconds, d.isFinite, let self else { return }
                    self.clipDurations[id] = d
                    self.version += 1
                    self.clock.duration = self.loopDuration
                }
            }
            loadQueue.addOperation { [weak self] in
                // One raster serves both: the texture, and the rail's thumbnail scaled from it.
                let (tex, thumb) = MediaLoader.loadWithThumbnail(url: url, kind: kind, page: page, maxSide: side, thumbnailSide: 360)
                let palette = thumb.flatMap { Palette.extract(from: [$0], name: "") }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.importing = max(0, self.importing - 1)
                    self.inFlight.remove(id)
                    let present = self.project.slides.contains(where: { $0.id == id })
                    if tex == nil, present {
                        self.failedMedia.insert(id)
                        self.unreadable.append(name)
                    }
                    if self.importing == 0, !self.unreadable.isEmpty {
                        let names = ListFormatter.localizedString(byJoining: self.unreadable)
                        let one = self.unreadable.count == 1
                        self.message = "\(names) could not be read, so \(one ? "it shows" : "they show") as a grey slide. Try exporting the file again, or replace it."
                        self.unreadable = []
                    }
                    // A slide removed while it loaded is not kept.
                    if present, let tex {
                        self.textures[id] = tex
                        if let i = self.project.slides.firstIndex(where: { $0.id == id }), abs(self.project.slides[i].aspect - tex.aspect) > 0.001 {
                            // The true shape, recorded without an undo step.
                            var p = self.project
                            p.slides[i].aspect = tex.aspect
                            Self.refit(&p)
                            self.project = p
                            self.document.project = p
                        }
                    }
                    if present, let thumb { self.thumbnails[id] = thumb }
                    if present, let palette { self.slidePalettes[id] = palette }
                    self.version += 1
                    self.clock.duration = self.loopDuration
                    // Loaded at a size since given up for a smaller one: load again.
                    if self.staleLoads.remove(id) != nil, tex != nil, let item = self.project.slides.first(where: { $0.id == id }) {
                        self.load([item])
                    }
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
            // Set by hand: it stays put as slides come and go.
            p.gridFollowsDeck = false
        }
    }

    func setShape(_ shape: CellShape) {
        update("Cell Shape") { p in
            p.settings.grid.shape = shape
            p.gridFollowsDeck = false
        }
    }

    /// Fits the grid to the deck, and keeps it fitted as slides come and go.
    func fitDeck() {
        update("Fit the Grid") { p in
            p.gridFollowsDeck = true
            Self.refit(&p)
        }
    }

    /// A grid size of about `count` cells for this deck's slide shape, with the shape that suits it.
    func gridPreset(about count: Int) -> GridSettings {
        project.settings.grid.fitted(count: count, aspect: Float(project.format.aspect), slideAspect: slideAspect)
    }

    func usePreset(_ g: GridSettings) {
        update("Grid") { p in
            p.settings.grid.columns = g.columns
            p.settings.grid.rows = g.rows
            p.settings.grid.shape = g.shape
            p.gridFollowsDeck = false
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
