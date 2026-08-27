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
