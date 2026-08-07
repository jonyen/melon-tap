import Foundation

/// Scores ripeness from first principles: riper flesh is softer and less dense, so it resonates
/// lower, damps faster, and puts more of its energy in the low sub-band.
public struct PhysicsScorer: RipenessScorer {

    public init() {}

    public func score(taps: [TapFeatures]) throws -> RipenessScore {
        guard taps.count >= AnalysisConstants.requiredTapCount else {
            throw ScoringError.insufficientTaps(
                found: taps.count,
                required: AnalysisConstants.requiredTapCount
            )
        }

        let perTap = taps.map { combinedScore(for: $0) }
        let usable = perTap.enumerated().compactMap { index, value in
            value.map { (index: index, score: $0) }
        }
        guard !usable.isEmpty else {
            throw ScoringError.noUsableChannels
        }
        guard usable.count >= AnalysisConstants.requiredTapCount else {
            throw ScoringError.insufficientTaps(
                found: usable.count,
                required: AnalysisConstants.requiredTapCount
            )
        }

        // Discard the single tap furthest from the median, but only when that deviation is
        // large enough to look like a real mishit rather than ordinary capture noise. A mishit
        // or a passing shopping cart shows up as exactly one bad tap out of three.
        let median = medianValue(usable.map(\.score))
        let worst = usable.max(by: { abs($0.score - median) < abs($1.score - median) })!
        let keptIndices: [Int]
        if abs(worst.score - median) > AnalysisConstants.outlierDeviationThreshold {
            keptIndices = usable.map(\.index).filter { $0 != worst.index }
        } else {
            keptIndices = usable.map(\.index)
        }

        let keptTaps = keptIndices.map { taps[$0] }
        let value = keptIndices.map { perTap[$0]! }.reduce(0, +) / Float(keptIndices.count)

        return RipenessScore(
            value: min(max(value, 0), 1),
            breakdown: breakdown(for: keptTaps),
            tapsUsed: keptIndices.count
        )
    }

    // MARK: - Per-tap scoring

    /// Blends the two channels. Returns nil when a tap has neither.
    private func combinedScore(for tap: TapFeatures) -> Float? {
        let mic = tap.microphone.map(channelScore)
        let accel = tap.accelerometer.map(channelScore)

        switch (mic, accel) {
        case let (mic?, accel?):
            let w = AnalysisConstants.accelerometerChannelWeight
            return accel * w + mic * (1 - w)
        case let (mic?, nil):
            return mic
        case let (nil, accel?):
            return accel
        case (nil, nil):
            return nil
        }
    }

    /// Weighted blend of the three ripeness-bearing features, each normalised to 0...1.
    private func channelScore(_ features: ChannelFeatures) -> Float {
        peakComponent(features) * AnalysisConstants.peakFrequencyWeight
            + decayComponent(features) * AnalysisConstants.decayRateWeight
            + ratioComponent(features) * AnalysisConstants.lowHighRatioWeight
    }

    /// Lower peak frequency reads as riper, so this normalisation is inverted.
    private func peakComponent(_ features: ChannelFeatures) -> Float {
        1 - normalise(features.peakFrequencyHz, into: AnalysisConstants.peakFrequencyReferenceRange)
    }

    private func decayComponent(_ features: ChannelFeatures) -> Float {
        normalise(features.decayRatePerSecond, into: AnalysisConstants.decayRateReferenceRange)
    }

    private func ratioComponent(_ features: ChannelFeatures) -> Float {
        normalise(features.lowHighEnergyRatio, into: AnalysisConstants.lowHighRatioReferenceRange)
    }

    private func normalise(_ value: Float, into range: ClosedRange<Float>) -> Float {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func medianValue(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    // MARK: - Breakdown

    /// Averages every component across the kept taps so the detail view can show what drove the score.
    private func breakdown(for taps: [TapFeatures]) -> [String: Float] {
        var result: [String: Float] = [:]

        func record(_ prefix: String, _ channels: [ChannelFeatures]) {
            guard !channels.isEmpty else { return }
            let count = Float(channels.count)
            result[prefix] = channels.map(channelScore).reduce(0, +) / count
            result["\(prefix).peakFrequency"] = channels.map(peakComponent).reduce(0, +) / count
            result["\(prefix).decayRate"] = channels.map(decayComponent).reduce(0, +) / count
            result["\(prefix).lowHighRatio"] = channels.map(ratioComponent).reduce(0, +) / count
        }

        record("microphone", taps.compactMap(\.microphone))
        record("accelerometer", taps.compactMap(\.accelerometer))
        return result
    }
}
