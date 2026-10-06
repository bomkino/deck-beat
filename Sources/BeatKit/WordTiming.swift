import Foundation
import StageKit

/// When a title's words land on the beat in a planned clip: one group per
/// beat, on half beats when the beats run out, and never so late that the
/// title can't be read before it clears.
public enum WordTiming {
    /// The most time a whole title takes to land when it can't fit on the beat.
    static let squeeze = 0.8

    /// One cue per group of `title`'s words; none unless the title asks to land on the beat.
    public static func cues(_ title: ReelTitle, plan: BeatPlan) -> [WordCue] {
        let n = title.beatGroups
        let loop = plan.length
        guard title.beat, n > 0, loop > 1.5 else { return [] }
        let period = max(plan.period, 0.2)
        // The fall onto the beat: quick, but never longer than half a beat.
        let lead = min(0.2, period * 0.45)
        let beats = plan.beats.filter { $0 > lead && $0 < loop }
        var halves = beats
        for (a, b) in zip(beats, beats.dropFirst()) where b - a < period * 1.5 { halves.append((a + b) / 2) }
        halves.sort()
        let grids = [beats, halves]

        /// The first `n` slots from `a` up to `b`, or `n` even steps if there are too few.
        func lands(from a: Double, to b: Double) -> [Double] {
            for grid in grids {
                let slots = grid.filter { $0 >= a - 1e-6 && $0 <= b + 1e-6 }
                if slots.count >= n { return Array(slots.prefix(n)) }
            }
            let span = min(max(b - a, 0), squeeze)
            return (0..<n).map { a + span * Double($0) / Double(max(n - 1, 1)) }
        }

        if let w = title.timing.window(loop: loop) {
            // An opening or closing title: inside its window, with time left to read it.
            let read = min(1.2, (w.end - w.start) * 0.4)
            return lands(from: w.start + lead, to: max(w.start + lead, w.end - read)).map { WordCue(land: $0, lead: lead) }
        }

        // Throughout: the words land once the grid has, and stay.
        let begin = max(plan.intro.end, lead + 0.05)
        guard begin < loop - 1 else { return [] }
        guard plan.outro.kind == .loop else {
            return lands(from: begin, to: loop - 1).map { WordCue(land: $0, lead: lead) }
        }
        // A loop closes on its first frame, which has no words: they lift off
        // in reverse on the last beats, the first to land the last to go.
        let gone = loop - lead - 0.04
        let hold = max(1.5, period * 4)
        let landing = lands(from: begin, to: gone)
        for grid in grids {
            let slots = grid.filter { $0 <= gone + 1e-6 }
            guard slots.count >= n, let last = landing.last else { continue }
            let leaving = Array(slots.suffix(n))
            if leaving[0] >= last + hold {
                return (0..<n).map { WordCue(land: landing[$0], leave: leaving[n - 1 - $0], lead: lead) }
            }
        }
        // A short loop: land and leave in quick steps around a hold in the middle.
        let room = gone - begin
        guard room > 1.5 else { return [] }
        let span = min(squeeze, room * 0.25)
        return (0..<n).map { i in
            let k = Double(i) / Double(max(n - 1, 1))
            return WordCue(land: begin + span * k, leave: gone - span * k, lead: lead)
        }
    }
}
