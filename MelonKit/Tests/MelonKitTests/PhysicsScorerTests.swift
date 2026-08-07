import XCTest
@testable import MelonKit

final class PhysicsScorerTests: XCTestCase {

    private let scorer = PhysicsScorer()

    private func features(peak: Float, decay: Float, ratio: Float) -> ChannelFeatures {
        ChannelFeatures(
            peakFrequencyHz: peak,
            spectralCentroidHz: peak,
            decayRatePerSecond: decay,
            lowHighEnergyRatio: ratio
        )
    }

    private func taps(peak: Float, decay: Float, ratio: Float, count: Int = 3) -> [TapFeatures] {
        let channel = features(peak: peak, decay: decay, ratio: ratio)
        return (0..<count).map { _ in
            TapFeatures(microphone: channel, accelerometer: channel)
        }
    }

    func testLowerPeakFrequencyScoresRiper() throws {
        let low = try scorer.score(taps: taps(peak: 90, decay: 40, ratio: 3))
        let high = try scorer.score(taps: taps(peak: 260, decay: 40, ratio: 3))
        XCTAssertGreaterThan(low.value, high.value)
    }

    func testFasterDecayScoresRiper() throws {
        let fast = try scorer.score(taps: taps(peak: 150, decay: 70, ratio: 3))
        let slow = try scorer.score(taps: taps(peak: 150, decay: 10, ratio: 3))
        XCTAssertGreaterThan(fast.value, slow.value)
    }

    func testMoreLowEnergyScoresRiper() throws {
        let lowHeavy = try scorer.score(taps: taps(peak: 150, decay: 40, ratio: 5))
        let highHeavy = try scorer.score(taps: taps(peak: 150, decay: 40, ratio: 0.3))
        XCTAssertGreaterThan(lowHeavy.value, highHeavy.value)
    }

    func testScoreStaysWithinZeroToOne() throws {
        let extreme = try scorer.score(taps: taps(peak: 10, decay: 500, ratio: 100))
        XCTAssertGreaterThanOrEqual(extreme.value, 0)
        XCTAssertLessThanOrEqual(extreme.value, 1)
    }

    func testOutlierTapIsDiscarded() throws {
        let good = features(peak: 100, decay: 45, ratio: 4)
        let mishit = features(peak: 290, decay: 6, ratio: 0.2)
        let withMishit = [
            TapFeatures(microphone: good, accelerometer: good),
            TapFeatures(microphone: good, accelerometer: good),
            TapFeatures(microphone: mishit, accelerometer: mishit)
        ]
        let clean = try scorer.score(taps: taps(peak: 100, decay: 45, ratio: 4))
        let withOutlier = try scorer.score(taps: withMishit)
        XCTAssertEqual(withOutlier.value, clean.value, accuracy: 0.01)
        XCTAssertEqual(withOutlier.tapsUsed, 2)
    }

    func testTooFewTapsThrows() {
        XCTAssertThrowsError(try scorer.score(taps: taps(peak: 150, decay: 40, ratio: 3, count: 2))) { error in
            XCTAssertEqual(error as? ScoringError, .insufficientTaps(found: 2, required: 3))
        }
    }

    func testTapWithNoChannelsThrows() {
        let empty = (0..<3).map { _ in TapFeatures(microphone: nil, accelerometer: nil) }
        XCTAssertThrowsError(try scorer.score(taps: empty)) { error in
            XCTAssertEqual(error as? ScoringError, .noUsableChannels)
        }
    }

    func testConsistentTapsKeepsAllThree() throws {
        let score = try scorer.score(taps: taps(peak: 100, decay: 45, ratio: 4))
        XCTAssertEqual(score.tapsUsed, 3)
        XCTAssertEqual(score.value, 0.7077, accuracy: 0.001)
    }

    func testTwoUsableTapsThrowsInsufficientTaps() {
        let channel = features(peak: 100, decay: 45, ratio: 4)
        let mostlyEmpty = [
            TapFeatures(microphone: channel, accelerometer: nil),
            TapFeatures(microphone: channel, accelerometer: nil),
            TapFeatures(microphone: nil, accelerometer: nil)
        ]
        XCTAssertThrowsError(try scorer.score(taps: mostlyEmpty)) { error in
            XCTAssertEqual(error as? ScoringError, .insufficientTaps(found: 2, required: 3))
        }
    }

    func testMicrophoneOnlyStillScores() throws {
        let channel = features(peak: 100, decay: 45, ratio: 4)
        let micOnly = (0..<3).map { _ in TapFeatures(microphone: channel, accelerometer: nil) }
        let score = try scorer.score(taps: micOnly)
        XCTAssertGreaterThan(score.value, 0)
        XCTAssertNotNil(score.breakdown["microphone"])
        XCTAssertNil(score.breakdown["accelerometer"])
    }

    /// The finite sentinel `FeatureExtractor` reports for a degenerate, high-band-silent window
    /// (see `AnalysisConstants.highBandSilenceRatioSentinel`) must score identically to
    /// `Float.infinity`, the value it replaced (M4 regression fix): both sit at or above
    /// `lowHighRatioReferenceRange`'s upper bound, so `normalise` clamps either one to 1.0, and
    /// the sentinel does not change scored output.
    func testHighBandSilenceSentinelScoresSameAsInfinity() throws {
        let withSentinel = try scorer.score(taps: taps(
            peak: 150, decay: 40, ratio: AnalysisConstants.highBandSilenceRatioSentinel
        ))
        let withInfinity = try scorer.score(taps: taps(peak: 150, decay: 40, ratio: .infinity))
        XCTAssertEqual(withSentinel.value, withInfinity.value)
        XCTAssertEqual(withSentinel.breakdown["accelerometer.lowHighRatio"], 1.0)
    }

    func testBreakdownExposesEveryContributingFeature() throws {
        let score = try scorer.score(taps: taps(peak: 120, decay: 40, ratio: 3))
        for key in ["microphone", "accelerometer",
                    "accelerometer.peakFrequency",
                    "accelerometer.decayRate",
                    "accelerometer.lowHighRatio"] {
            XCTAssertNotNil(score.breakdown[key], "missing breakdown key \(key)")
        }
    }
}
