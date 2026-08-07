import Foundation
import MelonKit
import Observation
import WatchConnectivity

/// Wire format between Watch and phone. Must stay byte-identical to the Watch's copy in
/// `Watch/Sync/WatchSyncService.swift`.
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
}

/// Receives melons from the Watch. Delivers payloads through `onMelonReceived` so that the
/// SwiftData layer, not this service, decides how they are stored.
///
/// Isolated to the main actor: `receivedMelons` and the two callback properties are all
/// main-actor-isolated stored state, so the compiler — not a doc comment — rejects any off-main
/// read or write of them, including an off-main assignment of `onMelonReceived` or
/// `onFileReceived`. `WCSession` invokes its delegate methods off the main thread, so each one is
/// `nonisolated` and does only thread-agnostic work (decoding, file I/O) before hopping to the
/// main actor via `Task { @MainActor in ... }` to touch the actor-isolated state above.
@MainActor
@Observable
final class PhoneSyncService: NSObject, WCSessionDelegate {

    static let shared = PhoneSyncService()

    private(set) var receivedMelons: [MelonPayload] = []

    /// Set by the app on launch. Called on the main actor for every melon that arrives.
    var onMelonReceived: (@MainActor (MelonPayload) -> Void)?

    /// Called for every raw file that lands, with the melon it belongs to.
    var onFileReceived: (@MainActor (UUID, URL) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private nonisolated func handle(_ message: [String: Any]) {
        guard let data = message["melon"] as? Data,
              let payload = try? JSONDecoder().decode(MelonPayload.self, from: data) else { return }
        Task { @MainActor in
            self.receivedMelons.append(payload)
            self.onMelonReceived?(payload)
        }
    }

    /// Removes and returns every melon received since the last drain.
    ///
    /// WatchConnectivity considers a `sendMessage`/`transferUserInfo` delivery complete once
    /// `onMelonReceived` returns, whether or not it actually persisted anything — so a payload
    /// that hits `MelonTapApp.configureSync()`'s fail-closed `catch` (a fetch failure that
    /// leaves a duplicate un-rule-out-able) is otherwise gone for good; the Watch never
    /// redelivers it. `receivedMelons` already holds every payload that has arrived, so draining
    /// it here and replaying each through `onMelonReceived` gives that dropped payload another
    /// chance, at a moment (scene becoming active) when a transient fetch failure is more likely
    /// to have cleared. Replaying an already-persisted melon is a harmless no-op:
    /// `onMelonReceived` fetches for an existing row with the same id first and returns early
    /// when it finds one.
    func drainReceivedMelons() -> [MelonPayload] {
        defer { receivedMelons.removeAll() }
        return receivedMelons
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let idString = file.metadata?["melonID"] as? String,
              let id = UUID(uuidString: idString) else { return }

        // The received file is deleted as soon as this delegate returns, so it must be copied now.
        let destination = URL.documentsDirectory
            .appendingPathComponent(file.fileURL.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        // If the copy fails (disk full, permissions), the file is simply not delivered — logged
        // here so the loss is visible rather than silent.
        guard (try? FileManager.default.copyItem(at: file.fileURL, to: destination)) != nil else {
            print("PhoneSyncService: failed to copy received file for melon \(id)")
            return
        }

        Task { @MainActor in
            self.onFileReceived?(id, destination)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
