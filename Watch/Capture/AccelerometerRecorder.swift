import CoreMotion
import Foundation
import MelonKit

/// Captures the 800 Hz batched accelerometer stream and reduces it to a scalar magnitude signal.
///
/// Magnitude rather than a single axis: the watch's orientation against the rind is arbitrary,
/// so per-axis values depend on how the wrist happens to be turned, while magnitude does not.
@MainActor
final class AccelerometerRecorder {

    static var isSupported: Bool {
        CMBatchedSensorManager.isAccelerometerSupported
    }

    /// Nominal rate of the batched stream. Actual timestamps are used to compute the real rate.
    private static let nominalSampleRate: Double = 800

    private let manager = CMBatchedSensorManager()

    /// Records for `duration` seconds. Requires an open `WorkoutSessionGate`.
    ///
    /// The batched stream delivers roughly once per second, and the deadline is only checked
    /// between batches, so the returned sample count can run up to one batch interval
    /// (~1 second) past `duration`. Callers must not assume this channel's length matches the
    /// microphone channel's.
    func record(duration: Double) async throws -> (samples: [Float], sampleRate: Double) {
        guard Self.isSupported else { throw CaptureError.highRateMotionUnavailable }

        var samples: [Float] = []
        var firstTimestamp: TimeInterval?
        var lastTimestamp: TimeInterval?

        let updates = manager.accelerometerUpdates()
        // Guarantees the 800 Hz sensor stream is stopped on every exit from here on — a
        // thrown error from the async sequence, or Task cancellation — not just the normal
        // `break` below. A leaked stream is a battery drain, the same failure mode an unended
        // workout session would be.
        defer { manager.stopAccelerometerUpdates() }
        let deadline = Date().addingTimeInterval(duration)

        for try await batch in updates {
            for reading in batch {
                let a = reading.acceleration
                // Subtract the 1 g static component so that the signal is the vibration alone.
                let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() - 1.0
                samples.append(Float(magnitude))
                if firstTimestamp == nil { firstTimestamp = reading.timestamp }
                lastTimestamp = reading.timestamp
            }
            if Date() >= deadline { break }
        }

        // Derive the true rate from the timestamps rather than trusting the nominal 800 Hz.
        // A wrong rate would shift every frequency the extractor reports.
        let sampleRate: Double
        if let first = firstTimestamp, let last = lastTimestamp, last > first, samples.count > 1 {
            sampleRate = Double(samples.count - 1) / (last - first)
        } else {
            sampleRate = Self.nominalSampleRate
        }

        return (samples, sampleRate)
    }
}
