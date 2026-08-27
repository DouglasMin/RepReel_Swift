import Foundation
import Testing
@testable import ReelsKit

@Suite("PendingJobStore")
struct PendingJobStoreTests {

    private func makeStore() -> (PendingJobStore, UserDefaults, String) {
        let suite = "reelskit.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (PendingJobStore(defaults: defaults), defaults, suite)
    }

    @Test("Round-trips jobs written by the share extension")
    func roundTrips() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.append(PendingJob(jobId: "job_1", reelURL: "https://instagram.com/reel/a/", createdAt: 1))
        store.append(PendingJob(jobId: "job_2", reelURL: "https://instagram.com/reel/b/", createdAt: 2))

        #expect(store.all().map(\.jobId) == ["job_1", "job_2"])
        #expect(store.all().first?.reelURL == "https://instagram.com/reel/a/")
    }

    @Test("Ignores a duplicate job id so a re-share does not double the banner")
    func deduplicates() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.append(PendingJob(jobId: "job_1", reelURL: "https://a", createdAt: 1))
        store.append(PendingJob(jobId: "job_1", reelURL: "https://a", createdAt: 2))

        #expect(store.all().count == 1)
    }

    @Test("Removes a job once its program resolves")
    func removes() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.append(PendingJob(jobId: "job_1", reelURL: "https://a", createdAt: 1))
        store.append(PendingJob(jobId: "job_2", reelURL: "https://b", createdAt: 2))
        store.remove(jobId: "job_1")

        #expect(store.all().map(\.jobId) == ["job_2"])
    }
}

@Suite("AppConfig")
struct AppConfigTests {

    @Test("Builds the base URL from host plus stage path")
    func buildsBaseURL() {
        let config = AppConfig(
            apiHost: "abc.execute-api.ap-northeast-2.amazonaws.com",
            apiStagePath: "/dev",
            appSecret: "s",
            appGroupID: "group.test"
        )
        #expect(config.baseURL.absoluteString
            == "https://abc.execute-api.ap-northeast-2.amazonaws.com/dev")
    }

    @Test("Tolerates an empty stage path")
    func emptyStagePath() {
        let config = AppConfig(
            apiHost: "abc.execute-api.ap-northeast-2.amazonaws.com",
            appSecret: "s",
            appGroupID: "group.test"
        )
        #expect(config.baseURL.absoluteString
            == "https://abc.execute-api.ap-northeast-2.amazonaws.com")
    }
}
