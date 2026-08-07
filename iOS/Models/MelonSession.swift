import Foundation
import SwiftData

/// One bin visit. Melons are only ever compared against others in the same session, because
/// ranking within a bin is what cancels the size confound.
@Model
final class MelonSession {

    var startedAt: Date
    var storeName: String?

    @Relationship(deleteRule: .cascade, inverse: \Melon.session)
    var melons: [Melon] = []

    init(startedAt: Date = Date(), storeName: String? = nil) {
        self.startedAt = startedAt
        self.storeName = storeName
    }

    var ranked: [Melon] {
        melons.sorted { $0.scoreValue > $1.scoreValue }
    }

    /// Melons captured within this window belong to the same bin visit.
    static let sessionGapSeconds: TimeInterval = 30 * 60
}
