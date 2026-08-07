import Foundation
import SwiftData

/// One bin visit. Melons are only ever compared against others in the same session, because
/// ranking within a bin is what cancels the size confound.
@Model
final class MelonSession {

    var startedAt: Date

    /// The Watch-minted "New Bin" boundary this session was created for. Nil for a session
    /// created by the time-proximity fallback, for a payload that arrived without a session id.
    var sessionID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \Melon.session)
    var melons: [Melon] = []

    init(startedAt: Date = Date(), sessionID: UUID? = nil) {
        self.startedAt = startedAt
        self.sessionID = sessionID
    }

    var ranked: [Melon] {
        melons.sorted { $0.scoreValue > $1.scoreValue }
    }

    /// Melons captured within this window belong to the same bin visit.
    static let sessionGapSeconds: TimeInterval = 30 * 60
}
