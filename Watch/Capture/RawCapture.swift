import Foundation

enum CaptureError: LocalizedError, Equatable {
    case highRateMotionUnavailable
    case healthKitDenied
    case microphoneDenied
    case bothChannelsFailed
    /// A failure that isn't one of the specific, expected cases above — a transient CoreMotion
    /// delivery error, an audio-session conflict, task cancellation, and so on. Carries the
    /// underlying error's own description rather than guessing which specific case applies.
    case other(String)

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
        case .other(let message):
            return message
        }
    }
}
