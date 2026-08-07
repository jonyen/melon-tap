import AVFoundation
import Foundation
import MelonKit

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

        // Mutated from the tap's render-thread callback below, read here only after
        // `removeTap` has synchronously guaranteed no further callback invocations.
        var samples: [Float] = []
        samples.reserveCapacity(Int(duration * sampleRate))

        input.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(AnalysisConstants.microphoneTapBufferFrames),
            format: format
        ) { buffer, _ in
            try? file.write(from: buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        // Guarantees the tap and engine are torn down on every exit from here on — a thrown
        // error from engine.start(), or Task cancellation during the sleep below — not just
        // the happy path. An orphaned tap/engine would corrupt the next capture attempt.
        defer {
            input.removeTap(onBus: 0)
            engine.stop()
        }

        engine.prepare()
        try engine.start()
        try await Task.sleep(for: .seconds(duration))

        return (samples, sampleRate, url)
    }
}
