import Foundation
import HealthKit

/// Holds an `HKWorkoutSession` open for the duration of a capture. The 800 Hz accelerometer
/// stream is workout-gated by the OS, so this is the price of admission.
///
/// The session is ended without ever creating an `HKWorkoutBuilder`, so nothing is written to Health.
@MainActor
final class WorkoutSessionGate {

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?

    /// Requests permission once and starts a session. Throws `CaptureError.healthKitDenied`
    /// if the user refuses or HealthKit is unavailable.
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

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.startActivity(with: Date())
            self.session = session
        } catch {
            throw CaptureError.healthKitDenied
        }
    }

    /// Ends the session. Safe to call when no session is open.
    func close() {
        session?.end()
        session = nil
    }
}
