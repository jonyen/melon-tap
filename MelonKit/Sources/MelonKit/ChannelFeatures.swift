import Foundation

/// Everything the pipeline measures from one tap on one channel.
/// Wire format between Watch and phone, so the property names are part of the sync contract.
public struct ChannelFeatures: Codable, Equatable, Sendable {

    /// Dominant frequency within the 20–400 Hz analysis band, in Hz. Riper melons peak lower.
    public let peakFrequencyHz: Float

    /// Magnitude-weighted mean frequency within the band, in Hz.
    public let spectralCentroidHz: Float

    /// Envelope decay in nepers per second, fitted to the log of the frame RMS. Riper melons damp faster.
    public let decayRatePerSecond: Float

    /// Energy in 20–150 Hz over energy in 150–400 Hz. Riper melons skew low.
    public let lowHighEnergyRatio: Float

    public init(
        peakFrequencyHz: Float,
        spectralCentroidHz: Float,
        decayRatePerSecond: Float,
        lowHighEnergyRatio: Float
    ) {
        self.peakFrequencyHz = peakFrequencyHz
        self.spectralCentroidHz = spectralCentroidHz
        self.decayRatePerSecond = decayRatePerSecond
        self.lowHighEnergyRatio = lowHighEnergyRatio
    }
}
