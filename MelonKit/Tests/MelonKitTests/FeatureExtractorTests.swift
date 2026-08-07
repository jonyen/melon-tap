import XCTest
@testable import MelonKit

final class FeatureExtractorTests: XCTestCase {

    func testPeakFrequencyOfPureToneAtAccelerometerRate() {
        // 800 Hz is the Watch batched accelerometer rate. 120 Hz is a plausible melon fundamental.
        let signal = SignalFixtures.decayingSine(
            frequency: 120, decayRate: 15, duration: 0.25, sampleRate: 800
        )
        let features = FeatureExtractor.extract(from: signal, sampleRate: 800)
        XCTAssertNotNil(features)
        XCTAssertEqual(features!.peakFrequencyHz, 120, accuracy: 3)
    }

    func testPeakFrequencyOfPureToneAtMicrophoneRate() {
        // Watch microphone typically delivers 16 kHz or higher. Same answer expected.
        let signal = SignalFixtures.decayingSine(
            frequency: 210, decayRate: 15, duration: 0.25, sampleRate: 16000
        )
        let features = FeatureExtractor.extract(from: signal, sampleRate: 16000)
        XCTAssertEqual(features!.peakFrequencyHz, 210, accuracy: 3)
    }

    func testEnergyOutsideTheBandIsIgnored() {
        // A loud 1200 Hz component sits above the 400 Hz band ceiling and must not win the peak.
        let inBand = SignalFixtures.decayingSine(
            frequency: 90, decayRate: 15, duration: 0.25, sampleRate: 16000, amplitude: 0.4
        )
        let outOfBand = SignalFixtures.decayingSine(
            frequency: 1200, decayRate: 15, duration: 0.25, sampleRate: 16000, amplitude: 1.0
        )
        let mixed = zip(inBand, outOfBand).map(+)
        let features = FeatureExtractor.extract(from: mixed, sampleRate: 16000)
        XCTAssertEqual(features!.peakFrequencyHz, 90, accuracy: 5)
    }

    func testTooFewSamplesReturnsNil() {
        XCTAssertNil(FeatureExtractor.extract(from: [0.1, 0.2, 0.3], sampleRate: 800))
    }

    func testDecayRateMatchesTheSynthesisedEnvelope() {
        // The fixture decays at exactly 30 nepers/second. The fitted value should recover it.
        let signal = SignalFixtures.decayingSine(
            frequency: 150, decayRate: 30, duration: 0.25, sampleRate: 8000
        )
        let features = FeatureExtractor.extract(from: signal, sampleRate: 8000)!
        XCTAssertEqual(features.decayRatePerSecond, 30, accuracy: 6)
    }

    func testFasterDecayProducesLargerDecayRate() {
        let slow = FeatureExtractor.extract(
            from: SignalFixtures.decayingSine(frequency: 150, decayRate: 10, duration: 0.25, sampleRate: 8000),
            sampleRate: 8000
        )!
        let fast = FeatureExtractor.extract(
            from: SignalFixtures.decayingSine(frequency: 150, decayRate: 60, duration: 0.25, sampleRate: 8000),
            sampleRate: 8000
        )!
        XCTAssertGreaterThan(fast.decayRatePerSecond, slow.decayRatePerSecond)
    }

    func testSpectralCentroidSitsNearASingleTone() {
        let signal = SignalFixtures.decayingSine(
            frequency: 200, decayRate: 15, duration: 0.25, sampleRate: 8000
        )
        let features = FeatureExtractor.extract(from: signal, sampleRate: 8000)!
        XCTAssertEqual(features.spectralCentroidHz, 200, accuracy: 40)
    }

    func testLowHeavySignalHasRatioAboveOne() {
        let signal = SignalFixtures.decayingSine(
            frequency: 80, decayRate: 15, duration: 0.25, sampleRate: 8000
        )
        let features = FeatureExtractor.extract(from: signal, sampleRate: 8000)!
        XCTAssertGreaterThan(features.lowHighEnergyRatio, 1)
    }

    func testHighHeavySignalHasRatioBelowOne() {
        let signal = SignalFixtures.decayingSine(
            frequency: 320, decayRate: 15, duration: 0.25, sampleRate: 8000
        )
        let features = FeatureExtractor.extract(from: signal, sampleRate: 8000)!
        XCTAssertLessThan(features.lowHighEnergyRatio, 1)
    }

    // MARK: - Regression found in review (M4)

    /// A window with zero high-band energy has a mathematically infinite low/high ratio, but
    /// `lowHighEnergyRatio` must not report `Float.infinity` itself: `ChannelFeatures` crosses
    /// the Watch-to-phone wire as JSON, and `JSONEncoder`'s default
    /// `nonConformingFloatEncodingStrategy` is `.throw`, so an infinite value there would
    /// silently drop the whole feature message. It reports
    /// `AnalysisConstants.highBandSilenceRatioSentinel` instead — a large finite stand-in chosen
    /// independently of `AnalysisConstants.lowHighRatioReferenceRange.upperBound` (the *scorer's*
    /// normalisation constant), so a future retune of the scorer's reference range cannot
    /// silently change what a degenerate window measures. `PhysicsScorer.normalise` clamps any
    /// value at or above that upper bound to 1.0 regardless, so scored output is unaffected by
    /// which finite value is used, as long as it's large enough — see
    /// `PhysicsScorerTests.testHighBandSilenceSentinelScoresSameAsInfinity` for that clamping
    /// behaviour pinned end to end.
    func testLowHighRatioOfWindowWithNoHighBandEnergyIsSentinel() {
        let silence = SignalFixtures.silence(count: 256)
        let spectrum = Spectrum(samples: silence, sampleRate: 8000)!
        XCTAssertEqual(
            FeatureExtractor.lowHighEnergyRatio(in: spectrum),
            AnalysisConstants.highBandSilenceRatioSentinel
        )
    }
}
