import XCTest
@testable import MelonKit

final class SignalFixturesTests: XCTestCase {

    func testDecayingSineHasExpectedSampleCount() {
        let signal = SignalFixtures.decayingSine(
            frequency: 120, decayRate: 20, duration: 0.25, sampleRate: 800
        )
        XCTAssertEqual(signal.count, 200)
    }

    func testDecayingSineAmplitudeFallsByExpectedFactor() {
        // After t = 1/decayRate seconds the envelope is exp(-1) of its start.
        let decayRate: Float = 20
        let sampleRate: Double = 8000
        let signal = SignalFixtures.decayingSine(
            frequency: 100, decayRate: decayRate, duration: 0.2, sampleRate: sampleRate
        )
        let oneTimeConstant = Int(Double(1 / decayRate) * sampleRate)
        let earlyPeak = signal[0..<200].map(abs).max()!
        let latePeak = signal[oneTimeConstant..<(oneTimeConstant + 200)].map(abs).max()!
        XCTAssertEqual(latePeak / earlyPeak, exp(-1), accuracy: 0.1)
    }

    func testWhiteNoiseIsDeterministic() {
        let a = SignalFixtures.whiteNoise(amplitude: 0.1, count: 64)
        let b = SignalFixtures.whiteNoise(amplitude: 0.1, count: 64)
        XCTAssertEqual(a, b)
    }

    func testConcatenatedReportsSegmentStarts() {
        let (samples, starts) = SignalFixtures.concatenated([
            SignalFixtures.silence(count: 10),
            SignalFixtures.silence(count: 5)
        ])
        XCTAssertEqual(samples.count, 15)
        XCTAssertEqual(starts, [0, 10])
    }
}
