import Charts
import MelonKit
import SwiftUI

/// Plots each tap's measured features — this is not a frequency spectrum. The raw signal only
/// reaches the phone as a file that may not have transferred yet (or ever), while the features
/// extracted from it on the Watch are always present. So this chart, not an FFT plot, is what
/// "inspecting the physics" means in this app: how each tap's peak frequency and spectral
/// centroid compare, so an odd melon can be diagnosed by eye.
struct SpectrumChart: View {

    let title: String
    let channels: [ChannelFeatures]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            if channels.isEmpty {
                Text("Not recorded on this channel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(Array(channels.enumerated()), id: \.offset) { index, features in
                        BarMark(
                            x: .value("Tap", "Tap \(index + 1)"),
                            y: .value("Peak Hz", features.peakFrequencyHz)
                        )
                        .foregroundStyle(by: .value("Feature", "Peak Hz"))

                        BarMark(
                            x: .value("Tap", "Tap \(index + 1)"),
                            y: .value("Centroid Hz", features.spectralCentroidHz)
                        )
                        .foregroundStyle(by: .value("Feature", "Centroid Hz"))
                    }
                }
                .frame(height: 160)

                ForEach(Array(channels.enumerated()), id: \.offset) { index, features in
                    Text(String(
                        format: "Tap %d — peak %.0f Hz, centroid %.0f Hz, decay %.1f/s, low:high %.2f",
                        index + 1,
                        features.peakFrequencyHz,
                        features.spectralCentroidHz,
                        features.decayRatePerSecond,
                        features.lowHighEnergyRatio
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
