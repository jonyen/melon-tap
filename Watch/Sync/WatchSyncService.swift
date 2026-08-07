import Foundation
import MelonKit
import WatchConnectivity

/// Wire format between Watch and phone. Kept deliberately flat and free of SwiftData or UI types
/// so both sides can decode it without sharing a module.
struct MelonPayload: Codable, Identifiable, Sendable {
    let id: UUID
    /// The bin visit ("New Bin" boundary) this melon was captured under. Optional only so a
    /// payload still in flight through the OS-persisted `transferUserInfo` queue from before this
    /// field existed can still decode; a freshly captured melon always sets it. The phone falls
    /// back to time-proximity grouping when this is nil.
    let sessionID: UUID?
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
/// Isolated to the main actor so the compiler enforces that `shared` and its stored state are
/// only ever touched from one thread — `WCSession` invokes delegate methods off the main thread,
/// so the one delegate method below is `nonisolated` and hops back to the main actor via
/// `Task { @MainActor in ... }` before touching `pending` or `isActivated`.
@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {

    static let shared = WatchSyncService()

    /// True once `activationDidCompleteWith` has reported `.activated`. `activate()` in `init`
    /// is asynchronous, so a melon captured in the same cold-launch turn as `shared` being first
    /// touched would otherwise be transferred on a session that has not finished activating —
    /// `sendMessage`/`transferUserInfo`/`transferFile` all require an activated session, and
    /// `isReachable` also reads false pre-activation, routing straight into the
    /// `transferUserInfo` branch that most explicitly requires it.
    private var isActivated = false

    /// Melons captured before activation completes. Flushed, in order, from
    /// `activationDidCompleteWith` once `isActivated` flips true. Never dropped: losing a
    /// captured melon here is worse than the delay of holding it briefly.
    private var pendingMelons: [CapturedMelon] = []

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ melon: CapturedMelon) {
        guard isActivated else {
            pendingMelons.append(melon)
            return
        }
        transmit(melon)
    }

    private func transmit(_ melon: CapturedMelon) {
        let payload = MelonPayload(
            id: melon.id,
            sessionID: melon.sessionID,
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

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in
            self.isActivated = true
            let queued = self.pendingMelons
            self.pendingMelons.removeAll()
            for melon in queued {
                self.transmit(melon)
            }
        }
    }
}
