import Foundation

/// Synthetic signals with exactly known properties, used as ground truth for the extractor tests.
enum SignalFixtures {

    /// A sinusoid at `frequency` whose amplitude follows exp(-decayRate * t).
    /// This is the idealised shape of a struck object ringing down.
    static func decayingSine(
        frequency: Float,
        decayRate: Float,
        duration: Double,
        sampleRate: Double,
        amplitude: Float = 1.0
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        return (0..<count).map { i in
            let t = Float(Double(i) / sampleRate)
            return amplitude * exp(-decayRate * t) * sin(2 * .pi * frequency * t)
        }
    }

    /// Deterministic pseudo-random noise. Uses a fixed linear congruential generator so tests never flake.
    static func whiteNoise(amplitude: Float, count: Int, seed: UInt64 = 42) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Float(state >> 33) / Float(UInt32.max >> 1) - 1.0
            return unit * amplitude
        }
    }

    /// Silence of `count` samples.
    static func silence(count: Int) -> [Float] {
        [Float](repeating: 0, count: count)
    }

    /// Concatenates segments into one buffer, returning the buffer and the start index of each segment.
    static func concatenated(_ segments: [[Float]]) -> (samples: [Float], startIndices: [Int]) {
        var samples: [Float] = []
        var starts: [Int] = []
        for segment in segments {
            starts.append(samples.count)
            samples.append(contentsOf: segment)
        }
        return (samples, starts)
    }
}
