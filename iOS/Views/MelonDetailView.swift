import SwiftData
import SwiftUI

struct MelonDetailView: View {

    @Environment(\.modelContext) private var context
    @Bindable var melon: Melon

    var body: some View {
        Form {
            Section("Score") {
                LabeledContent("Ripeness", value: String(format: "%.3f", melon.scoreValue))
                LabeledContent("Taps used", value: "\(melon.tapsUsed)")
                LabeledContent("Captured", value: melon.capturedAt.formatted())
            }

            Section("What drove the score") {
                ForEach(melon.scoreBreakdown.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    LabeledContent(key, value: String(format: "%.3f", value))
                }
            }

            Section("Microphone") {
                SpectrumChart(title: "Per tap", channels: melon.taps.compactMap(\.microphone))
            }

            Section("Accelerometer") {
                SpectrumChart(title: "Per tap", channels: melon.taps.compactMap(\.accelerometer))
            }

            Section("Outcome") {
                Picker("How it turned out", selection: Binding(
                    get: { melon.outcome },
                    set: { newValue in
                        melon.outcome = newValue
                        saveOutcome()
                    }
                )) {
                    Text("Not cut yet").tag(Optional<Outcome>.none)
                    ForEach(Outcome.allCases) { outcome in
                        Text(outcome.label).tag(Optional(outcome))
                    }
                }
                // `axis: .vertical` makes this a multi-line field, and on a multi-line field the
                // Return key inserts a newline instead of triggering `onSubmit` — so a save that
                // only happened in `onSubmit` would never fire here. Saving in the binding's
                // setter, on every edit, is what actually gets the note to disk.
                TextField("Note", text: Binding(
                    get: { melon.note ?? "" },
                    set: { newValue in
                        melon.note = newValue.isEmpty ? nil : newValue
                        saveNote()
                    }
                ), axis: .vertical)
            }

            Section("Raw signals") {
                LabeledContent("Audio", value: melon.audioFileName ?? "Not transferred")
                LabeledContent("Vibration", value: melon.accelerometerFileName ?? "Not transferred")
            }
        }
        .navigationTitle("Melon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveOutcome() {
        do {
            try context.save()
        } catch {
            print("MelonDetailView: failed to save outcome for melon \(melon.id): \(error)")
        }
    }

    private func saveNote() {
        do {
            try context.save()
        } catch {
            print("MelonDetailView: failed to save note for melon \(melon.id): \(error)")
        }
    }
}
