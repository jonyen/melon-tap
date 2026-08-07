import Foundation

/// Every tunable number used by the signal pipeline. Retuning happens here and nowhere else.
public enum AnalysisConstants {

    // MARK: Analysis band

    /// Lowest frequency considered. Below this is body movement and handling noise.
    public static let bandLowHz: Float = 20

    /// Highest frequency considered. Also the Nyquist limit of the 800 Hz accelerometer stream.
    public static let bandHighHz: Float = 400

    /// Boundary between the low and high sub-bands used by the energy ratio feature.
    public static let subBandSplitHz: Float = 150

    /// Shortest window the spectrum transform will accept.
    public static let minimumSpectrumSamples: Int = 16

    // MARK: Onset detection

    /// Length of the RMS analysis frame, in seconds.
    public static let onsetFrameSeconds: Double = 0.005

    /// Hop between successive RMS frames, in seconds.
    public static let onsetHopSeconds: Double = 0.0025

    /// An onset's energy rise must exceed the median frame-to-frame energy step by this many
    /// median-absolute-deviations of that step size to register as a tap attack. Calibrated
    /// (not the original 6) by sweeping synthetic taps across the full decayRateReferenceRange
    /// and a wide range of inter-tap gaps at both 800 Hz and 44.1 kHz, plus repeated
    /// capture-length pure-noise buffers at several amplitudes and seeds: 6 let noise-driven
    /// jitter through unpredictably as buffer length grew (more frames means more chances for a
    /// rare exceedance), 7 was still inconsistent, and 8 was the smallest factor with zero false
    /// positives across that noise sweep while still catching every synthetic tap in the grid.
    public static let onsetThresholdFactor: Float = 8

    /// Minimum time between two accepted onsets. Rejects the ring-out of a tap being read as a second tap.
    public static let onsetMinimumSeparationSeconds: Double = 0.12

    /// Length of signal analysed after each onset, in seconds.
    public static let tapWindowSeconds: Double = 0.25

    // MARK: Decay analysis

    /// Minimum frame length for RMS calculation, in samples. Floors the computed length to avoid tiny frames.
    public static let minimumFrameLengthSamples: Int = 8

    /// Minimum hop between successive RMS frames, in samples. Floors the computed hop to avoid zero-width steps.
    public static let minimumHopSamples: Int = 4

    /// Silence threshold for frame energy. Frames with RMS below this are excluded from decay analysis.
    public static let decayRmsFloor: Float = 1e-7

    /// Minimum fit points for decay linear regression. Requires at least this many frames after the peak to ensure a valid fit.
    public static let decayMinimumFitPoints: Int = 3

    // MARK: Capture

    /// Total capture duration on the Watch, in seconds.
    public static let captureDurationSeconds: Double = 4.0

    /// Required number of clean taps per melon. Fewer means refuse to score.
    public static let requiredTapCount: Int = 3

    /// A channel's loudest sample must exceed its median sample level by this factor to be
    /// trusted. Below it, the taps are buried in ambient noise and the channel is discarded.
    public static let minimumTapToNoiseRatio: Float = 4

    /// Frame count per `AVAudioEngine` tap buffer while recording the microphone. Larger buffers
    /// reduce callback overhead at the cost of latency between the sound and its capture.
    public static let microphoneTapBufferFrames: Int = 4096

    // MARK: Scoring

    /// Peak frequency range used to normalise that feature to 0...1. Lower peak reads as riper.
    public static let peakFrequencyReferenceRange: ClosedRange<Float> = 60...300

    /// Decay rate range, in nepers per second, used to normalise that feature. Faster decay reads as riper.
    public static let decayRateReferenceRange: ClosedRange<Float> = 5...80

    /// Low-over-high energy ratio range used to normalise that feature. More low energy reads as riper.
    public static let lowHighRatioReferenceRange: ClosedRange<Float> = 0.2...6

    /// Weights within a single channel. Must sum to 1.
    public static let peakFrequencyWeight: Float = 0.5
    public static let decayRateWeight: Float = 0.3
    public static let lowHighRatioWeight: Float = 0.2

    /// Weight given to the accelerometer channel when both channels are present.
    /// UNVALIDATED: contact vibration is assumed more reliable than the microphone in a noisy store.
    /// Revisit once logged melons have outcome labels.
    public static let accelerometerChannelWeight: Float = 0.65

    /// How far a tap's combined score (itself on the 0...1 scale) must sit from the median of
    /// the other taps before it is treated as a mishit and dropped. Below this, taps are
    /// treated as ordinary capture noise and all are kept. Chosen with margin on both sides of
    /// what's actually observed: three consistent taps deviate by 0, a genuine mishit (e.g. a
    /// tap caught on the rind edge instead of the flesh) deviates by roughly 0.68 in the
    /// reference fixture, and 0.15 sits well inside that gap.
    public static let outlierDeviationThreshold: Float = 0.15
}
