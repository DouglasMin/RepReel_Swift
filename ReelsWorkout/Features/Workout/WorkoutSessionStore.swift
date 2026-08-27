import Foundation
import Observation
import ReelsKit

/// The workout in progress. Owned by `AppEnvironment` so it outlives the screen —
/// the collapsed bar reads the same instance the expanded view mutates.
@MainActor
@Observable
final class WorkoutSessionStore {
    private(set) var draft: WorkoutDraft
    /// Server-computed tonnage. Never recomputed locally for display.
    private(set) var analytics: WorkoutVolumeAnalytics?
    private(set) var restEndsAt: Date?

    private let client: APIClient
    private var saveTask: Task<Void, Never>?

    private static let debounce = Duration.milliseconds(750)

    init(client: APIClient, draft: WorkoutDraft) {
        self.client = client
        self.draft = draft
    }

    // MARK: - Mutations

    /// Toggles a set. Completing starts the rest countdown and saves at once,
    /// because that is the moment worth not losing.
    func completeSet(exercise: Int, set: Int) {
        guard draft.exercises.indices.contains(exercise),
              draft.exercises[exercise].sets.indices.contains(set) else { return }

        let nowCompleted = !draft.exercises[exercise].sets[set].completed
        draft.exercises[exercise].sets[set].completed = nowCompleted

        if nowCompleted, let rest = draft.exercises[exercise].restSeconds {
            restEndsAt = Date().addingTimeInterval(TimeInterval(rest))
        } else {
            restEndsAt = nil
        }
        scheduleSave(immediate: true)
    }

    func setWeight(_ weight: Double?, exercise: Int, set: Int) {
        draft.setWeight(weight, exercise: exercise, set: set)
        scheduleSave()
    }

    func setReps(_ reps: Int, exercise: Int, set: Int) {
        guard draft.exercises.indices.contains(exercise),
              draft.exercises[exercise].sets.indices.contains(set) else { return }
        draft.exercises[exercise].sets[set].reps = reps
        scheduleSave()
    }

    func setRPE(_ rpe: Double?, exercise: Int, set: Int) {
        guard draft.exercises.indices.contains(exercise),
              draft.exercises[exercise].sets.indices.contains(set) else { return }
        draft.exercises[exercise].sets[set].rpe = rpe
        scheduleSave()
    }

    func dismissRest() { restEndsAt = nil }

    // MARK: - Sync

    /// Trailing debounce: a burst of keystrokes becomes one request. Completing a
    /// set bypasses the wait.
    private func scheduleSave(immediate: Bool = false) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: Self.debounce)
                if Task.isCancelled { return }
            }
            await self?.save()
        }
    }

    private func save() async {
        // Connectivity is out of scope by design: failures are silent and the
        // local draft remains the working copy.
        guard let response = try? await client.saveActiveSession(draft.makeUpdateRequest())
        else { return }
        analytics = response.activeSession?.volumeAnalytics
    }

    /// Awaits any in-flight or pending save. Used by tests and before finishing.
    func flushPendingSave() async {
        await saveTask?.value
    }
}
