import SwiftData
import SwiftUI

struct SessionListView: View {

    @Query(sort: \MelonSession.startedAt, order: .reverse)
    private var sessions: [MelonSession]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    Section(session.startedAt.formatted(date: .abbreviated, time: .shortened)) {
                        ForEach(Array(session.ranked.enumerated()), id: \.element.id) { index, melon in
                            NavigationLink {
                                // TASK 11 STUB: MelonDetailView does not exist until Task 11.
                                // Restore this to `MelonDetailView(melon: melon)` when it lands.
                                Text(String(format: "%.2f", melon.scoreValue))
                            } label: {
                                HStack {
                                    Text("\(index + 1)")
                                        .font(.headline)
                                        .foregroundStyle(index == 0 ? .green : .secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading) {
                                        Text(String(format: "Score %.2f", melon.scoreValue))
                                        Text("\(melon.tapsUsed) taps")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let outcome = melon.outcome {
                                        Text(outcome.label)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No melons yet",
                        systemImage: "waveform",
                        description: Text("Capture melons on your Watch and they will appear here.")
                    )
                }
            }
            .navigationTitle("Sessions")
        }
    }
}
