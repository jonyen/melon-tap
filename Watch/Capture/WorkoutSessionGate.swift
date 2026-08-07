import Foundation
import HealthKit
import MelonKit

/// Holds an `HKWorkoutSession` open for the duration of a capture. The 800 Hz accelerometer
/// stream is workout-gated by the OS, so this is the price of admission.
///
/// The session is ended without ever creating an `HKWorkoutBuilder`, so nothing is written to Health.
///
/// `HKWorkoutSession` state transitions are delivered asynchronously through
/// `HKWorkoutSessionDelegate`, not synchronously from `startActivity(with:)`. `open()` suspends
/// on a `CheckedContinuation` until the delegate reports `.running` (success), reports a failure,
/// or a timeout fires — whichever comes first. Isolated to the main actor so `startContinuation`
/// and `timeoutTask` are only ever touched from one thread; `HKWorkoutSessionDelegate` invokes its
/// methods off the main actor, so those two methods below are `nonisolated` and hop back via
/// `Task { @MainActor in ... }` before touching actor-isolated state, matching the pattern already
/// used by `WatchSyncService` and `PhoneSyncService`.
@MainActor
final class WorkoutSessionGate: NSObject, HKWorkoutSessionDelegate {

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?

    /// The continuation `open()` is suspended on, plus the task racing it to a timeout. Every
    /// path that can complete the wait — `.running`, `didFailWithError`, and the timeout —
    /// funnels through `finishStarting(_:)`, which resumes the continuation only the first time
    /// it is called and nils it out immediately after. A `CheckedContinuation` resumed twice is a
    /// crash (e.g. a delegate callback arriving after the timeout already fired, or an error
    /// transition arriving after `.running` was already reported), so nothing outside
    /// `finishStarting(_:)` is allowed to call `resume` directly. All callers run on the main
    /// actor's serial executor, so the nil-check-then-clear in `finishStarting(_:)` cannot race
    /// with itself.
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    /// Requests permission once and starts a session, suspending until it is actually running.
    ///
    /// Throws `CaptureError.healthKitDenied` only for genuine authorization refusal — HealthKit
    /// unavailable, or `requestAuthorization` failing/declining. Any other failure (the session
    /// initializer throwing, the session failing to start, or timing out) throws
    /// `CaptureError.other` carrying the real error text, so the user is never told to grant a
    /// permission that isn't the actual problem.
    func open() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CaptureError.healthKitDenied
        }

        let workoutType = HKObjectType.workoutType()
        do {
            try await healthStore.requestAuthorization(toShare: [workoutType], read: [])
        } catch {
            throw CaptureError.healthKitDenied
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor

        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        } catch {
            // A real initializer failure — e.g. the app is missing the WKBackgroundModes /
            // workout-processing background mode — not a permission refusal. Preserve what
            // actually happened instead of steering the user toward a permission prompt that
            // cannot fix this.
            throw CaptureError.other(error.localizedDescription)
        }

        session.delegate = self
        self.session = session

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.startContinuation = continuation

            self.timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(AnalysisConstants.workoutSessionStartTimeoutSeconds))
                guard !Task.isCancelled else { return }
                self.finishStarting(.failure(CaptureError.other("The workout session did not start in time.")))
            }

            session.startActivity(with: Date())
        }
    }

    /// Ends the session. Safe to call when no session is open.
    func close() {
        session?.end()
        session = nil
    }

    /// Resumes `startContinuation` exactly once, cancelling the race with the timeout task. Every
    /// other path in this file that could complete the wait calls this instead of resuming
    /// directly, so a resume that already happened is a guaranteed no-op here.
    private func finishStarting(_ result: Result<Void, Error>) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }

    // MARK: HKWorkoutSessionDelegate

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .running else { return }
        Task { @MainActor in
            self.finishStarting(.success(()))
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.finishStarting(.failure(CaptureError.other(error.localizedDescription)))
        }
    }
}
