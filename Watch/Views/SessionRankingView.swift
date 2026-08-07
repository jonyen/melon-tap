import SwiftUI

struct SessionRankingView: View {

    let coordinator: CaptureCoordinator

    var body: some View {
        List {
            ForEach(Array(coordinator.ranked.enumerated()), id: \.element.id) { index, melon in
                HStack {
                    Text("\(index + 1)")
                        .font(.headline)
                        .foregroundStyle(index == 0 ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(String(format: "%.2f", melon.score.value))
                            .font(.body)
                        Text("\(melon.score.tapsUsed) taps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Ripest First")
    }
}
