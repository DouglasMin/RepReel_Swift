import Foundation
import Observation
import ReelsKit

/// Drives the library screen: the saved-program list plus the reels the share
/// extension dropped into the App Group and that are still being analysed.
@MainActor
@Observable
final class LibraryStore {
    private(set) var programs: [ProgramSummary] = []
    private(set) var pending: [PendingJob] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let client: APIClient
    private let jobStore: PendingJobStore
    private var pollTasks: [String: Task<Void, Never>] = [:]

    init(client: APIClient, jobStore: PendingJobStore) {
        self.client = client
        self.jobStore = jobStore
    }

    func refresh() async {
        reloadPendingJobs()
        await loadPrograms()
    }

    func loadPrograms() async {
        isLoading = true
        defer { isLoading = false }
        do {
            programs = try await client.programs(limit: 50)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Picks up whatever the share extension wrote while the app was suspended.
    func reloadPendingJobs() {
        pending = jobStore.all()
        for job in pending where pollTasks[job.jobId] == nil {
            pollTasks[job.jobId] = Task { [weak self] in
                await self?.poll(job)
            }
        }
    }

    func dismissPendingJob(_ job: PendingJob) {
        pollTasks[job.jobId]?.cancel()
        pollTasks[job.jobId] = nil
        jobStore.remove(jobId: job.jobId)
        pending.removeAll { $0.jobId == job.jobId }
    }

    /// Manual entry point for a reel URL pasted into the app.
    func ingest(url: String) async {
        do {
            let response = try await client.ingestReel(url: url)
            let job = PendingJob(jobId: response.jobId, reelURL: url)
            jobStore.append(job)
            reloadPendingJobs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func poll(_ job: PendingJob) async {
        do {
            let result = try await client.awaitJobCompletion(jobId: job.jobId)
            guard !Task.isCancelled else { return }
            switch result.status {
            case .completed:
                dismissPendingJob(job)
                await loadPrograms()
            case .failed:
                errorMessage = result.error ?? "릴스 분석에 실패했습니다."
                dismissPendingJob(job)
            case .processing:
                // Hit the poll timeout; leave it queued for the next foreground.
                pollTasks[job.jobId] = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            pollTasks[job.jobId] = nil
        }
    }
}
