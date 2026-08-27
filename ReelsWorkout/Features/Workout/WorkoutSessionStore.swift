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
    var finishState: WorkoutFinishState = .idle
    private(set) var isOrphaned = false

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
enum WorkoutFinishState {
    case idle
    case saving
    case finished(WorkoutSessionLog)
    case failed(String)
}

extension WorkoutSessionStore {

    /// Rebuilds a draft from a server draft plus the program it belongs to.
    /// A program that 404s yields an orphaned store: it shows what was logged so
    /// the user can discard knowingly, but cannot be continued.
    static func resume(client: APIClient) async -> WorkoutSessionStore? {
        guard let response = try? await client.activeSession(),
              response.hasActiveSession,
              let remote = response.activeSession,
              let sessionData = remote.sessionData else { return nil }

        let programId = remote.programId ?? sessionData.programId
        let dayNumber = remote.dayNumber ?? sessionData.dayNumber
        let startedAt = remote.startedAt ?? sessionData.loggedAt ?? 0

        let program = try? await client.program(id: programId)
        let day = program?.days.first { $0.dayNumber == dayNumber }

        // Seed from the program when it exists so prescriptions and rest times are
        // right, then overlay what the server recorded.
        var draft = day.map {
            WorkoutDraft.seed(programId: programId, day: $0, startedAt: startedAt)
        } ?? WorkoutDraft(
            programId: programId, dayNumber: dayNumber,
            dayTitle: "Day \(dayNumber)", startedAt: startedAt,
            exercises: sessionData.completedExercises.map { logged in
                DraftExercise(
                    exerciseId: logged.exerciseId, exerciseName: logged.exerciseName,
                    equipment: .other, restSeconds: nil, prescription: "",
                    sets: logged.sets.map {
                        DraftSet(setNumber: $0.setNumber, weightKg: $0.weightKg,
                                 reps: $0.reps, rpe: $0.rpe, completed: $0.completed)
                    }
                )
            }
        )

        if day != nil {
            for logged in sessionData.completedExercises {
                guard let index = draft.exercises
                    .firstIndex(where: { $0.exerciseId == logged.exerciseId }) else { continue }
                draft.exercises[index].sets = logged.sets.map {
                    DraftSet(setNumber: $0.setNumber, weightKg: $0.weightKg,
                             reps: $0.reps, rpe: $0.rpe, completed: $0.completed)
                }
            }
        }

        let store = WorkoutSessionStore(client: client, draft: draft)
        store.isOrphaned = (day == nil)
        store.analytics = remote.volumeAnalytics
        return store
    }

    /// Unlike a draft save, this failure is loud: it is an hour of work.
    func finish(notes: String?) async {
        finishState = .saving
        let log = draft.makeSessionLog(loggedAt: Int(Date().timeIntervalSince1970),
                                       notes: notes)
        do {
            let response = try await client.logSession(log)
            finishState = .finished(response.session ?? log)
        } catch {
            finishState = .failed(error.localizedDescription)
        }
    }

    func discard() async {
        saveTask?.cancel()
        _ = try? await client.discardActiveSession()
    }
}
