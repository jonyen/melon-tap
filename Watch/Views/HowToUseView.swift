import SwiftUI

/// In-store instructions, kept short enough to read on a wrist while holding a melon.
/// The longer explanation of why ranking is per-bin lives on the phone.
struct HowToUseView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                step(
                    number: 1,
                    title: "Press the watch to the rind",
                    detail: "Flat against the melon, firm but not hard. The watch feels the vibration through its case."
                )

                step(
                    number: 2,
                    title: "Tap Melon, then knuckle-tap 3 times",
                    detail: "Tap beside the watch, about one tap per second, while the countdown runs. Same spot, same force each time."
                )

                step(
                    number: 3,
                    title: "Read the score",
                    detail: "Higher means riper. The rank shows where this melon placed against the others from this bin."
                )

                step(
                    number: 4,
                    title: "Tap 3 to 5 melons from the same bin",
                    detail: "The score only means something compared with other melons of a similar size. Use New Bin when you move to a different pile."
                )

                step(
                    number: 5,
                    title: "Label it after you cut it",
                    detail: "On your iPhone, mark how the melon actually turned out. That is what makes the scoring better over time."
                )

                Divider()

                Text("If it says only 1 or 2 taps were detected, tap more firmly and leave a clear gap between taps.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("How to Use")
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.green)
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
