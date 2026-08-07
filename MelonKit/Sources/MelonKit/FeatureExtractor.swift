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
            spectralCentroidHz: spectralCentroid(in: spectrum),
            decayRatePerSecond: decayRate(of: samples, sampleRate: sampleRate),
            lowHighEnergyRatio: lowHighEnergyRatio(in: spectrum)
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

    /// Magnitude-weighted mean frequency across the analysis band.
    static func spectralCentroid(in spectrum: Spectrum) -> Float {
        let range = spectrum.binRange(
            fromHz: AnalysisConstants.bandLowHz,
            toHz: AnalysisConstants.bandHighHz
        )
        guard !range.isEmpty else { return 0 }

        var weighted: Float = 0
        var total: Float = 0
        for bin in range {
            let magnitude = spectrum.magnitudes[bin]
            weighted += spectrum.frequency(ofBin: bin) * magnitude
            total += magnitude
        }
        return total > 0 ? weighted / total : 0
    }

    /// Energy below the sub-band split over energy above it.
    static func lowHighEnergyRatio(in spectrum: Spectrum) -> Float {
        func energy(_ range: Range<Int>) -> Float {
            range.reduce(Float(0)) { $0 + spectrum.magnitudes[$1] * spectrum.magnitudes[$1] }
        }

        let low = energy(spectrum.binRange(
            fromHz: AnalysisConstants.bandLowHz,
            toHz: AnalysisConstants.subBandSplitHz
        ))
        let high = energy(spectrum.binRange(
            fromHz: AnalysisConstants.subBandSplitHz,
            toHz: AnalysisConstants.bandHighHz
        ))

        // A window with no high-band energy at all has a mathematically infinite ratio; report
        // that directly rather than borrowing the scorer's normalisation range as a stand-in.
        // This extractor has no business knowing what range `PhysicsScorer` treats as "maximally
        // ripe" — that range is retuned independently of this file, and using it here as a
        // sentinel would let a scorer retune silently change what a degenerate window measures.
        // `PhysicsScorer.normalise` already clamps any value at or above its reference range's
        // upper bound to 1.0, so `.infinity` reaches the same scored outcome the old sentinel
        // did, without the extractor depending on the scorer's constant to get there.
        guard high > 0 else { return .infinity }
        return low / high
    }

    /// Fits a straight line to the log of frame RMS and returns its negated slope, so that
    /// a faster-fading signal yields a larger number. Frames before the loudest one are
    /// discarded — the attack is not part of the decay.
    static func decayRate(of samples: [Float], sampleRate: Double) -> Float {
        let frameLength = max(AnalysisConstants.minimumFrameLengthSamples, Int(AnalysisConstants.decayFrameSeconds * sampleRate))
        let hop = max(AnalysisConstants.minimumHopSamples, Int(AnalysisConstants.decayHopSeconds * sampleRate))
        guard samples.count >= frameLength * AnalysisConstants.decayMinimumFitPoints else { return 0 }

        var times: [Float] = []
        var logEnergies: [Float] = []
        var start = 0
        while start + frameLength <= samples.count {
            let frame = Array(samples[start..<(start + frameLength)])
            var rms: Float = 0
            vDSP_rmsqv(frame, 1, &rms, vDSP_Length(frameLength))
            if rms > AnalysisConstants.decayRmsFloor {
                times.append(Float(Double(start) / sampleRate))
                logEnergies.append(log(rms))
            }
            start += hop
        }

        guard let loudestIndex = logEnergies.indices.max(by: { logEnergies[$0] < logEnergies[$1] }),
              logEnergies.count - loudestIndex >= AnalysisConstants.decayMinimumFitPoints else { return 0 }

        let x = Array(times[loudestIndex...])
        let y = Array(logEnergies[loudestIndex...])
        let n = Float(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let sumXX = x.reduce(Float(0)) { $0 + $1 * $1 }
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return 0 }

        let slope = (n * sumXY - sumX * sumY) / denominator
        return max(0, -slope)
    }
}
