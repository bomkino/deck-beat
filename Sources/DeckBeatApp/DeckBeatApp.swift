import AppKit
import BeatKit
import StudioKit
import SwiftUI
import UniformTypeIdentifiers
import Updates

@main
struct DeckBeatApp: App {
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var delegate
    /// Updates from the GitHub releases; off for headless stills, snapshots and exports.
    @StateObject private var updates = AppUpdates(start: !StudioSnapshot.isRequested)

    init() {
        if StudioSnapshot.isRequested {
            // Headless runs report each step as it happens, even into a pipe.
            setvbuf(stdout, nil, _IOLBF, 0)
            // Their words are flags and values, never documents: without this, a
            // value after a bare flag (`--beat-words --title "Words"`) is opened
            // as a file, and the error it raises waits for a click that never comes.
            UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
        }
        UserDefaults.standard.register(defaults: [
            "appearance": AppearanceChoice.dark.rawValue,
            // Open on a new window, ready to go, rather than on the Open panel.
            "NSShowAppCentricOpenPanelInsteadOfUntitledFile": false,
        ])
        DispatchQueue.global(qos: .utility).async {
            if let r = try? StageRenderer() { r.warmUp() }
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: { BeatDocument() }) { file in
            BeatRoot(document: file.document)
                // Revert hands over a new document object; the window follows it.
                .id(ObjectIdentifier(file.document))
        }
        .commands {
            CheckForUpdatesCommand(updates: updates)
            CommandGroup(after: .toolbar) {
                AppearanceMenu()
            }
            BeatCommands()
        }
        .defaultSize(width: 1440, height: 900)
    }
}

struct AppearanceMenu: View {
    @AppStorage("appearance") private var appearance = AppearanceChoice.dark.rawValue
    var body: some View {
        Picker("Appearance", selection: $appearance) {
            ForEach(AppearanceChoice.allCases) { c in Text(c.title).tag(c.rawValue) }
        }
    }
}

// MARK: - Project

/// The song a project plays: a file in the package, or the demo groove when nil.
struct SongFile: Codable, Hashable {
    var file: String
    var title: String
}

/// Everything saved in a Deck Beat project.
struct BeatProject: Codable, Hashable {
    static let currentVersion = 2

    var version = BeatProject.currentVersion
    var slides: [MediaItem] = []
    var song: SongFile?
    var look = Looks.defaultID
    var settings = BeatSettings()
    var backdrop: BackdropSettings
    var stage: StageLook
    var format: CanvasFormat = .reel
    var fps = 30
    var clip = Clip()
    /// The cover lands on a drop that comes early in the clip.
    var landOnDrop = true
    /// The backdrop takes its colours from the slides.
    var followDeck = false
    /// The grid refits as slides come and go, until it is set by hand.
    var gridFollowsDeck = false
    /// Corrections to the song's beat, when it was heard wrong.
    var beat = BeatFix.none
    /// Words over the video: a caption or a title card.
    var title: ReelTitle?

    init(backdrop: BackdropSettings, stage: StageLook) {
        self.backdrop = backdrop
        self.stage = stage
    }

    static func fresh() -> BeatProject {
        let look = Looks.look(Looks.defaultID)
        var p = BeatProject(backdrop: look.backdrop(nil), stage: look.stage)
        p.settings = Looks.settings(look, over: BeatSettings())
        p.gridFollowsDeck = true
        return p
    }

    /// Reads any version: whatever the file leaves out, or this version
    /// cannot read, takes its default rather than failing the project.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let look = Looks.look((try? c.decodeIfPresent(String.self, forKey: .look)) ?? Looks.defaultID)
        self.init(backdrop: look.backdrop(nil), stage: look.stage)
        self.look = look.id
        settings = Looks.settings(look, over: BeatSettings())
        c.update(&version, .version)
        c.update(&slides, .slides)
        c.update(&song, .song)
        c.update(&settings, .settings)
        c.update(&backdrop, .backdrop)
        c.update(&stage, .stage)
        c.update(&format, .format)
        c.update(&fps, .fps)
        c.update(&clip, .clip)
        c.update(&landOnDrop, .landOnDrop)
        c.update(&followDeck, .followDeck)
        c.update(&gridFollowsDeck, .gridFollowsDeck)
        c.update(&beat, .beat)
        c.update(&title, .title)
    }
}

/// A Deck Beat project: `project.json` and a `Media` folder holding the slides and the song.
final class BeatDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = BeatProject
    static let type = UTType(exportedAs: "dog.pitch.deckbeat.project", conformingTo: .package)
    static var readableContentTypes: [UTType] { [type] }

    @Published var project: BeatProject
    let media = MediaStore()

    init() { project = .fresh() }

    required init(configuration: ReadConfiguration) throws {
        guard let wrappers = configuration.file.fileWrappers,
              let json = wrappers[ProjectPackage.projectFile]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        project = try JSONDecoder().decode(BeatProject.self, from: json)
        if let folder = wrappers[ProjectPackage.mediaFolder]?.fileWrappers {
            for (name, wrapper) in folder {
                if let data = wrapper.regularFileContents { try? media.write(data, as: name) }
            }
        }
    }

    func snapshot(contentType: UTType) throws -> BeatProject { project }

    func fileWrapper(snapshot: BeatProject, configuration: WriteConfiguration) throws -> FileWrapper {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(snapshot)
        var needed = Set(snapshot.slides.map(\.file))
        if let song = snapshot.song { needed.insert(song.file) }
        let saved = configuration.existingFile?.fileWrappers?[ProjectPackage.mediaFolder]?.fileWrappers
        var files: [String: FileWrapper] = [:]
        for file in needed {
            // A stored name never changes its contents, so the package's own copy is always good.
            if let existing = saved?[file] {
                files[file] = existing
            } else if media.contains(file), let w = try? FileWrapper(url: media.url(for: file), options: []) {
                w.preferredFilename = file
                files[file] = w
            } else {
                throw CocoaError(.fileWriteUnknown, userInfo: [
                    NSLocalizedDescriptionKey: "A slide or the song is missing, so the project was not saved.",
                    NSLocalizedRecoverySuggestionErrorKey: "Remove the grey slide, or reopen the project, then save again.",
                ])
            }
        }
        let folder = FileWrapper(directoryWithFileWrappers: files)
        folder.preferredFilename = ProjectPackage.mediaFolder
        let json = FileWrapper(regularFileWithContents: data)
        json.preferredFilename = ProjectPackage.projectFile
        return FileWrapper(directoryWithFileWrappers: [ProjectPackage.projectFile: json, ProjectPackage.mediaFolder: folder])
    }
}

// MARK: - Menus

struct BeatSessionKey: FocusedValueKey {
    typealias Value = BeatSession
}

extension FocusedValues {
    var beatSession: BeatSession? {
        get { self[BeatSessionKey.self] }
        set { self[BeatSessionKey.self] = newValue }
    }
}

struct BeatCommands: Commands {
    @FocusedValue(\.beatSession) private var session

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Add Slides…") { if let session { BeatPanels.addSlides(session) } }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Choose Song…") { if let session { BeatPanels.chooseSong(session) } }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(session == nil)
            Divider()
            Button("Export…") { session?.showExport = true }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(session == nil)
        }
        CommandMenu("Beat") {
            Button("Play or Pause") { session?.togglePlay() }
                .disabled(session == nil)
            Button("Back to the Start") { session?.rewind() }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(session == nil)
            Divider()
            Button("New Variation") { session?.reroll() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Fit the Grid to My Deck") { session?.fitDeck() }
                .disabled(session == nil)
        }
    }
}

/// Open panels for slides and songs.
@MainActor
enum BeatPanels {
    static func addSlides(_ session: BeatSession) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        // Presentations can be chosen too, to be told how to bring them in.
        panel.allowedContentTypes = BeatSession.slideTypes + SlideFiles.presentationExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose slides: images, PDFs (each page becomes a slide) or clips."
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated { session.importSlides(urls) }
        }
    }

    static func chooseSong(_ session: BeatSession) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = SongDecoder.types
        panel.message = "Choose a song, or a video whose sound you want."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { session.importSong(url) }
        }
    }
}
