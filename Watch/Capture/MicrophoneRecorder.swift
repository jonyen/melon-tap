import AVFoundation
import Foundation
import MelonKit

/// Accumulates samples appended from the audio tap's render-thread callback while also being
/// read back from the main actor. `samples` is plain (non-actor, non-Sendable-checked) mutable
/// state shared across those two threads, so every access goes through `lock` — an `NSLock`
/// guards both the tap's `append` and the final `snapshot`, giving the reader a proper
/// happens-before relationship with every write instead of racing the render thread.
private final class LockedSampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func reserveCapacity(_ minimumCapacity: Int) {
        lock.lock()
        defer { lock.unlock() }
        samples.reserveCapacity(minimumCapacity)
    }

    func append(_ pointer: UnsafeBufferPointer<Float>) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: pointer)
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

/// Carries the `AVAudioFile` into the tap's render-thread callback. `AVAudioFile` is not
/// Sendable, but after creation it is written from exactly one place — the tap callback, which
/// AVFAudio invokes serially on its own queue — and read again only after `removeTap` has
/// synchronously guaranteed no further callbacks, so every access is ordered.
private final class TapAudioFile: @unchecked Sendable {
    let file: AVAudioFile
    init(_ file: AVAudioFile) { self.file = file }
}

/// Captures watch microphone audio into memory and, in parallel, to a file for later re-analysis.
@MainActor
final class MicrophoneRecorder {

    /// Result of the last `prepareForRecording()`, consumed by `record(duration:)`. `nil` means
    /// `prepareForRecording()` has not run yet this capture.
    private var permissionGranted: Bool?
    /// The in-flight capture's buffer and rate, published while `record(duration:)` runs so the
    /// coordinator's live tap monitor can peek at partial audio. `nil` outside a capture.
    private var liveBuffer: (samples: LockedSampleBuffer, sampleRate: Double)?
    /// Set by `finishEarly()`; the wait loop in `record(duration:)` checks it each slice.
    private var stopEarly = false
    /// Set when `prepareForRecording()`'s own `setCategory`/`setActive` throws, so `record`
    /// can surface it instead of silently proceeding on a session that was never activated.
    private var sessionPrepareError: Error?

    /// Requests microphone permission and activates the audio session, both ahead of time.
    ///
    /// `CaptureCoordinator.capture()` calls this once, before it starts the accelerometer and
    /// microphone recording concurrently. `AVAudioApplication.requestRecordPermission()` suspends
    /// for as long as the user takes to answer the system dialog on first launch — unbounded —
    /// and running that inside the concurrent section let the accelerometer record its whole
    /// capture window while the microphone had not even started. Resolving permission and
    /// warming the session here means the concurrent section contains only the two
    /// `record(duration:)` calls, with no unbounded suspension on either side of the race.
    ///
    /// Safe to call more than once: the OS only ever shows the permission dialog once and
    /// returns immediately on every later call, and activating an already-active session is a
    /// cheap no-op.
    func prepareForRecording() async {
        // AVAudioApplication is the watchOS 11 permission API. AVAudioSession.requestRecordPermission
        // is deprecated and would emit a warning.
        permissionGranted = await AVAudioApplication.requestRecordPermission()
        guard permissionGranted == true else {
            sessionPrepareError = nil
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            sessionPrepareError = nil
        } catch {
            sessionPrepareError = error
        }
    }

    func record(duration: Double) async throws -> (samples: [Float], sampleRate: Double, fileURL: URL) {
        // Normally already resolved by `prepareForRecording()`, called ahead of time by
        // `CaptureCoordinator.capture()` before either recorder starts. Falling back here keeps
        // this method correct on its own — for direct callers, tests, and so on.
        if permissionGranted == nil {
            await prepareForRecording()
        }
        guard permissionGranted == true else { throw CaptureError.microphoneDenied }
        if let sessionPrepareError { throw sessionPrepareError }

        let session = AVAudioSession.sharedInstance()
        // Guarantees the session — activated by `prepareForRecording()` above — is deactivated
        // on every exit from here on, not just the happy path.
        defer { try? session.setActive(false) }

        // A fresh engine per capture, not one shared across the recorder's lifetime: reusing a
        // stopped engine's input node for a later capture can abort inside AudioToolbox
        // (AURemoteIO::Cleanup RPC timeout) when the audio server has torn down the remote IO
        // unit between captures.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Use the hardware's own format. Watch microphones do not all run at the same rate,
        // and resampling here would only add error.
        let format = input.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("melon-\(UUID().uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        // Mutated from the tap's render-thread callback below and read back after teardown;
        // `LockedSampleBuffer` synchronizes both sides.
        let samples = LockedSampleBuffer()
        samples.reserveCapacity(Int(duration * sampleRate))
        stopEarly = false
        liveBuffer = (samples, sampleRate)
        defer { liveBuffer = nil }

        // The tap callback runs on AVFAudio's own queue, never the main actor. Without the
        // explicit @Sendable it would inherit this method's @MainActor isolation, and the Swift 6
        // runtime's isolation check would trap (dispatch_assert_queue_fail) on the first buffer.
        let tapFile = TapAudioFile(file)
        input.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(AnalysisConstants.microphoneTapBufferFrames),
            format: format
        ) { @Sendable buffer, _ in
            do {
                try tapFile.file.write(from: buffer)
            } catch {
                print("MicrophoneRecorder: failed to write audio buffer to file: \(error)")
            }
            guard let channel = buffer.floatChannelData?[0] else { return }
            samples.append(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        // Guarantees the tap and engine are torn down on every exit from here on — a thrown
        // error from engine.start(), or Task cancellation during the sleep below — not just
        // the happy path. An orphaned tap/engine would corrupt the next capture attempt. Also a
        // safety net for the happy path below: `removeTap`/`stop` are idempotent, so this firing
        // again after they have already run explicitly is harmless.
        defer {
            input.removeTap(onBus: 0)
            engine.stop()
        }

        engine.prepare()
        try engine.start()
        // Sliced rather than one long sleep so `finishEarly()` — set by the coordinator's live
        // tap monitor once enough taps are in — can end the capture within a slice instead of
        // holding the user for the full window.
        let sliceSeconds = 0.1
        var elapsed = 0.0
        while elapsed < duration && !stopEarly {
            try await Task.sleep(for: .seconds(min(sliceSeconds, duration - elapsed)))
            elapsed += sliceSeconds
        }

        // Swift evaluates a `return` expression's operands *before* running `defer` blocks, so
        // reading `samples` here would race the tap's render-thread callback if teardown were
        // left to the `defer` above. Tear down explicitly first — `removeTap` synchronously
        // guarantees no further callback invocations — so the snapshot below is race-free.
        input.removeTap(onBus: 0)
        engine.stop()

        return (samples.snapshot(), sampleRate, url)
    }

    /// Snapshot of the audio captured so far in the current `record(duration:)` call, for live
    /// onset detection. `nil` when no capture is running.
    func liveCapture() -> (samples: [Float], sampleRate: Double)? {
        liveBuffer.map { ($0.samples.snapshot(), $0.sampleRate) }
    }

    /// Asks the in-flight `record(duration:)` to return at the next slice boundary (≤0.1 s away)
    /// instead of running out its full window. No-op when no capture is running.
    func finishEarly() {
        stopEarly = true
    }
}
