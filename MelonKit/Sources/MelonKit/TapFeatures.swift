import Foundation

/// One tap, measured on up to two channels. Either channel may be absent — the microphone
/// when the store is too loud, the accelerometer on hardware older than Series 8.
public struct TapFeatures: Codable, Equatable, Sendable {

    public let microphone: ChannelFeatures?
    public let accelerometer: ChannelFeatures?

    public init(microphone: ChannelFeatures?, accelerometer: ChannelFeatures?) {
        self.microphone = microphone
        self.accelerometer = accelerometer
    }
}
