import Foundation
import MelonKit
import WatchConnectivity

/// Wire format between Watch and phone. Kept deliberately flat and free of SwiftData or UI types
/// so both sides can decode it without sharing a module.
struct MelonPayload: Codable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let taps: [TapFeatures]
    let scoreValue: Float
    let scoreBreakdown: [String: Float]
    let tapsUsed: Int
    /// File names only. The files themselves arrive separately via `transferFile`.
    let audioFileName: String?
    let accelerometerFileName: String?
}

/// Sends scored melons to the phone. Features go immediately; raw files go opportunistically.
///
/// `@unchecked Sendable`: this class holds no mutable state of its own (`send` only reads its
/// argument and talks to `WCSession`, which is thread-safe), so the `static let shared` singleton
/// required by Swift 6's global-state check is safe without actor isolation.
final class WatchSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchSyncService()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ melon: CapturedMelon) {
        let payload = MelonPayload(
            id: melon.id,
            capturedAt: melon.capturedAt,
            taps: melon.taps,
            scoreValue: melon.score.value,
            scoreBreakdown: melon.score.breakdown,
            tapsUsed: melon.score.tapsUsed,
            audioFileName: melon.audioFileURL?.lastPathComponent,
            accelerometerFileName: melon.accelerometerFileURL?.lastPathComponent
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }
        let message: [String: Any] = ["melon": data]

        // sendMessage is immediate but requires reachability; transferUserInfo queues and
        // survives the phone being in a pocket, asleep, or out of range.
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(message)
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }

        // Raw signals are large. Nothing in the UI waits on these.
        for url in [melon.audioFileURL, melon.accelerometerFileURL].compactMap({ $0 }) {
            WCSession.default.transferFile(url, metadata: ["melonID": melon.id.uuidString])
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
