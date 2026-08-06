import Accelerate
import Foundation

/// Turns one tap window into features. Pure, stateless, and platform-free, so it is fully unit-testable.
public enum FeatureExtractor {

    /// Returns nil when the window is too short or contains no energy in the analysis band.
    public static func extract(from samples: [Float], sampleRate: Double) -> ChannelFeatures? {
        guard let spectrum = Spectrum(samples: samples, sampleRate: sampleRate) else { return nil }
        guard let peak = peakFrequency(in: spectrum) else { return nil }

        return ChannelFeatures(
            peakFrequencyHz: peak,
            spectralCentroidHz: 0,
            decayRatePerSecond: 0,
            lowHighEnergyRatio: 0
        )
    }

    /// Loudest bin within the analysis band, refined by parabolic interpolation across its neighbours
    /// so that resolution is not limited to the bin spacing.
    static func peakFrequency(in spectrum: Spectrum) -> Float? {
        let range = spectrum.binRange(
            fromHz: AnalysisConstants.bandLowHz,
            toHz: AnalysisConstants.bandHighHz
        )
        guard !range.isEmpty else { return nil }

        var peakBin = range.lowerBound
        for bin in range where spectrum.magnitudes[bin] > spectrum.magnitudes[peakBin] {
            peakBin = bin
        }
        guard spectrum.magnitudes[peakBin] > 0 else { return nil }

        guard peakBin > 0, peakBin < spectrum.magnitudes.count - 1 else {
            return spectrum.frequency(ofBin: peakBin)
        }

        let left = spectrum.magnitudes[peakBin - 1]
        let centre = spectrum.magnitudes[peakBin]
        let right = spectrum.magnitudes[peakBin + 1]
        let denominator = left - 2 * centre + right
        let offset = denominator == 0 ? 0 : 0.5 * (left - right) / denominator

        return (Float(peakBin) + offset) * spectrum.binWidthHz
    }
}
