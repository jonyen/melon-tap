import SwiftData
import SwiftUI

@main
struct MelonTapApp: App {

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
            }
        }
        .modelContainer(container)
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
                try context.save()
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
            guard let melon = melons?.first else { return }
            if url.pathExtension == "caf" {
                melon.audioFileName = url.lastPathComponent
            } else {
                melon.accelerometerFileName = url.lastPathComponent
            }
            do {
                try context.save()
            } catch {
                print("MelonTapApp: failed to save file association for melon \(id): \(error)")
            }
        }
    }
}
