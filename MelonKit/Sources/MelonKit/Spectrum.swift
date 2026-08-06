import Accelerate
import Foundation

/// Magnitude spectrum of a real signal, produced by a Hann-windowed DFT.
public struct Spectrum: Sendable {

    /// Magnitudes for bins 0 ..< transformLength/2.
    public let magnitudes: [Float]

    /// Frequency spacing between adjacent bins, in Hz.
    public let binWidthHz: Float

    /// Returns nil when the input is too short to transform meaningfully (fewer than 16 samples).
    public init?(samples: [Float], sampleRate: Double) {
        guard samples.count >= AnalysisConstants.minimumSpectrumSamples, sampleRate > 0 else { return nil }

        // Zero-pad up to a power of two. Padding preserves every input sample, unlike truncating,
        // and finer bin spacing costs nothing here.
        let length = 1 << Int(ceil(log2(Double(samples.count))))
        let logLength = vDSP_Length(log2(Float(length)))

        var window = [Float](repeating: 0, count: length)
        vDSP_hann_window(&window, vDSP_Length(length), Int32(vDSP_HANN_DENORM))

        var padded = samples
        padded.append(contentsOf: [Float](repeating: 0, count: length - samples.count))

        var windowed = [Float](repeating: 0, count: length)
        vDSP_vmul(padded, 1, window, 1, &windowed, 1, vDSP_Length(length))

        guard let setup = vDSP_create_fftsetup(logLength, Int32(FFT_RADIX2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var splitComplex = DSPSplitComplex(
            realp: UnsafeMutablePointer<Float>.allocate(capacity: length / 2),
            imagp: UnsafeMutablePointer<Float>.allocate(capacity: length / 2)
        )
        defer {
            splitComplex.realp.deallocate()
            splitComplex.imagp.deallocate()
        }

        windowed.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: length / 2) { ptr in
                vDSP_ctoz(ptr, 2, &splitComplex, 1, vDSP_Length(length / 2))
            }
        }

        vDSP_fft_zrip(setup, &splitComplex, 1, logLength, Int32(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0, count: length / 2)
        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(length / 2))

        self.magnitudes = magnitudes
        self.binWidthHz = Float(sampleRate) / Float(length)
    }

    /// Centre frequency of a bin.
    public func frequency(ofBin bin: Int) -> Float {
        Float(bin) * binWidthHz
    }

    /// Bin indices covering a frequency span, clamped to the available bins.
    public func binRange(fromHz low: Float, toHz high: Float) -> Range<Int> {
        let first = max(1, Int((low / binWidthHz).rounded(.down)))
        let last = min(magnitudes.count - 1, Int((high / binWidthHz).rounded(.up)))
        guard first < last else { return 0..<0 }
        return first..<last
    }
}
