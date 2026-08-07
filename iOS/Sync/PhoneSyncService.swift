import Foundation
import MelonKit
import Observation
import WatchConnectivity

/// Wire format between Watch and phone. Must stay byte-identical to the Watch's copy in
/// `Watch/Sync/WatchSyncService.swift`.
struct MelonPayload: Codable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let taps: [TapFeatures]
    let scoreValue: Float
    let scoreBreakdown: [String: Float]
    let tapsUsed: Int
    let audioFileName: String?
    let accelerometerFileName: String?
}

/// Receives melons from the Watch. Delivers payloads through `onMelonReceived` so that the
/// SwiftData layer, not this service, decides how they are stored.
///
/// `@unchecked Sendable`: the delegate methods below arrive on a WatchConnectivity background
/// queue, not the main thread, but none of them touch `receivedMelons` or invoke the callbacks
/// directly — each hands off to `Task { @MainActor in ... }` first. That funnels every mutation
/// through the main actor, which is what makes the `static let shared` singleton Swift 6 requires
/// safe despite this class not being actor-isolated itself.
@Observable
final class PhoneSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {

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

    private func handle(_ message: [String: Any]) {
        guard let data = message["melon"] as? Data,
              let payload = try? JSONDecoder().decode(MelonPayload.self, from: data) else { return }
        Task { @MainActor in
            self.receivedMelons.append(payload)
            self.onMelonReceived?(payload)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let idString = file.metadata?["melonID"] as? String,
              let id = UUID(uuidString: idString) else { return }

        // The received file is deleted as soon as this delegate returns, so it must be copied now.
        let destination = URL.documentsDirectory
            .appendingPathComponent(file.fileURL.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.copyItem(at: file.fileURL, to: destination)) != nil else { return }

        Task { @MainActor in
            self.onFileReceived?(id, destination)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
