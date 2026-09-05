import AuthenticationServices
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

    var userFullName: String? {
        didSet { identity.fullName = userFullName }
    }

    var userIdentifier: String? {
        didSet { identity.userIdentifier = userIdentifier }
    }

    var isSignedIn: Bool {
        if let email = userEmail, !email.isEmpty { return true }
        if let uid = userIdentifier, !uid.isEmpty { return true }
        return false
    }

    /// The workout in progress, or nil. The bar's existence is derived from this
    /// rather than a separate flag that could drift.
    var workout: WorkoutSessionStore?
    var isWorkoutExpanded: Bool = false

    /// True when starting a new workout would destroy an existing one — the
    /// server keeps a single draft per user, so this needs a confirmation.
    var hasWorkoutInProgress: Bool { workout != nil }

    func signIn(userIdentifier: String, email: String?, fullName: String?) {
        self.userIdentifier = userIdentifier
        if let email, !email.isEmpty {
            self.userEmail = email
        } else if self.userEmail == nil || self.userEmail?.isEmpty == true {
            // Fallback for returning Apple users where email is not re-sent on subsequent logins
            self.userEmail = "\(userIdentifier)@appleid.user"
        }
        if let fullName, !fullName.isEmpty {
            self.userFullName = fullName
        }
    }

    func signOut() {
        identity.clear()
        self.userEmail = nil
        self.userFullName = nil
        self.userIdentifier = nil
        self.workout = nil
        self.isWorkoutExpanded = false
        WorkoutActivityManager.shared.endActivity(immediate: true)
    }

    func checkAppleCredentialState() async {
        guard let userId = userIdentifier, !userId.isEmpty else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userId)
            switch state {
            case .authorized:
                break
            case .revoked, .notFound, .transferred:
                signOut()
            @unknown default:
                break
            }
        } catch {
            // Transient error — don't sign out automatically
        }
    }

    func startWorkout(programId: String, day: WorkoutDay) {
        isWorkoutExpanded = true
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

    func endWorkout() {
        workout = nil
        isWorkoutExpanded = false
        WorkoutActivityManager.shared.endActivity(immediate: true)
    }

    /// Called on foreground. Does nothing if a workout is already in memory.
    func restoreWorkoutIfNeeded() async {
        guard workout == nil else { return }
        isWorkoutExpanded = false
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
        
        if let devEmail = config.developmentUserEmail, !devEmail.isEmpty {
            identity.email = devEmail
        }
        self.userEmail = identity.email ?? config.developmentUserEmail
        self.userIdentifier = identity.userIdentifier
        self.userFullName = identity.fullName

        // Read the email lazily so signing in mid-session does not need a rebuild.
        let emailStore = identity
        let fallback = config.developmentUserEmail
        self.client = APIClient(config: config, transport: transport) {
            emailStore.email ?? fallback
        }
    }
}
