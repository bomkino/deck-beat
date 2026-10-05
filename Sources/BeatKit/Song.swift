import AVFoundation
import Foundation
import RenderCore
import UniformTypeIdentifiers

/// A song ready to play and to light the grid: its sound at 48 kHz stereo,
/// and what Deck Beat heard in it.
public final class Song: @unchecked Sendable {
    public let title: String
    public let audio: AudioTrack
    public let analysis: SongAnalysis
    /// A coarse outline of the sound for the transport: peak level per slot, 0…1.
    public let outline: [Float]

    public init(title: String, audio: AudioTrack, analysis: SongAnalysis) {
        self.title = title
        self.audio = audio
        self.analysis = analysis
        outline = Self.outline(audio, slots: 2_000)
    }

    public var duration: Double { audio.duration }

    /// The built-in groove, synthesised and analysed.
    public static func demo() -> Song {
        let audio = AudioTrack(samples: DemoGroove.render())
        return Song(title: DemoGroove.title, audio: audio, analysis: SongAnalyzer.analyze(mono: audio.mono(), sampleRate: Double(AudioTrack.sampleRate)))
    }

    /// Decodes any file macOS can play (a song, or the sound of a movie) and
    /// listens to it.
    public static func load(_ url: URL) async throws -> Song {
        let (audio, title) = try await SongDecoder.decode(url)
        let analysis = SongAnalyzer.analyze(mono: audio.mono(), sampleRate: Double(AudioTrack.sampleRate))
        return Song(title: title, audio: audio, analysis: analysis)
    }

    /// The part of the song from `start` lasting `length`, with short fades so
    /// it never clicks, and an optional longer fade-out.
    public func slice(from start: Double, length: Double, fadeIn: Double = 0.012, fadeOut: Double = 0.012) -> AudioTrack {
        let rate = Double(AudioTrack.sampleRate)
        let total = max(1, Int((length * rate).rounded()))
        let first = Int((start * rate).rounded())
        var out = [Float](repeating: 0, count: total * 2)
        let src = audio.samples
        let frames = audio.frames
        let inFrames = max(1, Int(fadeIn * rate)), outFrames = max(1, Int(fadeOut * rate))
        out.withUnsafeMutableBufferPointer { dst in
            src.withUnsafeBufferPointer { s in
                for i in 0..<total {
                    let j = first + i
                    guard j >= 0, j < frames else { continue }
                    var g: Float = 1
                    if i < inFrames { g = Float(i) / Float(inFrames) }
                    let left = total - 1 - i
                    // An equal-power curve keeps a long fade-out from sagging in the middle.
                    if left < outFrames { g *= sinf(Float(left) / Float(outFrames) * .pi / 2) }
                    dst[2 * i] = s[2 * j] * g
                    dst[2 * i + 1] = s[2 * j + 1] * g
                }
            }
        }
        return AudioTrack(samples: out)
    }

    static func outline(_ audio: AudioTrack, slots: Int) -> [Float] {
        let frames = audio.frames
        guard frames > 0 else { return [] }
        let per = max(1, frames / slots)
        var out: [Float] = []
        out.reserveCapacity(frames / per + 1)
        audio.samples.withUnsafeBufferPointer { s in
            var i = 0
            while i < frames {
                let end = min(frames, i + per)
                var peak: Float = 0
                var k = i
                while k < end {
                    peak = max(peak, abs(s[2 * k]), abs(s[2 * k + 1]))
                    k += 4
                }
                out.append(peak)
                i = end
            }
        }
        let top = max(out.max() ?? 1, 1e-4)
        return out.map { min(1, ($0 / top).squareRoot()) }
    }
}

public extension AudioTrack {
    /// Left and right averaged.
    func mono() -> [Float] {
        let n = frames
        var out = [Float](repeating: 0, count: n)
        samples.withUnsafeBufferPointer { s in
            for i in 0..<n { out[i] = 0.5 * (s[2 * i] + s[2 * i + 1]) }
        }
        return out
    }
}

public enum SongError: LocalizedError {
    case noSound
    case unreadable(String)
    case tooLong(Double)

    public var errorDescription: String? {
        switch self {
        case .noSound: return "That file has no sound in it."
        case let .unreadable(why): return "That file could not be read: \(why)"
        case let .tooLong(minutes): return String(format: "That is %.0f minutes long. Deck Beat takes songs up to 20 minutes.", minutes)
        }
    }
}

public enum SongDecoder {
    /// Files Deck Beat accepts as a song.
    public static let types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .movie, .mpeg4Movie, .quickTimeMovie]

    public static let longest: Double = 20 * 60

    /// Decodes the first sound track of `url` to 48 kHz interleaved stereo.
    public static func decode(_ url: URL) async throws -> (AudioTrack, String) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw SongError.noSound }
        let duration = try await asset.load(.duration).seconds
        if duration.isFinite, duration > longest { throw SongError.tooLong(duration / 60) }
        let title = await Self.title(of: asset) ?? url.deletingPathExtension().lastPathComponent
        let samples = try read(asset: asset, track: track)
        guard samples.count >= 2 else { throw SongError.noSound }
        return (AudioTrack(samples: samples), title)
    }

    private static func read(asset: AVURLAsset, track: AVAssetTrack) throws -> [Float] {
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw SongError.unreadable(error.localizedDescription) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioTrack.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw SongError.unreadable("its sound cannot be decoded") }
        reader.add(output)
        guard reader.startReading() else { throw SongError.unreadable(reader.error?.localizedDescription ?? "decoding did not start") }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: count))
            let status = samples.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                           destination: raw.baseAddress!.advanced(by: start * MemoryLayout<Float>.size))
            }
            if status != kCMBlockBufferNoErr { samples.removeLast(count) }
        }
        if reader.status == .failed { throw SongError.unreadable(reader.error?.localizedDescription ?? "decoding failed") }
        if samples.count % 2 == 1 { samples.removeLast() }
        return samples
    }

    private static func title(of asset: AVURLAsset) async -> String? {
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        var title: String?, artist: String?
        for item in items {
            if item.commonKey == .commonKeyTitle { title = try? await item.load(.stringValue) }
            if item.commonKey == .commonKeyArtist { artist = try? await item.load(.stringValue) }
        }
        guard let title, !title.isEmpty else { return nil }
        if let artist, !artist.isEmpty { return "\(title) · \(artist)" }
        return title
    }
}
