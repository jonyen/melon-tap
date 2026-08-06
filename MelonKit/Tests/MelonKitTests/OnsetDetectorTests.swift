import XCTest
@testable import MelonKit

final class OnsetDetectorTests: XCTestCase {

    /// Builds three taps separated by silence, at 800 Hz, and reports where each tap starts.
    private func threeTaps(noiseAmplitude: Float) -> (samples: [Float], starts: [Int]) {
        let sampleRate: Double = 800
        let tap = SignalFixtures.decayingSine(
            frequency: 120, decayRate: 40, duration: 0.2, sampleRate: sampleRate
        )
        let gap = SignalFixtures.silence(count: Int(0.4 * sampleRate))

        let (clean, starts) = SignalFixtures.concatenated([gap, tap, gap, tap, gap, tap])
        // Segment starts alternate gap, tap, gap, tap, gap, tap — the taps are at indices 1, 3, 5.
        let tapStarts = [starts[1], starts[3], starts[5]]

        guard noiseAmplitude > 0 else { return (clean, tapStarts) }
        let noise = SignalFixtures.whiteNoise(amplitude: noiseAmplitude, count: clean.count)
        return (zip(clean, noise).map(+), tapStarts)
    }

    func testFindsThreeCleanTaps() {
        let (samples, expected) = threeTaps(noiseAmplitude: 0)
        let onsets = OnsetDetector.detect(in: samples, sampleRate: 800)
        XCTAssertEqual(onsets.count, 3)
        for (onset, expectedStart) in zip(onsets, expected) {
            // Frame-level resolution: within one 5 ms frame at 800 Hz is 4 samples, allow 8.
            XCTAssertEqual(onset.sampleIndex, expectedStart, accuracy: 8)
        }
    }

    func testFindsThreeTapsBuriedInStoreNoise() {
        let (samples, expected) = threeTaps(noiseAmplitude: 0.05)
        let onsets = OnsetDetector.detect(in: samples, sampleRate: 800)
        XCTAssertEqual(onsets.count, 3)
        XCTAssertEqual(onsets[0].sampleIndex, expected[0], accuracy: 12)
    }

    func testDoesNotReportOnsetsInPureNoise() {
        let samples = SignalFixtures.whiteNoise(amplitude: 0.05, count: 2400)
        let onsets = OnsetDetector.detect(in: samples, sampleRate: 800)
        XCTAssertTrue(onsets.isEmpty)
    }

    func testRingOutIsNotCountedAsASecondOnset() {
        // One long tap must produce exactly one onset, not one per amplitude wobble.
        let tap = SignalFixtures.decayingSine(
            frequency: 120, decayRate: 8, duration: 1.0, sampleRate: 800
        )
        let (samples, _) = SignalFixtures.concatenated([
            SignalFixtures.silence(count: 400), tap
        ])
        XCTAssertEqual(OnsetDetector.detect(in: samples, sampleRate: 800).count, 1)
    }

    func testWindowStartsAtTheOnsetAndHasTheConfiguredLength() {
        let (samples, _) = threeTaps(noiseAmplitude: 0)
        let onsets = OnsetDetector.detect(in: samples, sampleRate: 800)
        let window = OnsetDetector.window(at: onsets[0], in: samples, sampleRate: 800)
        XCTAssertEqual(window.count, Int(AnalysisConstants.tapWindowSeconds * 800))
        XCTAssertEqual(window[0], samples[onsets[0].sampleIndex])
    }

    func testWindowIsTruncatedAtTheEndOfTheBuffer() {
        let samples = SignalFixtures.decayingSine(
            frequency: 120, decayRate: 40, duration: 0.1, sampleRate: 800
        )
        let onset = Onset(sampleIndex: 60, strength: 1)
        let window = OnsetDetector.window(at: onset, in: samples, sampleRate: 800)
        XCTAssertEqual(window.count, samples.count - 60)
    }

    // MARK: - Regressions found in review

    // The brief's own `threeTaps` fixture (decay rate 40, 0.4 s gaps) does not exercise the
    // full range this detector has to work across: `AnalysisConstants.decayRateReferenceRange`
    // permits decay rates from 5 to 80, and real inter-tap timing is not fixed. A prior version
    // of the threshold statistic collapsed on slow decay with long silent gaps (a genuine
    // ring-down ripple in short-time energy cleared a near-zero threshold, registering as a
    // second onset per tap) and, separately, on moderate decay with tight tap spacing (little
    // true silence in the buffer inflated the threshold past the size of a real attack, missing
    // every onset). These tests pin both failure modes at both the accelerometer rate and a
    // microphone rate, so a regression to either statistic trips a test rather than shipping
    // silently — the six tests above only exercise one point in this space.

    /// Builds three taps separated by silence at an arbitrary decay rate, gap, and sample rate.
    private func threeTapsCustom(
        decayRate: Float, gapSeconds: Double, sampleRate: Double
    ) -> (samples: [Float], starts: [Int]) {
        let tap = SignalFixtures.decayingSine(
            frequency: 120, decayRate: decayRate, duration: 0.2, sampleRate: sampleRate
        )
        let gap = SignalFixtures.silence(count: Int(gapSeconds * sampleRate))
        let (samples, starts) = SignalFixtures.concatenated([gap, tap, gap, tap, gap, tap])
        return (samples, [starts[1], starts[3], starts[5]])
    }

    func testDoesNotDoubleCountRingRippleWithSlowDecayAndLongGaps_AccelerometerRate() {
        // decay rate 5 is the slow end of decayRateReferenceRange; a 1.0 s gap gives the
        // ring-down plenty of room to ripple before the next tap starts.
        let (samples, _) = threeTapsCustom(decayRate: 5, gapSeconds: 1.0, sampleRate: 800)
        XCTAssertEqual(OnsetDetector.detect(in: samples, sampleRate: 800).count, 3)
    }

    func testDoesNotDoubleCountRingRippleWithSlowDecayAndLongGaps_MicrophoneRate() {
        let sampleRate: Double = 44100
        let (samples, _) = threeTapsCustom(decayRate: 5, gapSeconds: 1.0, sampleRate: sampleRate)
        XCTAssertEqual(OnsetDetector.detect(in: samples, sampleRate: sampleRate).count, 3)
    }

    func testFindsTapsWithModerateDecayAndTightSpacing_AccelerometerRate() {
        // decay rate 8 barely thins the tap out within 0.2 s, and a 0.1 s gap leaves almost no
        // true silence in the buffer to establish an ambient floor from.
        let (samples, _) = threeTapsCustom(decayRate: 8, gapSeconds: 0.1, sampleRate: 800)
        XCTAssertEqual(OnsetDetector.detect(in: samples, sampleRate: 800).count, 3)
    }

    func testFindsTapsWithModerateDecayAndTightSpacing_MicrophoneRate() {
        let sampleRate: Double = 44100
        let (samples, _) = threeTapsCustom(decayRate: 8, gapSeconds: 0.1, sampleRate: sampleRate)
        XCTAssertEqual(OnsetDetector.detect(in: samples, sampleRate: sampleRate).count, 3)
    }
}
