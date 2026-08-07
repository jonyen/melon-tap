import Foundation
import MelonKit
import Observation

/// One melon as captured and scored on the wrist.
struct CapturedMelon: Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let taps: [TapFeatures]
    let score: RipenessScore
    let audioFileURL: URL?
    let accelerometerFileURL: URL?
}

enum CaptureState: Equatable {
    case idle
    case recording
    case analysing
    case failed(String)
}

/// Runs a capture end to end: open the workout gate, record both channels, detect onsets on the
/// accelerometer, window both channels at those onsets, extract features, score, and rank.
@MainActor
@Observable
final class CaptureCoordinator {

    private(set) var melons: [CapturedMelon] = []
    private(set) var state: CaptureState = .idle
    private(set) var lastWarning: String?

    private let gate = WorkoutSessionGate()
    private let accelerometer = AccelerometerRecorder()
    private let microphone = MicrophoneRecorder()
    private let scorer = PhysicsScorer()

    /// Melons ordered ripest first. This ordering is what the whole app exists to produce.
    var ranked: [CapturedMelon] {
        melons.sorted { $0.score.value > $1.score.value }
    }

    func startNewSession() {
        melons.removeAll()
        state = .idle
        lastWarning = nil
    }

    func capture() async {
        state = .recording
        lastWarning = nil

        // The accelerometer path is best-effort. A Series 7 or a HealthKit refusal degrades
        // to microphone-only capture and says so, rather than failing the capture.
        var gateOpened = false
        do {
            try await gate.open()
            gateOpened = true
        } catch let error as CaptureError {
            lastWarning = error.errorDescription
        } catch {
            lastWarning = error.localizedDescription
        }

        // Both channels must record over the same real-time window, concurrently, so that a
        // tap's accelerometer onset and its microphone onset describe the same physical strike.
        // Recording them one after another (open gate, await the accelerometer to finish, then
        // await the microphone to finish) would have the user tap during one four-second window
        // and again during an unrelated later one; the onset index conversion in `analyse`
        // assumes both channels started at approximately the same instant, and only concurrent
        // recording provides that.
        async let accelOutcome = attemptAccelerometer(gateOpened: gateOpened)
        async let micOutcome = attemptMicrophone()
        let (accelResultOutcome, micResultOutcome) = await (accelOutcome, micOutcome)
        if gateOpened { gate.close() }

        var accelResult: (samples: [Float], sampleRate: Double)?
        switch accelResultOutcome {
        case .success(let value):
            accelResult = value
        case .failure(let error):
            // When the gate itself failed to open, `lastWarning` already carries that message
            // and there is nothing new to report — the accelerometer was never attempted.
            if gateOpened { lastWarning = error.errorDescription }
        }

        var micResult: (samples: [Float], sampleRate: Double, fileURL: URL)?
        switch micResultOutcome {
        case .success(let value):
            micResult = value
        case .failure(let error):
            lastWarning = error.errorDescription
        }

        // A store loud enough to bury the taps makes the microphone channel worse than useless,
        // since it would drag the score toward whatever the room sounds like. Drop it and say so.
        if let mic = micResult, !Self.hasUsableTapContrast(mic.samples) {
            micResult = nil
            lastWarning = accelResult == nil
                ? "Too noisy here, and no vibration sensor. Try somewhere quieter."
                : "Too noisy for the microphone. Scoring on vibration alone."
        }

        guard accelResult != nil || micResult != nil else {
            state = .failed(CaptureError.bothChannelsFailed.errorDescription!)
            return
        }

        state = .analysing
        analyse(accelerometer: accelResult, microphone: micResult)
    }

    /// Records the accelerometer channel. Never attempted when the workout gate did not open,
    /// since `CMBatchedSensorManager` requires an active workout session.
    private func attemptAccelerometer(gateOpened: Bool) async -> Result<(samples: [Float], sampleRate: Double), CaptureError> {
        guard gateOpened else { return .failure(.healthKitDenied) }
        do {
            return .success(try await accelerometer.record(duration: AnalysisConstants.captureDurationSeconds))
        } catch let error as CaptureError {
            return .failure(error)
        } catch {
            return .failure(.highRateMotionUnavailable)
        }
    }

    private func attemptMicrophone() async -> Result<(samples: [Float], sampleRate: Double, fileURL: URL), CaptureError> {
        do {
            return .success(try await microphone.record(duration: AnalysisConstants.captureDurationSeconds))
        } catch let error as CaptureError {
            return .failure(error)
        } catch {
            return .failure(.microphoneDenied)
        }
    }

    private func analyse(
        accelerometer accel: (samples: [Float], sampleRate: Double)?,
        microphone mic: (samples: [Float], sampleRate: Double, fileURL: URL)?
    ) {
        // Onsets come from whichever channel is available, preferring the accelerometer:
        // its transient is sharper and it does not hear the store.
        let onsetSource: (samples: [Float], sampleRate: Double)
        if let accel { onsetSource = (accel.samples, accel.sampleRate) }
        else if let mic { onsetSource = (mic.samples, mic.sampleRate) }
        else { state = .failed(CaptureError.bothChannelsFailed.errorDescription!); return }

        let onsets = OnsetDetector.detect(in: onsetSource.samples, sampleRate: onsetSource.sampleRate)

        guard onsets.count >= AnalysisConstants.requiredTapCount else {
            state = .failed("Only \(onsets.count) clean tap\(onsets.count == 1 ? "" : "s") detected. Tap three times, firmly.")
            return
        }

        // Take the strongest three onsets, in time order.
        let chosen = onsets
            .sorted { $0.strength > $1.strength }
            .prefix(AnalysisConstants.requiredTapCount)
            .sorted { $0.sampleIndex < $1.sampleIndex }

        let taps: [TapFeatures] = chosen.map { onset in
            let accelFeatures = accel.flatMap { channel -> ChannelFeatures? in
                let window = OnsetDetector.window(at: onset, in: channel.samples, sampleRate: channel.sampleRate)
                return FeatureExtractor.extract(from: window, sampleRate: channel.sampleRate)
            }
            // The microphone stream runs at a different rate, so the onset's sample index must be
            // converted into that stream's timebase before windowing.
            let micFeatures = mic.flatMap { channel -> ChannelFeatures? in
                let seconds = Double(onset.sampleIndex) / onsetSource.sampleRate
                let index = Int(seconds * channel.sampleRate)
                let converted = Onset(sampleIndex: index, strength: onset.strength)
                let window = OnsetDetector.window(at: converted, in: channel.samples, sampleRate: channel.sampleRate)
                return FeatureExtractor.extract(from: window, sampleRate: channel.sampleRate)
            }
            return TapFeatures(microphone: micFeatures, accelerometer: accelFeatures)
        }

        do {
            let score = try scorer.score(taps: taps)
            let accelFileURL = accel.flatMap { writeAccelerometer($0.samples) }
            melons.append(
                CapturedMelon(
                    id: UUID(),
                    capturedAt: Date(),
                    taps: taps,
                    score: score,
                    audioFileURL: mic?.fileURL,
                    accelerometerFileURL: accelFileURL
                )
            )
            state = .idle
        } catch ScoringError.insufficientTaps(let found, let required) {
            state = .failed("Only \(found) of \(required) taps were usable. Try again.")
        } catch {
            state = .failed("Could not score this melon. Try again.")
        }
    }

    /// True when the loudest sample stands far enough above the typical sample level that the
    /// taps are distinguishable from the room.
    private static func hasUsableTapContrast(_ samples: [Float]) -> Bool {
        guard samples.count > 32 else { return false }
        let magnitudes = samples.map(abs)
        let sorted = magnitudes.sorted()
        let median = max(sorted[sorted.count / 2], 1e-6)
        let peak = sorted[sorted.count - 1]
        return peak / median >= AnalysisConstants.minimumTapToNoiseRatio
    }

    /// Persists the raw accelerometer magnitudes so a better extractor can revisit them later.
    private func writeAccelerometer(_ samples: [Float]) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("melon-accel-\(UUID().uuidString).bin")
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return (try? data.write(to: url)) == nil ? nil : url
    }
}
