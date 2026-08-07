import MelonKit
import SwiftUI

struct CaptureView: View {

    @State private var coordinator = CaptureCoordinator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                switch coordinator.state {
                case .idle:
                    captureButton

                case .preparing:
                    ProgressView("Get Ready")

                case .recording(let start):
                    VStack(spacing: 4) {
                        ProgressView(
                            timerInterval: start...start.addingTimeInterval(AnalysisConstants.captureDurationSeconds)
                        )
                        .progressViewStyle(.circular)
                        Text("Tap 3 times")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .analysing:
                    ProgressView("Scoring")

                case .scored(let melon):
                    VStack(spacing: 4) {
                        Text(String(format: "%.2f", melon.score.value))
                            .font(.system(.title, design: .rounded, weight: .bold))
                        // A safe lookup, not a force unwrap: `melon` was just appended to
                        // `coordinator.melons` before this state was set, but deriving the rank
                        // from an index-into-a-just-mutated-collection should not crash the
                        // capture flow on any future refactor that breaks that ordering.
                        if let rank = coordinator.ranked.firstIndex(where: { $0.id == melon.id }) {
                            Text("#\(rank + 1) of \(coordinator.ranked.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    captureButton

                case .failed(let message):
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await coordinator.capture() }
                    }
                }

                if let warning = coordinator.lastWarning {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !coordinator.melons.isEmpty {
                    NavigationLink("Ranking (\(coordinator.melons.count))") {
                        SessionRankingView(coordinator: coordinator)
                    }
                }

                // Always reachable: the screen scrolls, and the one time you need
                // the instructions is mid-aisle with a melon in your other hand.
                NavigationLink {
                    HowToUseView()
                } label: {
                    Label("How to Use", systemImage: "questionmark.circle")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Melon Tap")
            .toolbar {
                if !coordinator.melons.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Bin") { coordinator.startNewSession() }
                    }
                }
            }
        }
    }

    private var captureButton: some View {
        Button {
            Task { await coordinator.capture() }
        } label: {
            Label("Tap Melon", systemImage: "waveform")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}
