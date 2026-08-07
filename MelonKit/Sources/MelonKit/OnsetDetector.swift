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

        // Adaptive threshold from the median absolute deviation of the *unrectified*
        // frame-to-frame energy steps (both rises and falls together, signed difference then
        // magnituded). Two more obvious choices were tried first and both collapse:
        //   - MAD of the rectified rises: exact zero on every frame whose energy fell, which
        //     is close to half the buffer for any decaying signal, not just a silent one. That
        //     zero mass sits at the series' own median, dragging the median and MAD to zero,
        //     so the resulting threshold is cleared by ordinary jitter almost everywhere.
        //   - MAD of the frame energies themselves: not zero-inflated in general, but it
        //     measures the buffer's overall dynamic range rather than a local step size, so it
        //     over-estimates "ambient" scale whenever the buffer is signal-heavy (e.g. slow
        //     decay with tight inter-tap gaps leaves little true silence), making real attacks
        //     fail to clear it.
        // The unrectified step magnitude |energies[i] - energies[i-1]| avoids both: because it
        // measures a step rather than a level it is insensitive to the buffer's overall dynamic
        // range, and for a real decaying or noisy signal it is essentially never exactly zero (a
        // decay tail approaches but does not hit exact float32 zero at the decay rates modelled
        // here). Under literal digital silence, though, every step *is* exactly zero:
        // `stepDeviation` collapses to its 1e-6 floor below, and the resulting threshold is
        // small enough that ordinary quantisation-level jitter can clear it on many frames at
        // once. What keeps that from registering as a burst of spurious onsets is not this
        // statistic — it's the peak-picking further down: a candidate must dominate its own
        // minimum-separation neighbourhood and clear the minimum gap since the last accepted
        // onset, so a field of marginal, similarly-sized rises collapses to at most one
        // acceptance per neighbourhood rather than many. Narrowing that neighbourhood (the
        // minimum-separation window) later can reintroduce the burst this comment describes;
        // this statistic alone will not catch it.
        var steps = [Float](repeating: 0, count: energies.count)
        for i in 1..<energies.count {
            steps[i] = abs(energies[i] - energies[i - 1])
        }
        let sortedSteps = steps.sorted()
        let medianStep = sortedSteps[sortedSteps.count / 2]
        let stepDeviations = steps.map { abs($0 - medianStep) }.sorted()
        let stepDeviation = max(stepDeviations[stepDeviations.count / 2], 1e-6)
        let threshold = medianStep + AnalysisConstants.onsetThresholdFactor * stepDeviation

        // Peak-pick above the threshold, enforcing a minimum separation so that one tap's
        // ring-out cannot register as a second tap. A candidate must also be the largest rise
        // within its own minimum-separation neighborhood, not merely larger than its immediate
        // neighbors: a slow-decaying tap's short-time energy genuinely ripples as the RMS frame
        // beats against the tap's own carrier cycle, and those ripples can present several
        // smaller local maxima in a row that each individually clear a single global threshold.
        // Requiring a candidate to dominate its whole neighborhood — not just its two nearest
        // frames — suppresses those ripple peaks in favor of the one genuinely large attack.
        let minimumFrameGap = max(1, Int(AnalysisConstants.onsetMinimumSeparationSeconds * sampleRate) / hop)
        var onsets: [Onset] = []
        var lastAcceptedFrame = -minimumFrameGap

        for i in 1..<(rises.count - 1) {
            guard rises[i] > threshold else { continue }
            let windowStart = max(0, i - minimumFrameGap)
            let windowEnd = min(rises.count, i + minimumFrameGap + 1)
            guard rises[i] == rises[windowStart..<windowEnd].max(),
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
