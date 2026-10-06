import BeatKit
import StudioKit
import SwiftUI

/// Words over the video: a title card that opens or closes it, or a caption
/// that stays, which the grid makes room for.
struct TitlePage: View {
    let session: BeatSession
    @State private var pause: Task<Void, Never>?
    @FocusState private var field: Field?

    enum Field { case text, kicker }

    var body: some View {
        let title = session.project.title ?? Self.blank
        VStack(spacing: 0) {
            InspectorSection("Title", accessory: {
                if session.project.title != nil {
                    Button {
                        field = nil
                        session.update("Remove Title") { p in
                            p.title = nil
                            BeatSession.refit(&p)
                        }
                    } label: { Text("Remove").textStyle(.caption) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }) {
                input("Title", \.text, .text)
                input("Line above, such as a date or a client", \.kicker, .kicker)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set as").textStyle(.bodyCompact).foregroundStyle(.secondary)
                    ChoiceRow(ReelTitle.Placement.allCases.map { ($0, $0.title) }, selection: choice(\.placement, "Title Placement"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shows").textStyle(.bodyCompact).foregroundStyle(.secondary)
                    ChoiceRow([(ReelTitle.Timing.opening, "Opening"), (.throughout, "Throughout"), (.closing, "Closing")],
                              selection: choice(\.timing, "Title Timing"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type").textStyle(.bodyCompact).foregroundStyle(.secondary)
                    // Each face named in itself.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)],
                              spacing: 4) {
                        ForEach(ReelTitle.Face.allCases, id: \.self) { face in
                            let on = title.face == face
                            Button { choice(\.face, "Typeface").wrappedValue = face } label: {
                                Text(face.title).font(Font(face.titleFont(12)))
                                    .foregroundStyle(on ? Color.primary : Color.secondary).lineLimit(1).minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity).frame(height: 28)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.segmentOn : Theme.well.opacity(0.7)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ink").textStyle(.bodyCompact).foregroundStyle(.secondary)
                    ChoiceRow(ReelTitle.Ink.allCases.map { ($0, $0.title) }, selection: choice(\.ink, "Title Ink"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Words").textStyle(.bodyCompact).foregroundStyle(.secondary)
                    ChoiceRow([("together", "Together")] + ReelTitle.Motion.allCases.map { ($0.rawValue, $0.title) },
                              selection: Binding(get: { title.beat ? title.motion.rawValue : "together" }, set: { v in
                                  session.setTitle("Words on the Beat") { t in
                                      t.beat = v != "together"
                                      if let m = ReelTitle.Motion(rawValue: v) { t.motion = m }
                                  }
                                  revealIfHidden()
                              }))
                        .help("Together rises in as one. Land, Pop and Reveal bring the line above in first, then the title a few words at a time, each on a beat")
                }
                Text(note(title)).textStyle(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { session.commit("Title") }
    }

    /// A new title: a title card as the video opens.
    static let blank = ReelTitle(placement: .centre, timing: .opening)

    private func input(_ placeholder: String, _ key: WritableKeyPath<ReelTitle, String>, _ which: Field) -> some View {
        TextField(placeholder, text: Binding(
            get: { session.project.title?[keyPath: key] ?? "" },
            set: { v in
                // One undo step per pause in typing.
                session.begin("Title")
                session.live { p in
                    var t = p.title ?? Self.blank
                    t[keyPath: key] = v
                    p.title = t
                    BeatSession.refit(&p)
                }
                pause?.cancel()
                pause = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    if !Task.isCancelled { session.commit("Title") }
                }
                revealIfHidden()
            }))
            .textFieldStyle(.plain)
            .textStyle(.input)
            .focused($field, equals: which)
            .onSubmit { field = nil }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.well.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(field == which ? Theme.accent : Theme.hairline, lineWidth: field == which ? 1.5 : 1))
    }

    private func choice<T: Hashable>(_ key: WritableKeyPath<ReelTitle, T>, _ name: String) -> Binding<T> {
        Binding(
            get: { (session.project.title ?? Self.blank)[keyPath: key] },
            set: { v in
                session.setTitle(name) { $0[keyPath: key] = v }
                revealIfHidden()
            })
    }

    /// An opening or closing title is gone for most of the loop; while paused,
    /// bring the playhead to where it shows, so the words being set are in view.
    private func revealIfHidden() {
        guard let title = session.project.title, title.timing != .throughout, !title.isEmpty, !session.clock.playing else { return }
        let loop = session.loopDuration
        let probe = TitleOverlay(key: 0, timing: title.timing, scrim: 0) { _, _ in nil }
        guard probe.presence(at: session.clock.time, loop: loop).alpha < 0.6 else { return }
        let times = stride(from: 0.0, to: loop, by: loop / 200).filter { probe.presence(at: $0, loop: loop).alpha > 0.99 }
        if let first = times.first, let last = times.last {
            session.clock.time = (first + last) / 2
            session.touch()
        }
    }

    private func note(_ title: ReelTitle) -> String {
        var parts = [title.placement == .corner
            ? "Set small in a corner, clear of each platform’s buttons."
            : "Set large and centred over a dimmed stage."]
        switch title.timing {
        case .opening: parts.append("It rises in as the video begins and clears after a few seconds.")
        case .closing: parts.append("It rises in a few seconds before the end, like an end card, and clears as the loop turns.")
        case .throughout:
            if title.placement == .corner { parts.append("The grid moves over to make room for it.") }
        }
        if title.beat {
            let how: String
            switch title.motion {
            case .land: how = "fall onto the beat"
            case .pop: how = "pop in on the beat"
            case .reveal: how = "rise from behind their line on the beat"
            }
            parts.append(title.timing == .throughout
                ? "Its words \(how) once the grid is in, and a loop lifts them off again before it turns."
                : "Its words \(how), a few at a time.")
        }
        let words = title.text.split(whereSeparator: { $0.isWhitespace }).count
        let most = TitleArt.maxWords(title.placement)
        if words > most { parts.append("Titles read best in \(most) words or fewer.") }
        return parts.joined(separator: " ")
    }
}
