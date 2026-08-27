import Foundation
import Observation
import ReelsKit

/// Single composition root: reads build config once, wires the API client to the
/// shared App Group stores, and hands the result to the view tree.
@MainActor
@Observable
final class AppEnvironment {
    let config: AppConfig
    let client: APIClient
    let pendingJobs: PendingJobStore
    private let identity: UserIdentityStore

    /// Nil until the user signs in (or `DEV_USER_EMAIL` is set in Secrets.xcconfig).
    var userEmail: String? {
        didSet { identity.email = userEmail }
    }

    /// The workout in progress, or nil. The bar's existence is derived from this
    /// rather than a separate flag that could drift.
    var workout: WorkoutSessionStore?

    /// True when starting a new workout would destroy an existing one — the
    /// server keeps a single draft per user, so this needs a confirmation.
    var hasWorkoutInProgress: Bool { workout != nil }

    func startWorkout(programId: String, day: WorkoutDay) {
        workout = WorkoutSessionStore(
            client: client,
            draft: .seed(programId: programId, day: day,
                         startedAt: Int(Date().timeIntervalSince1970))
        )
    }

    /// Discards the running draft server-side before replacing it.
    func replaceWorkout(programId: String, day: WorkoutDay) async {
        await workout?.discard()
        startWorkout(programId: programId, day: day)
    }

    func endWorkout() { workout = nil }

    /// Called on foreground. Does nothing if a workout is already in memory.
    func restoreWorkoutIfNeeded() async {
        guard workout == nil else { return }
        workout = await WorkoutSessionStore.resume(client: client)
    }

    static func bootstrap() -> Result<AppEnvironment, any Error> {
        Result { try AppEnvironment() }
    }

    convenience init() throws {
        try self.init(config: AppConfig.fromBundle())
    }

    /// `transport` is injected by previews and demo mode; production passes the
    /// default `URLSession.shared`.
    init(config: AppConfig, transport: any HTTPTransport = URLSession.shared) throws {
        guard let pendingJobs = PendingJobStore(appGroupID: config.appGroupID),
              let identity = UserIdentityStore(appGroupID: config.appGroupID) else {
            throw AppConfig.ConfigError.placeholderValue("AppGroupID")
        }

        self.config = config
        self.pendingJobs = pendingJobs
        self.identity = identity
        self.userEmail = identity.email ?? config.developmentUserEmail

        // Read the email lazily so signing in mid-session does not need a rebuild.
        let emailStore = identity
        let fallback = config.developmentUserEmail
        self.client = APIClient(config: config, transport: transport) {
            emailStore.email ?? fallback
        }

        // Persist the dev fallback so the share extension can authenticate too.
        if identity.email == nil { identity.email = config.developmentUserEmail }
    }
}
