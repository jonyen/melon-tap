import SwiftData
import SwiftUI

/// Melons that have been captured but never cut. One tap records how each one turned out.
struct UnlabeledMelonsView: View {

    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<Melon> { $0.outcomeRaw == nil },
        sort: \Melon.capturedAt,
        order: .reverse
    )
    private var melons: [Melon]

    var body: some View {
        NavigationStack {
            List(melons) { melon in
                VStack(alignment: .leading, spacing: 8) {
                    Text(melon.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                    Text(String(format: "Predicted %.2f", melon.scoreValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach(Outcome.allCases) { outcome in
                            Button(outcome.label) {
                                melon.outcome = outcome
                                try? context.save()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if melons.isEmpty {
                    ContentUnavailableView(
                        "Nothing to label",
                        systemImage: "checkmark.circle",
                        description: Text("Every captured melon has an outcome recorded.")
                    )
                }
            }
            .navigationTitle("To Label")
        }
    }
}
