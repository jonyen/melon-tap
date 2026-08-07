import Foundation
import MelonKit
import SwiftData

@Model
final class Melon {

    /// Matches the ID assigned on the Watch, so late-arriving raw files can find their melon.
    @Attribute(.unique) var id: UUID

    var capturedAt: Date
    var scoreValue: Float
    var scoreBreakdown: [String: Float]
    var tapsUsed: Int

    /// Features for each tap, stored as encoded JSON because SwiftData cannot persist the
    /// nested optional structs directly.
    var tapsData: Data

    /// File names within the app's documents directory. Nil until the file transfer completes.
    var audioFileName: String?
    var accelerometerFileName: String?

    var note: String?
    var outcomeRaw: String?

    var session: MelonSession?

    init(
        id: UUID,
        capturedAt: Date,
        scoreValue: Float,
        scoreBreakdown: [String: Float],
        tapsUsed: Int,
        tapsData: Data,
        audioFileName: String?,
        accelerometerFileName: String?
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.scoreValue = scoreValue
        self.scoreBreakdown = scoreBreakdown
        self.tapsUsed = tapsUsed
        self.tapsData = tapsData
        self.audioFileName = audioFileName
        self.accelerometerFileName = accelerometerFileName
    }

    var outcome: Outcome? {
        get { outcomeRaw.flatMap(Outcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue }
    }

    var taps: [TapFeatures] {
        (try? JSONDecoder().decode([TapFeatures].self, from: tapsData)) ?? []
    }

    static func make(from payload: MelonPayload) -> Melon {
        Melon(
            id: payload.id,
            capturedAt: payload.capturedAt,
            scoreValue: payload.scoreValue,
            scoreBreakdown: payload.scoreBreakdown,
            tapsUsed: payload.tapsUsed,
            tapsData: (try? JSONEncoder().encode(payload.taps)) ?? Data(),
            audioFileName: payload.audioFileName,
            accelerometerFileName: payload.accelerometerFileName
        )
    }
}
