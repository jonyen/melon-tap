import Foundation

/// A melon's ripeness estimate. Higher is riper. Only meaningful compared against other
/// melons scored in the same session — see the size confound in the design spec.
public struct RipenessScore: Codable, Equatable, Sendable {

    /// 0...1, higher meaning riper.
    public let value: Float

    /// Per-channel and per-feature contributions, so the number can be inspected rather than trusted.
    public let breakdown: [String: Float]

    /// How many taps survived outlier rejection.
    public let tapsUsed: Int

    public init(value: Float, breakdown: [String: Float], tapsUsed: Int) {
        self.value = value
        self.breakdown = breakdown
        self.tapsUsed = tapsUsed
    }
}

public enum ScoringError: Error, Equatable {
    /// Fewer clean taps than required. Never scored partially.
    case insufficientTaps(found: Int, required: Int)
    /// Every tap arrived with both channels missing.
    case noUsableChannels
}

/// Anything that turns a melon's taps into a score. `PhysicsScorer` is the only implementation
/// today; a nearest-neighbour scorer over labelled melons and a Core ML model are the planned successors.
public protocol RipenessScorer: Sendable {
    func score(taps: [TapFeatures]) throws -> RipenessScore
}
