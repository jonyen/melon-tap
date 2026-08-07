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

    /// Melons arriving from the Watch are appended to the most recent session if it is still
    /// open, otherwise a new session is started. Grouping by arrival time avoids needing any
    /// session-management UI on the wrist.
    private func configureSync() {
        let context = ModelContext(container)

        PhoneSyncService.shared.onMelonReceived = { payload in
            let existing = try? context.fetch(
                FetchDescriptor<Melon>(predicate: #Predicate { $0.id == payload.id })
            )
            guard existing?.isEmpty ?? true else { return }

            let melon = Melon.make(from: payload)

            var descriptor = FetchDescriptor<MelonSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            let latest = try? context.fetch(descriptor).first

            if let latest,
               payload.capturedAt.timeIntervalSince(latest.startedAt) < MelonSession.sessionGapSeconds {
                melon.session = latest
            } else {
                let session = MelonSession(startedAt: payload.capturedAt)
                context.insert(session)
                melon.session = session
            }

            context.insert(melon)
            try? context.save()
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
            try? context.save()
        }
    }
}
