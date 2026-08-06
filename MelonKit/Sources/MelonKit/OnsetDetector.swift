import Accelerate
import Foundation

/// The start of one tap transient.
public struct Onset: Equatable, Sendable {

    /// Index into the source buffer where the tap begins.
    public let sampleIndex: Int

    /// How far the energy rise exceeded the adaptive threshold. Larger is a more confident hit.
    public let strength: Float

    public init(sampleIndex: Int, strength: Float) {
        self.sampleIndex = sampleIndex
        self.strength = strength
    }
}

/// Finds tap transients by looking for sharp rises in short-time energy.
/// Sample-rate agnostic: the same code serves the 800 Hz accelerometer and the microphone stream.
public enum OnsetDetector {

    public static func detect(in samples: [Float], sampleRate: Double) -> [Onset] {
        let frameLength = max(
            AnalysisConstants.minimumFrameLengthSamples, Int(AnalysisConstants.onsetFrameSeconds * sampleRate)
        )
        let hop = max(
            AnalysisConstants.minimumHopSamples, Int(AnalysisConstants.onsetHopSeconds * sampleRate)
        )
        guard samples.count > frameLength * 4 else { return [] }

        // Frame-wise RMS.
        var energies: [Float] = []
        var frameStarts: [Int] = []
        var start = 0
        while start + frameLength <= samples.count {
            var rms: Float = 0
            samples.withUnsafeBufferPointer { buffer in
                vDSP_rmsqv(buffer.baseAddress! + start, 1, &rms, vDSP_Length(frameLength))
            }
            energies.append(rms)
            frameStarts.append(start)
            start += hop
        }
        guard energies.count > 3 else { return [] }

        // Rectified first difference: only rises matter, a decay is not an onset.
        var rises = [Float](repeating: 0, count: energies.count)
        for i in 1..<energies.count {
            rises[i] = max(0, energies[i] - energies[i - 1])
        }

        // Adaptive threshold from the median absolute deviation of the frame energies
        // themselves, not of the rectified rises. The rise series is exact zero at every
        // frame whose energy fell (a decaying frame contributes nothing under rectification),
        // so roughly half its entries are hard zeros. That zero mass sits at the rise series'
        // own median, collapsing both its median and its MAD toward zero — a threshold
        // derived from the rises would then be cleared by ordinary noise jitter almost
        // everywhere. Frame energies (RMS magnitudes) carry no such zero-inflation, so their
        // MAD is a stable estimate of the ambient noise floor's scale; a rise must clear a
        // multiple of that scale to count as a real onset.
        let sortedEnergies = energies.sorted()
        let medianEnergy = sortedEnergies[sortedEnergies.count / 2]
        let energyDeviations = energies.map { abs($0 - medianEnergy) }.sorted()
        let energyDeviation = max(energyDeviations[energyDeviations.count / 2], 1e-6)
        let threshold = AnalysisConstants.onsetThresholdFactor * energyDeviation

        // Peak-pick above the threshold, enforcing a minimum separation so that one tap's
        // ring-out cannot register as a second tap.
        let minimumFrameGap = max(1, Int(AnalysisConstants.onsetMinimumSeparationSeconds * sampleRate) / hop)
        var onsets: [Onset] = []
        var lastAcceptedFrame = -minimumFrameGap

        for i in 1..<(rises.count - 1) {
            guard rises[i] > threshold,
                  rises[i] >= rises[i - 1],
                  rises[i] >= rises[i + 1],
                  i - lastAcceptedFrame >= minimumFrameGap else { continue }
            onsets.append(Onset(sampleIndex: frameStarts[i - 1], strength: rises[i] - threshold))
            lastAcceptedFrame = i
        }

        return onsets
    }

    /// The analysis window that follows an onset, truncated if the buffer ends first.
    public static func window(at onset: Onset, in samples: [Float], sampleRate: Double) -> [Float] {
        let length = Int(AnalysisConstants.tapWindowSeconds * sampleRate)
        let start = min(onset.sampleIndex, samples.count)
        let end = min(start + length, samples.count)
        guard start < end else { return [] }
        return Array(samples[start..<end])
    }
}
