import Foundation

/// A reel handed off by the share extension and not yet resolved into a program.
public struct PendingJob: Codable, Identifiable, Sendable, Equatable {
    public var id: String { jobId }

    public let jobId: String
    public let reelURL: String
    public let createdAt: Int

    public init(jobId: String, reelURL: String, createdAt: Int = Int(Date().timeIntervalSince1970)) {
        self.jobId = jobId
        self.reelURL = reelURL
        self.createdAt = createdAt
    }
}

/// App Group hand-off between the share extension (writer) and the app (reader).
///
/// The extension has a few hundred milliseconds to live, so writes stay
/// synchronous and small. Records are stored as JSON rather than the plain id
/// array in `docs/IOS_SHARE_EXTENSION_GUIDE.md` so the app can show which reel is
/// being analysed while it polls.
///
/// `@unchecked` because `UserDefaults` is thread-safe but not marked `Sendable`.
public struct PendingJobStore: @unchecked Sendable {
    private static let key = "pending_jobs"

    private let defaults: UserDefaults

    public init?(appGroupID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        self.defaults = defaults
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func all() -> [PendingJob] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([PendingJob].self, from: data)) ?? []
    }

    public func append(_ job: PendingJob) {
        var jobs = all()
        guard !jobs.contains(where: { $0.jobId == job.jobId }) else { return }
        jobs.append(job)
        write(jobs)
    }

    public func remove(jobId: String) {
        write(all().filter { $0.jobId != jobId })
    }

    public func removeAll() {
        defaults.removeObject(forKey: Self.key)
    }

    private func write(_ jobs: [PendingJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// The signed-in user's email, shared with the extension so it can authenticate
/// its `POST /reels` call. Replace the writer with Sign in with Apple.
///
/// `@unchecked` because `UserDefaults` is thread-safe but not marked `Sendable`.
public struct UserIdentityStore: @unchecked Sendable {
    private static let key = "user_email"

    private let defaults: UserDefaults

    public init?(appGroupID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        self.defaults = defaults
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var email: String? {
        get { defaults.string(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
