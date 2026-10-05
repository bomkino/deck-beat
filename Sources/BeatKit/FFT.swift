import Foundation

/// A real-input FFT of one power-of-two size, written out in plain Swift so the
/// analysis runs the same everywhere, including in the checks.
///
/// The real signal is packed into a complex one of half the length, transformed
/// with an iterative radix-2 FFT, then split back into the real spectrum.
public final class RealFFT {
    public let size: Int
    private let half: Int
    private let levels: Int
    private let bitReverse: [Int]
    /// Twiddles for the half-size complex transform: e^(−2πij / half).
    private let twiddleRe: [Float]
    private let twiddleIm: [Float]
    /// Twiddles for the split: e^(−2πik / size).
    private let splitRe: [Float]
    private let splitIm: [Float]
    private var re: [Float]
    private var im: [Float]

    public init(size: Int) {
        precondition(size >= 4 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        half = size / 2
        var l = 0
        while (1 << l) < half { l += 1 }
        levels = l
        bitReverse = (0..<(size / 2)).map { i in
            var r = 0, x = i
            for _ in 0..<l { r = (r << 1) | (x & 1); x >>= 1 }
            return r
        }
        twiddleRe = (0..<(size / 4)).map { Float(cos(-2 * Double.pi * Double($0) / Double(size / 2))) }
        twiddleIm = (0..<(size / 4)).map { Float(sin(-2 * Double.pi * Double($0) / Double(size / 2))) }
        splitRe = (0...(size / 2)).map { Float(cos(-2 * Double.pi * Double($0) / Double(size))) }
        splitIm = (0...(size / 2)).map { Float(sin(-2 * Double.pi * Double($0) / Double(size))) }
        re = [Float](repeating: 0, count: size / 2)
        im = [Float](repeating: 0, count: size / 2)
    }

    /// Magnitudes of bins 0…size/2 of `input` (exactly `size` samples, already windowed).
    public func magnitudes(_ input: UnsafeBufferPointer<Float>, into out: UnsafeMutableBufferPointer<Float>) {
        precondition(input.count >= size && out.count >= half + 1)
        let m = half
        // Pack even samples as real parts and odd ones as imaginary, in bit-reversed order.
        for i in 0..<m {
            let j = bitReverse[i]
            re[j] = input[2 * i]
            im[j] = input[2 * i + 1]
        }
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { q in
                var span = 1
                var step = m / 2
                while span < m {
                    var start = 0
                    while start < m {
                        var k = 0
                        for j in start..<(start + span) {
                            let wr = twiddleRe[k], wi = twiddleIm[k]
                            let a = j + span
                            let tr = r[a] * wr - q[a] * wi
                            let ti = r[a] * wi + q[a] * wr
                            r[a] = r[j] - tr
                            q[a] = q[j] - ti
                            r[j] += tr
                            q[j] += ti
                            k += step
                        }
                        start += span * 2
                    }
                    span *= 2
                    step /= 2
                }
                // Split the half-length transform into the spectrum of the real input.
                for k in 0...m {
                    let a = r[k % m], b = q[k % m]
                    let c = r[(m - k) % m], d = q[(m - k) % m]
                    let cr = splitRe[k], ci = splitIm[k]
                    // X[k] = E + W^k O with E = (Z[k] + Z*[m−k]) / 2 and O = (Z[k] − Z*[m−k]) / 2i.
                    let er = (a + c) * 0.5, ei = (b - d) * 0.5
                    let or = (b + d) * 0.5, oi = -(a - c) * 0.5
                    let xr = er + cr * or - ci * oi
                    let xi = ei + cr * oi + ci * or
                    out[k] = (xr * xr + xi * xi).squareRoot()
                }
            }
        }
    }

    /// A Hann window of this transform's size.
    public var hann: [Float] {
        (0..<size).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size))) }
    }
}
