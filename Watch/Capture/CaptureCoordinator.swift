import Foundation
import MelonKit
import Observation

/// One melon as captured and scored on the wrist.
struct CapturedMelon: Identifiable, Equatable, Sendable {
    let id: UUID
    /// The bin visit this melon was captured under. Stamped from `CaptureCoordinator.sessionID`
    /// so the phone can group melons by the user's explicit "New Bin" boundary instead of
    /// inferring it from capture-time proximity.
    let sessionID: UUID
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
    /// A capture just finished successfully. Carries the melon so the view can show its score
    /// and rank directly, rather than sending the user through the ranking list to find it.
    case scored(CapturedMelon)
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

    /// The current bin visit. Every `CapturedMelon` produced while this value is current is
    /// stamped with it, so the phone can tell which melons came from the same "New Bin" boundary
    /// without guessing from capture timestamps. Minted fresh here (covering the value at init)
    /// and again in `startNewSession()`.
    private(set) var sessionID = UUID()

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
        sessionID = UUID()
    }

    func capture() async {
        state = .recording
        lastWarning = nil

        // Resolves microphone permission and warms the audio session before either recorder
        // starts. `AVAudioApplication.requestRecordPermission()` suspends for as long as the
        // user takes to answer the system dialog on first launch — unbounded — so it cannot run
        // inside the concurrent section below without letting the accelerometer's whole
        // four-second window elapse while the microphone has not even started. See
        // `MicrophoneRecorder.prepareForRecording()`.
        await microphone.prepareForRecording()

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
        // assumes both channels started at approximately the same instant. This section now
        // contains only the two `record(duration:)` calls — permission and session setup already
        // happened above — so the skew between them is bounded by each recorder's own remaining
        // (short, synchronous) setup work (CoreMotion stream start on one side, AVAudioEngine
        // prepare/start on the other) rather than by an unbounded permission prompt or by capture
        // duration. Declaring both `async let` bindings before awaiting either starts both
        // `record(duration:)` calls before either one's four-second body runs, but this is not a
        // guarantee of true parallel execution: both recorders are `@MainActor` and so interleave
        // on the same serial executor at suspension points. How small the resulting skew is in
        // practice is a hardware question, answered by on-device testing, not by this comment.
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
            // Not one of AccelerometerRecorder's documented throws (it only throws
            // .highRateMotionUnavailable) — a transient CoreMotion delivery error or task
            // cancellation, say. Preserve what actually happened instead of guessing it was a
            // hardware-support problem.
            return .failure(.other(error.localizedDescription))
        }
    }

    private func attemptMicrophone() async -> Result<(samples: [Float], sampleRate: Double, fileURL: URL), CaptureError> {
        do {
            return .success(try await microphone.record(duration: AnalysisConstants.captureDurationSeconds))
        } catch let error as CaptureError {
            return .failure(error)
        } catch {
            // Not one of MicrophoneRecorder's documented throws (it only throws
            // .microphoneDenied) — an audio-session conflict from engine.start(), a
            // Task.sleep cancellation, say. Preserve what actually happened instead of
            // guessing it was a permission problem.
            return .failure(.other(error.localizedDescription))
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

        // The microphone stream runs at a different rate, so an onset's sample index must be
        // converted into that stream's timebase before it can window or be judged for noise.
        func convert(_ onset: Onset, to sampleRate: Double) -> Onset {
            let seconds = Double(onset.sampleIndex) / onsetSource.sampleRate
            let index = Int(seconds * sampleRate)
            return Onset(sampleIndex: index, strength: onset.strength)
        }

        var mic = mic
        // A store loud enough to bury the taps makes the microphone channel worse than useless,
        // since it would drag the score toward whatever the room sounds like. Whether that's
        // happening can only be judged after onset detection: it compares the RMS inside the
        // mic's own tap windows against the RMS of everything else in its buffer (the room),
        // which — unlike a whole-buffer peak/median ratio — is scale-free and does not drift with
        // capture length. Drop the channel and say so when its own taps do not stand out from its
        // own room.
        if let micChannel = mic {
            let micOnsets = chosen.map { convert($0, to: micChannel.sampleRate) }
            if !Self.hasUsableMicrophoneContrast(
                samples: micChannel.samples, onsets: micOnsets, sampleRate: micChannel.sampleRate
            ) {
                mic = nil
                lastWarning = accel == nil
                    ? "Too noisy here, and no vibration sensor. Try somewhere quieter."
                    : "Too noisy for the microphone. Scoring on vibration alone."
            }
        }

        guard accel != nil || mic != nil else {
            state = .failed(CaptureError.bothChannelsFailed.errorDescription!)
            return
        }

        let taps: [TapFeatures] = chosen.map { onset in
            let accelFeatures = accel.flatMap { channel -> ChannelFeatures? in
                let window = OnsetDetector.window(at: onset, in: channel.samples, sampleRate: channel.sampleRate)
                return FeatureExtractor.extract(from: window, sampleRate: channel.sampleRate)
            }
            let micFeatures = mic.flatMap { channel -> ChannelFeatures? in
                let converted = convert(onset, to: channel.sampleRate)
                let window = OnsetDetector.window(at: converted, in: channel.samples, sampleRate: channel.sampleRate)
                return FeatureExtractor.extract(from: window, sampleRate: channel.sampleRate)
            }
            return TapFeatures(microphone: micFeatures, accelerometer: accelFeatures)
        }

        do {
            let score = try scorer.score(taps: taps)
            let accelFileURL = accel.flatMap { writeAccelerometer($0.samples) }
            let captured = CapturedMelon(
                id: UUID(),
                sessionID: sessionID,
                capturedAt: Date(),
                taps: taps,
                score: score,
                audioFileURL: mic?.fileURL,
                accelerometerFileURL: accelFileURL
            )
            melons.append(captured)
            WatchSyncService.shared.send(captured)
            state = .scored(captured)
        } catch ScoringError.insufficientTaps(let found, let required) {
            state = .failed("Only \(found) of \(required) taps were usable. Try again.")
        } catch {
            state = .failed("Could not score this melon. Try again.")
        }
    }

    /// True when a channel's own detected tap windows are louder, in RMS, than the rest of its
    /// own buffer by at least `AnalysisConstants.minimumTapWindowToRoomRmsRatio`. `onsets` must
    /// already be in `samples`'s own timebase (see `convert(_:to:)` in `analyse`).
    ///
    /// This measures "are the taps above the room" directly, rather than a whole-buffer
    /// peak/median ratio, which for pure noise grows with sample count instead of staying fixed —
    /// see the doc comment on `minimumTapWindowToRoomRmsRatio` for the numbers.
    private static func hasUsableMicrophoneContrast(
        samples: [Float], onsets: [Onset], sampleRate: Double
    ) -> Bool {
        guard !onsets.isEmpty else { return false }

        var inWindow = [Bool](repeating: false, count: samples.count)
        for onset in onsets {
            let window = OnsetDetector.window(at: onset, in: samples, sampleRate: sampleRate)
            let start = min(max(onset.sampleIndex, 0), samples.count)
            let end = min(start + window.count, samples.count)
            guard start < end else { continue }
            for index in start..<end { inWindow[index] = true }
        }

        var tapSumSquares: Double = 0
        var tapCount = 0
        var roomSumSquares: Double = 0
        var roomCount = 0
        for (index, sample) in samples.enumerated() {
            let value = Double(sample)
            if inWindow[index] {
                tapSumSquares += value * value
                tapCount += 1
            } else {
                roomSumSquares += value * value
                roomCount += 1
            }
        }
        // Fewer than 32 room samples means there isn't enough of the buffer left outside the tap
        // windows to know what the room sounds like — too little evidence to trust the channel.
        guard tapCount > 0, roomCount > 32 else { return false }

        let tapRms = (tapSumSquares / Double(tapCount)).squareRoot()
        let roomRms = max((roomSumSquares / Double(roomCount)).squareRoot(), 1e-9)
        return Float(tapRms / roomRms) >= AnalysisConstants.minimumTapWindowToRoomRmsRatio
    }

    /// Persists the raw accelerometer magnitudes so a better extractor can revisit them later.
    private func writeAccelerometer(_ samples: [Float]) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("melon-accel-\(UUID().uuidString).bin")
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return (try? data.write(to: url)) == nil ? nil : url
    }
}
