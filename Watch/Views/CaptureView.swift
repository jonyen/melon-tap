import SwiftUI

struct CaptureView: View {

    @State private var coordinator = CaptureCoordinator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                switch coordinator.state {
                case .idle:
                    Button {
                        Task { await coordinator.capture() }
                    } label: {
                        Label("Tap Melon", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                case .recording:
                    ProgressView("Tap 3 times")
                        .progressViewStyle(.circular)

                case .analysing:
                    ProgressView("Scoring")

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
}
