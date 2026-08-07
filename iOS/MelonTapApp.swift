import SwiftData
import SwiftUI

@main
struct MelonTapApp: App {

    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: MelonSession.self, Melon.self)
        } catch {
            fatalError("Could not open the melon archive: \(error)")
        }
        configureSync()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                SessionListView()
                    .tabItem { Label("Sessions", systemImage: "list.bullet") }
                UnlabeledMelonsView()
                    .tabItem { Label("To Label", systemImage: "questionmark.circle") }
                HowItWorksView()
                    .tabItem { Label("How It Works", systemImage: "book") }
            }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            // Retry any melon that arrived while the app could not rule out a duplicate (see
            // `PhoneSyncService.drainReceivedMelons()`) every time the app comes back to the
            // foreground, not just once at launch — the scene can go active many times over the
            // app's life, and each is a fresh chance for a transient fetch failure to have
            // cleared.
            if newPhase == .active {
                for payload in PhoneSyncService.shared.drainReceivedMelons() {
                    PhoneSyncService.shared.onMelonReceived?(payload)
                }
            }
        }
    }

    /// Melons arriving from the Watch are grouped primarily by `payload.sessionID`, the user's
    /// explicit "New Bin" boundary: the session already carrying that id, or a new session minted
    /// for it if none exists yet. This is what actually enforces the app's core premise — melons
    /// are only ever ranked against others from the same bin — because unlike the fallback below
    /// it cannot merge or split a bin visit based on timing.
    ///
    /// Only a payload with no session id (queued on the Watch before this field existed) falls
    /// back to proximity: the nearest session whose `startedAt` is within `sessionGapSeconds` of
    /// `payload.capturedAt` in either direction, or a new session if none qualifies. Keying off
    /// the melon's own capture timestamp — not arrival order — matters because `transferUserInfo`
    /// can deliver a melon long after it was captured (phone asleep, out of range); a symmetric,
    /// nearest-session match keeps a late-arriving melon in the bin it was actually captured in
    /// instead of merging into whatever session happens to already exist.
    private func configureSync() {
        let context = container.mainContext

        // `transferFile` and the `sendMessage`/`transferUserInfo` feature payload are independent
        // WatchConnectivity paths with no ordering guarantee between them, so a raw file can land
        // in `onFileReceived` before `onMelonReceived` has inserted the melon it belongs to.
        // Holding it here — keyed by melon id — lets `onMelonReceived` attach it once the melon
        // row exists, instead of the file being silently unattachable because no Melon matched
        // yet.
        var pendingFiles: [UUID: [URL]] = [:]

        func attach(_ url: URL, to melon: Melon) {
            if url.pathExtension == "caf" {
                melon.audioFileName = url.lastPathComponent
            } else {
                melon.accelerometerFileName = url.lastPathComponent
            }
        }

        PhoneSyncService.shared.onMelonReceived = { payload in
            do {
                let existing = try context.fetch(
                    FetchDescriptor<Melon>(predicate: #Predicate { $0.id == payload.id })
                )
                guard existing.isEmpty else { return }

                let melon = Melon.make(from: payload)

                if let sessionID = payload.sessionID {
                    let matches = try context.fetch(
                        FetchDescriptor<MelonSession>(
                            predicate: #Predicate { $0.sessionID == sessionID }
                        )
                    )
                    if let match = matches.first {
                        melon.session = match
                    } else {
                        let session = MelonSession(startedAt: payload.capturedAt, sessionID: sessionID)
                        context.insert(session)
                        melon.session = session
                    }
                } else {
                    let gap = MelonSession.sessionGapSeconds
                    let lowerBound = payload.capturedAt.addingTimeInterval(-gap)
                    let upperBound = payload.capturedAt.addingTimeInterval(gap)
                    let candidates = try context.fetch(
                        FetchDescriptor<MelonSession>(
                            predicate: #Predicate { $0.startedAt >= lowerBound && $0.startedAt <= upperBound }
                        )
                    )
                    let nearest = candidates.min {
                        abs($0.startedAt.timeIntervalSince(payload.capturedAt))
                            < abs($1.startedAt.timeIntervalSince(payload.capturedAt))
                    }

                    if let nearest {
                        melon.session = nearest
                    } else {
                        let session = MelonSession(startedAt: payload.capturedAt)
                        context.insert(session)
                        melon.session = session
                    }
                }

                context.insert(melon)

                // Attach any raw files that beat this melon's own feature payload here. Left in
                // `pendingFiles` until the save below actually succeeds — removing it earlier
                // would lose the files for good if `save()` throws, since a retry would find
                // `existing` already non-empty (the melon is in the context from the failed
                // insert) and never reach this attach step again.
                if let files = pendingFiles[payload.id] {
                    for url in files {
                        attach(url, to: melon)
                    }
                }

                try context.save()
                pendingFiles.removeValue(forKey: payload.id)
            } catch {
                // A thrown fetch means a duplicate cannot be ruled out; fail closed rather than
                // risk inserting the same melon twice into a session's ranking.
                print("MelonTapApp: failed to persist received melon \(payload.id): \(error)")
            }
        }

        PhoneSyncService.shared.onFileReceived = { id, url in
            let melons = try? context.fetch(
                FetchDescriptor<Melon>(predicate: #Predicate { $0.id == id })
            )
            guard let melon = melons?.first else {
                // The melon's feature message has not arrived (or been persisted) yet. Hold the
                // file so `onMelonReceived` can attach it once the row exists, rather than
                // dropping it because no Melon matched.
                pendingFiles[id, default: []].append(url)
                return
            }
            attach(url, to: melon)
            do {
                try context.save()
            } catch {
                print("MelonTapApp: failed to save file association for melon \(id): \(error)")
            }
        }
    }
}
