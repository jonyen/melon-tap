import SwiftUI

@main
struct MelonTapWatchApp: App {
    init() {
        // Starts WCSession activation at launch rather than at the first captured melon. If the
        // service were touched for the first time inside CaptureCoordinator instead, `activate()`
        // (asynchronous) and the first `send(_:)` (synchronous, no suspension point between them)
        // would land in the same main-actor turn, sending on a session that has not finished
        // activating. Touching `shared` here gives activation the whole app lifetime to complete
        // before any melon can be captured.
        _ = WatchSyncService.shared
    }

    var body: some Scene {
        WindowGroup {
            CaptureView()
        }
    }
}
