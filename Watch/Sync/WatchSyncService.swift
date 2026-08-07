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
/// Isolated to the main actor so the compiler enforces that `shared` and any future stored state
/// are only ever touched from one thread — `WCSession` invokes delegate methods off the main
/// thread, so the one delegate method below is `nonisolated` and does no actor-isolated work of
/// its own, since this class carries no mutable state to protect either way.
@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {

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

        // The feature message and the raw file transfers below are independent paths: a failure
        // encoding or sending the message (this `if let`) must not skip the file transfers, and
        // vice versa. They used to share a single `guard let data = ... else { return }`, which
        // meant an encode failure silently dropped the raw files too.
        if let data = try? JSONEncoder().encode(payload) {
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
        }

        // Raw signals are large. Nothing in the UI waits on these, and they are sent
        // unconditionally regardless of whether the feature message above encoded or sent.
        for url in [melon.audioFileURL, melon.accelerometerFileURL].compactMap({ $0 }) {
            WCSession.default.transferFile(url, metadata: ["melonID": melon.id.uuidString])
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
