import Foundation

/// Both raw streams from one melon capture, before any feature extraction.
struct RawCapture {
    let accelerometer: [Float]?
    let accelerometerSampleRate: Double
    let microphone: [Float]?
    let microphoneSampleRate: Double
    /// On-disk copy of the audio, kept for re-analysis with a better extractor later.
    let audioFileURL: URL?
    /// On-disk copy of the accelerometer magnitudes, same reason.
    let accelerometerFileURL: URL?
}

enum CaptureError: LocalizedError, Equatable {
    case highRateMotionUnavailable
    case healthKitDenied
    case microphoneDenied
    case bothChannelsFailed

    var errorDescription: String? {
        switch self {
        case .highRateMotionUnavailable:
            return "This Watch does not support high-rate motion. Recording sound only."
        case .healthKitDenied:
            return "Workout permission is needed for the vibration sensor. Recording sound only."
        case .microphoneDenied:
            return "Microphone access denied. Recording vibration only."
        case .bothChannelsFailed:
            return "Could not record. Grant permissions in Watch → Melon Tap on your iPhone."
        }
    }
}
