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
}
