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
            #if DEBUG
            print("[LibraryStore] Successfully loaded \(programs.count) programs")
            #endif
            errorMessage = nil
        } catch is CancellationError {
            // Task cancelled (e.g. view dismissed), do not surface error
        } catch {
            guard !Task.isCancelled else { return }
            if case APIError.transport(let underlying) = error,
               (underlying as NSError).code == NSURLErrorCancelled {
                return
            }
            #if DEBUG
            print("[LibraryStore] Failed to load programs: \(error)")
            #endif
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
        if let task = pollTasks.removeValue(forKey: job.jobId) {
            task.cancel()
        }
        jobStore.remove(jobId: job.jobId)
        pending.removeAll { $0.jobId == job.jobId }
    }

    /// Manual entry point for a reel URL pasted into the app.
    func ingest(url: String) async {
        do {
            #if DEBUG
            print("[LibraryStore] Starting ingest for URL: \(url)")
            #endif
            let response = try await client.ingestReel(url: url)
            #if DEBUG
            print("[LibraryStore] Ingest response received: jobId=\(response.jobId)")
            #endif
            let job = PendingJob(jobId: response.jobId, reelURL: url)
            jobStore.append(job)
            reloadPendingJobs()
        } catch is CancellationError {
            // Task cancelled
        } catch {
            guard !Task.isCancelled else { return }
            if case APIError.transport(let underlying) = error,
               (underlying as NSError).code == NSURLErrorCancelled {
                return
            }
            #if DEBUG
            print("[LibraryStore] Ingest failed: \(error)")
            #endif
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a program by id and removes it from the local list.
    func deleteProgram(id: String) async {
        do {
            #if DEBUG
            print("[LibraryStore] Deleting program \(id)...")
            #endif
            try await client.deleteProgram(id: id)
            programs.removeAll { $0.programId == id }
            errorMessage = nil
        } catch is CancellationError {
            // Task cancelled
        } catch {
            guard !Task.isCancelled else { return }
            if case APIError.transport(let underlying) = error,
               (underlying as NSError).code == NSURLErrorCancelled {
                return
            }
            #if DEBUG
            print("[LibraryStore] Delete failed: \(error)")
            #endif
            errorMessage = error.localizedDescription
        }
    }

    /// Updates local cached program summary immediately when updated in detail view.
    func updateProgramSummary(from response: WorkoutProgramResponse) {
        if let index = programs.firstIndex(where: { $0.programId == response.programId }) {
            let old = programs[index]
            programs[index] = ProgramSummary(
                programId: old.programId,
                title: response.title,
                creator: response.creator ?? old.creator,
                splitType: response.splitType,
                createdAt: old.createdAt
            )
        }
    }

    /// Removes a program from the local list immediately.
    func removeProgram(id: String) {
        programs.removeAll { $0.programId == id }
    }

    /// Merges multiple series programs into a single multi-day program.
    @discardableResult
    func mergePrograms(programIds: [String], title: String?) async throws -> String {
        #if DEBUG
        print("[LibraryStore] Merging programs: \(programIds) with title: \(title ?? "nil")")
        #endif
        let request = ProgramMergeRequest(programIds: programIds, title: title)
        let response = try await client.mergePrograms(request)
        await loadPrograms()
        return response.mergedProgramId
    }

    private func poll(_ job: PendingJob) async {
        defer {
            pollTasks[job.jobId] = nil
        }
        do {
            #if DEBUG
            print("[LibraryStore] Polling job \(job.jobId)...")
            #endif
            let result = try await client.awaitJobCompletion(jobId: job.jobId)
            #if DEBUG
            print("[LibraryStore] Job \(job.jobId) poll finished: status=\(result.status.rawValue), programId=\(result.programId ?? "nil"), error=\(result.error ?? "nil")")
            #endif
            guard !Task.isCancelled else { return }
            switch result.status {
            case .completed:
                jobStore.remove(jobId: job.jobId)
                pending.removeAll { $0.jobId == job.jobId }
                await loadPrograms()
            case .failed:
                errorMessage = result.error ?? "릴스 분석에 실패했습니다."
                jobStore.remove(jobId: job.jobId)
                pending.removeAll { $0.jobId == job.jobId }
            case .processing:
                // Hit the poll timeout; leave it queued for the next foreground.
                break
            }
        } catch is CancellationError {
            #if DEBUG
            print("[LibraryStore] Polling job \(job.jobId) was cancelled.")
            #endif
        } catch {
            guard !Task.isCancelled else { return }
            if case APIError.transport(let underlying) = error,
               (underlying as NSError).code == NSURLErrorCancelled {
                return
            }
            #if DEBUG
            print("[LibraryStore] Polling job \(job.jobId) error: \(error)")
            #endif
            errorMessage = error.localizedDescription
        }
    }
}
