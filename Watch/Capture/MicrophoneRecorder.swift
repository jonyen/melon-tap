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

/// Captures watch microphone audio into memory and, in parallel, to a file for later re-analysis.
@MainActor
final class MicrophoneRecorder {

    private let engine = AVAudioEngine()

    func record(duration: Double) async throws -> (samples: [Float], sampleRate: Double, fileURL: URL) {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        // Guarantees the session is deactivated on every exit from here on — including the
        // permission-denied throw below — not just the happy path.
        defer { try? session.setActive(false) }

        // AVAudioApplication is the watchOS 11 permission API. AVAudioSession.requestRecordPermission
        // is deprecated and would emit a warning.
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw CaptureError.microphoneDenied }

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

        input.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(AnalysisConstants.microphoneTapBufferFrames),
            format: format
        ) { buffer, _ in
            do {
                try file.write(from: buffer)
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
        try await Task.sleep(for: .seconds(duration))

        // Swift evaluates a `return` expression's operands *before* running `defer` blocks, so
        // reading `samples` here would race the tap's render-thread callback if teardown were
        // left to the `defer` above. Tear down explicitly first — `removeTap` synchronously
        // guarantees no further callback invocations — so the snapshot below is race-free.
        input.removeTap(onBus: 0)
        engine.stop()

        return (samples.snapshot(), sampleRate, url)
    }
}
