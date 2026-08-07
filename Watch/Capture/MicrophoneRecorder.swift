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

        engine.prepare()
        try engine.start()
        try await Task.sleep(for: .seconds(duration))

        input.removeTap(onBus: 0)
        engine.stop()
        try? session.setActive(false)

        return (samples, sampleRate, url)
    }
}
