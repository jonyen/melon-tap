import SwiftUI

/// The long-form explanation: what the app measures, why melons are only ever ranked
/// against others from the same bin, and why the outcome labels matter.
/// The terse in-store version lives on the Watch.
struct HowItWorksView: View {

    var body: some View {
        NavigationStack {
            List {
                Section("In the store") {
                    numbered(1, "Press the watch face flat against the rind — firm, but you are not trying to squash it.")
                    numbered(2, "Tap Melon on the watch, then knuckle-tap the melon three times beside the watch, about one tap per second, while the countdown runs.")
                    numbered(3, "The watch shows a score and a rank. Higher means riper.")
                    numbered(4, "Tap three to five melons from the same bin, then buy the top-ranked one.")
                    numbered(5, "Tap New Bin on the watch when you move to a different pile.")
                }

                Section("At home") {
                    Text("After you cut a melon, open the To Label tab and record how it actually turned out — ripe, unripe, overripe, or mushy.")
                    Text("This is the part that makes the app worth using. Every score it produces today is based on untested guesses; your labels are the only thing that can prove them right or wrong.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Why it ranks instead of just telling you") {
                    Text("A melon's pitch depends on its size as much as its ripeness. A large ripe melon and a small unripe one can ring at the same note, so an absolute \"this one is ripe\" verdict would need to know the melon's mass and a calibration nobody has published.")
                    Text("Melons in one bin are usually the same variety and a similar size, so comparing them against each other mostly cancels that out. That is why the app never says a melon is ripe — only which of the ones you tapped is most likely the ripest.")
                }

                Section("What it measures") {
                    labelled("Pitch", "Riper flesh is softer and resonates lower.")
                    labelled("Decay", "Riper flesh damps the thump faster.")
                    labelled("Tone", "Riper flesh puts more energy in the low frequencies.")
                    Text("Two channels are recorded at once: the microphone hears the thump, and the watch's accelerometer feels the vibration through the case. The vibration channel is the unusual one — it ignores store noise, and no other app uses it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("When it complains") {
                    labelled("Only 1 or 2 taps detected", "Tap more firmly, and leave a clear gap between taps.")
                    labelled("Too noisy for the microphone", "It scored on vibration alone. That is fine.")
                    labelled("No vibration sensor", "The high-rate motion sensor needs an Apple Watch Series 8 or later, and permission to start a workout session. Nothing is saved to Health.")
                }
            }
            .navigationTitle("How It Works")
        }
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.green)
                .frame(width: 16, alignment: .leading)
            Text(text)
        }
    }

    private func labelled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
