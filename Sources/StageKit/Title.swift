import CoreGraphics
import Foundation
import Metal
import RenderCore

/// A title ready to draw over a composition.
public struct TitleOverlay: @unchecked Sendable {
    /// Identity of the words, their setting and ink, for caching the drawing.
    public var key: Int
    public var timing: ReelTitle.Timing
    /// How far the stage dims behind the words, 0…1.
    public var scrim: Float
    /// Draws the words over a transparent frame of this pixel size, premultiplied.
    public var draw: @Sendable (Int, Int) -> CGImage?
    /// Words that land on the beat: one cue per group, in order. Empty when
    /// the words rise in together.
    public var cues: [WordCue] = []
    /// Where each group sits in a frame of this pixel size, for words that land on the beat.
    public var pieces: (@Sendable (Int, Int) -> [TitlePiece])?
    /// How words on the beat arrive: falling, popping or rising from behind their line.
    public var motion: ReelTitle.Motion = .land

    public init(key: Int, timing: ReelTitle.Timing, scrim: Float, draw: @escaping @Sendable (Int, Int) -> CGImage?) {
        self.key = key
        self.timing = timing
        self.scrim = scrim
        self.draw = draw
    }

    /// Whether its words land on the beat.
    public var onBeat: Bool { !cues.isEmpty && pieces != nil }

    /// Opacity, and how far below its place the title sits (a share of the
    /// frame height), at time `t`. An opening title rises in after the loop
    /// begins and clears a few seconds later; a closing one rises in a few
    /// seconds before the end and clears just before the loop turns. Either
    /// way the loop's first and last frames have no title, so it still closes.
    public func presence(at t: Double, loop: Double) -> (alpha: Float, drop: Float) {
        guard let w = window(loop: loop) else { return (1, 0) }
        let u = wrap(t, loop)
        if onBeat {
            // Each group brings itself in; the title still clears together.
            let outT = Float(max(0, min(1, (u - w.end) / w.fadeOut)))
            return (u < (cues.first.map { $0.land - $0.lead } ?? w.start) - 0.01 ? 0 : 1 - Ease.smoother(outT), 0)
        }
        let inT = Float(max(0, min(1, (u - w.start) / w.fadeIn)))
        let outT = Float(max(0, min(1, (u - w.end) / w.fadeOut)))
        let alpha = Ease.smoother(inT) * (1 - Ease.smoother(outT))
        let settle = 1 - inT
        return (alpha, 0.014 * settle * settle * settle)
    }

    /// How strongly the title holds the frame at time `t`, 0…1: what dims and
    /// defocuses the stage behind a title card. Words on the beat bring it in
    /// with the first group and take it away with the last.
    public func strength(at t: Double, loop: Double) -> Float {
        let whole = presence(at: t, loop: loop).alpha
        guard onBeat, let first = cues.first else { return whole }
        let u = wrap(t, loop)
        let ramp = 0.35
        let start = first.land - first.lead - ramp * 0.5
        let rise = Ease.smooth(Float((u - start) / ramp))
        let last = cues.map(\.leave).max() ?? .infinity
        let fall = last.isFinite ? 1 - Ease.smooth(Float((u - last) / (first.lead + ramp))) : 1
        return whole * rise * fall
    }

    /// When an opening or closing title starts to rise in and starts to clear,
    /// and how long each fade takes; nil for a title shown throughout.
    public func window(loop: Double) -> (start: Double, fadeIn: Double, end: Double, fadeOut: Double)? { timing.window(loop: loop) }

    /// A soft rush of air as the title rises in, for the sound mix.
    public func soundEvents(loop: Double) -> [SoundEvent] {
        guard let w = window(loop: loop) else { return [] }
        return [SoundEvent(time: w.start + w.fadeIn * 0.15, cue: .air, intensity: 0.4)]
    }
}

/// Draws a title over the finished frame: the dimming behind a title card,
/// then the words, in one premultiplied pass.
final class TitleCompositor {
    private let library: MTLLibrary
    private var cached: (key: Int, width: Int, height: Int, texture: MTLTexture, pieces: [TitlePiece])?
    private let lock = NSLock()

    init() throws {
        library = try GPU.shared.library(named: "title", source: ShaderPrelude.source + Self.source)
    }

    func encode(_ cb: MTLCommandBuffer, _ overlay: TitleOverlay, at t: Double, loop: Double, output: MTLTexture) throws {
        let (alpha, drop) = overlay.presence(at: t, loop: loop)
        guard alpha > 0.002, let drawn = drawn(overlay, output.width, output.height) else { return }
        let gpu = GPU.shared
        // Words on the beat: each piece follows its own cue.
        var rects: [SIMD4<Float>] = []
        var motion: [SIMD4<Float>] = []
        var words: [SIMD4<Float>] = []
        if overlay.onBeat {
            let u = wrap(t, loop)
            for piece in drawn.pieces.prefix(Self.maxPieces) where overlay.cues.indices.contains(piece.cue) {
                let cue = overlay.cues[piece.cue]
                rects.append(piece.rect)
                words.append(piece.words)
                // (opacity, drop, scale, matte): the matte hides everything below it, 2 for none.
                switch overlay.motion {
                case .land:
                    let m = cue.presence(at: u)
                    motion.append(SIMD4(m.alpha * alpha, m.drop, 1, 2))
                case .pop:
                    let m = cue.pop(at: u)
                    motion.append(SIMD4(m.alpha * alpha, 0, m.scale, 2))
                case .reveal:
                    let hidden = cue.reveal(at: u)
                    let line = piece.words.w - piece.words.y
                    // Hidden behind the foot of its own line while it moves; free of the matte once home,
                    // so its shadow falls where it likes.
                    let matte: Float = hidden > 0.001 ? piece.words.w + line * 0.06 : 2
                    motion.append(SIMD4(hidden < 0.999 ? alpha : 0, hidden * line * 1.12, 1, matte))
                }
            }
            guard motion.contains(where: { $0.x > 0.002 }) || overlay.scrim * overlay.strength(at: t, loop: loop) > 0.002 else { return }
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "title"
        let fragment = overlay.onBeat ? "title_pieces_fragment" : "title_fragment"
        enc.setRenderPipelineState(try gpu.renderPipeline(.init(library: "title", vertex: "fs_vertex", fragment: fragment,
                                                                color: output.pixelFormat, blend: .over), library: library))
        var p = SIMD4<Float>(alpha, drop, overlay.scrim * overlay.strength(at: t, loop: loop), Float(rects.count))
        enc.setFragmentBytes(&p, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        if overlay.onBeat {
            // Metal wants a buffer bound even when no piece shows.
            if rects.isEmpty {
                rects = [.zero]
                motion = [.zero]
                words = [.zero]
            }
            enc.setFragmentBytes(rects, length: MemoryLayout<SIMD4<Float>>.stride * rects.count, index: 1)
            enc.setFragmentBytes(motion, length: MemoryLayout<SIMD4<Float>>.stride * motion.count, index: 2)
            enc.setFragmentBytes(words, length: MemoryLayout<SIMD4<Float>>.stride * words.count, index: 3)
        }
        enc.setFragmentTexture(drawn.texture, index: 0)
        enc.setFragmentSamplerState(gpu.sampler(.linearClamp), index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Copies a premultiplied frame into `output` as straight colour, for
    /// ProRes 4444: the words are laid over the frame first, premultiplied,
    /// so their fades and edges composite like everything else.
    func straighten(_ cb: MTLCommandBuffer, from input: MTLTexture, to output: MTLTexture) throws {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "straight alpha"
        enc.setRenderPipelineState(try GPU.shared.renderPipeline(.init(library: "title", vertex: "fs_vertex", fragment: "unpremultiply_fragment",
                                                                       color: output.pixelFormat, blend: .opaque), library: library))
        enc.setFragmentTexture(input, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// The most pieces a title is cut into: a dozen groups over a few lines, with room to spare.
    static let maxPieces = 48

    /// The drawn words at this size, and where each group of them sits, kept
    /// until the words or the size change.
    private func drawn(_ overlay: TitleOverlay, _ width: Int, _ height: Int) -> (texture: MTLTexture, pieces: [TitlePiece])? {
        lock.lock()
        defer { lock.unlock() }
        if let c = cached, c.key == overlay.key, c.width == width, c.height == height { return (c.texture, c.pieces) }
        guard let image = overlay.draw(width, height) else { return nil }
        let tex = GPU.shared.makeTexture(width: width, height: height, format: .rgba8Unorm, usage: [.shaderRead], storage: .shared)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)
        let pieces = overlay.pieces?(width, height) ?? []
        cached = (overlay.key, width, height, tex, pieces)
        return (tex, pieces)
    }

    static let source = #"""
// Premultiplied in, straight out.
fragment float4 unpremultiply_fragment(FSOut in [[stage_in]], texture2d<float> src [[texture(0)]]) {
    float4 c = src.read(uint2(in.position.xy));
    return c.a > 1e-5 ? float4(clamp(c.rgb / c.a, 0.0, 1.0), c.a) : float4(0.0);
}

// The words, dropped `p.y` of the frame below their place, faded by `p.x`,
// over a black dimming of `p.z`.
fragment float4 title_fragment(FSOut in [[stage_in]], texture2d<float> words [[texture(0)]], sampler s [[sampler(0)]],
                               constant float4 &p [[buffer(0)]]) {
    float2 uv = in.uv - float2(0.0, p.y);
    float4 w = uv.y >= 0.0 ? words.sample(s, uv) * p.x : float4(0.0);
    return float4(w.rgb, w.a + p.z * (1.0 - w.a));
}

// Words on the beat: the frame is tiled into pieces, one group of words in
// each; piece i shows where its rectangle lies, dropped motion[i].y, scaled
// motion[i].z about the middle of its words (bounds[i]) and faded by
// motion[i].x, with nothing showing below the matte motion[i].w, over the
// same dimming. p.w is the number of pieces.
fragment float4 title_pieces_fragment(FSOut in [[stage_in]], texture2d<float> words [[texture(0)]], sampler s [[sampler(0)]],
                                      constant float4 &p [[buffer(0)]], constant float4 *rects [[buffer(1)]],
                                      constant float4 *motion [[buffer(2)]], constant float4 *bounds [[buffer(3)]]) {
    float4 w = float4(0.0);
    int n = int(p.w);
    for (int i = 0; i < n; i++) {
        float a = motion[i].x;
        if (a <= 0.0 || in.uv.y > motion[i].w) continue;
        float4 b = bounds[i];
        float2 mid = (b.xy + b.zw) * 0.5;
        float k = max(motion[i].z, 0.05);
        float2 uv = mid + (in.uv - mid) / k - float2(0.0, motion[i].y);
        float4 r = rects[i];
        if (uv.x < r.x || uv.x >= r.z || uv.y < r.y || uv.y >= r.w) continue;
        float4 c = words.sample(s, uv) * a;
        w = c + w * (1.0 - c.a);
    }
    return float4(w.rgb, w.a + p.z * (1.0 - w.a));
}
"""#
}
