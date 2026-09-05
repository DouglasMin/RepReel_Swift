import Foundation
import Observation
import ReelsKit
import UserNotifications

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
        WorkoutActivityManager.shared.startActivity(from: draft)
    }

    // MARK: - Mutations

    /// Toggles a set. Completing starts the rest countdown and saves at once,
    /// because that is the moment worth not losing.
    func completeSet(exercise: Int, set: Int) {
        guard draft.exercises.indices.contains(exercise),
              draft.exercises[exercise].sets.indices.contains(set) else { return }

        let nowCompleted = !draft.exercises[exercise].sets[set].completed
        draft.exercises[exercise].sets[set].completed = nowCompleted

        if nowCompleted {
            let rest = draft.exercises[exercise].effectiveRestSeconds
            let target = Date().addingTimeInterval(TimeInterval(rest))
            restEndsAt = target
            scheduleRestNotification(endsAt: target)
        } else {
            restEndsAt = nil
            cancelRestNotification()
        }
        scheduleSave(immediate: true)
    }

    func setWeight(_ weight: Double?, exercise: Int, set: Int) {
        draft.setWeight(weight, exercise: exercise, set: set)
        scheduleSave()
    }

    func commitWeight(_ weight: Double?, exercise: Int, set: Int) {
        draft.commitWeight(weight, exercise: exercise, set: set)
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

    /// Adds a new set to the given exercise and immediately schedules an update.
    func addSet(exercise: Int) {
        draft.addSet(to: exercise)
        scheduleSave(immediate: true)
    }

    /// Removes a set from the given exercise and immediately schedules an update.
    func removeSet(exercise: Int, set: Int) {
        draft.removeSet(at: set, from: exercise)
        scheduleSave(immediate: true)
    }

    /// Moves/reorders exercises within the workout.
    func moveExercise(from source: IndexSet, to destination: Int) {
        draft.moveExercise(from: source, to: destination)
        scheduleSave(immediate: true)
    }

    /// Updates the target rest duration for an exercise.
    func setRestSeconds(_ seconds: Int, exercise: Int) {
        guard draft.exercises.indices.contains(exercise) else { return }
        draft.exercises[exercise].restSeconds = seconds
    }

    func dismissRest() {
        restEndsAt = nil
        cancelRestNotification()
        WorkoutActivityManager.shared.update(from: draft, restEndsAt: nil)
    }

    /// Extends or decreases the ongoing rest timer by the specified number of seconds.
    func adjustRest(by seconds: TimeInterval) {
        guard let current = restEndsAt else { return }
        let updated = current.addingTimeInterval(seconds)
        if updated <= Date() {
            restEndsAt = nil
            cancelRestNotification()
        } else {
            restEndsAt = updated
            scheduleRestNotification(endsAt: updated)
        }
        WorkoutActivityManager.shared.update(from: draft, restEndsAt: restEndsAt)
    }

    // MARK: - Notifications

    private func scheduleRestNotification(endsAt: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        center.removePendingNotificationRequests(withIdentifiers: ["workout_rest_timer"])

        let seconds = endsAt.timeIntervalSinceNow
        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "휴식 완료 🔔"
        content.body = "다음 세트를 시작할 시간입니다!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "workout_rest_timer", content: content, trigger: trigger)
        center.add(request)
    }

    private func cancelRestNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["workout_rest_timer"])
    }

    // MARK: - Sync

    /// Trailing debounce: a burst of keystrokes becomes one request. Completing a
    /// set bypasses the wait.
    private func scheduleSave(immediate: Bool = false) {
        WorkoutActivityManager.shared.update(from: draft, restEndsAt: restEndsAt)
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
        do {
            let response = try await client.saveActiveSession(draft.makeUpdateRequest())
            if let new = response.activeSession?.volumeAnalytics {
                analytics = new
            }
        } catch {
            #if DEBUG
            print("[WorkoutSessionStore] Save draft failed: \(error)")
            #endif
        }
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
        let startedAt = remote.startedAt ?? sessionData.loggedAt ?? Int(Date().timeIntervalSince1970)

        let day: WorkoutDay?
        do {
            day = try await client.program(id: programId)
                .days.first { $0.dayNumber == dayNumber }
        } catch APIError.notFound {
            day = nil // Genuinely deleted -> orphan
        } catch {
            return nil // Transient error (timeout, 500, etc.) -> retry on next foreground
        }

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
                if let index = draft.exercises.firstIndex(where: { $0.exerciseId == logged.exerciseId }) {
                    draft.exercises[index].exerciseName = logged.exerciseName
                    draft.exercises[index].sets = logged.sets.map {
                        DraftSet(setNumber: $0.setNumber, weightKg: $0.weightKg,
                                 reps: $0.reps, rpe: $0.rpe, completed: $0.completed)
                    }
                } else {
                    // Append unmatched server exercise so swapped exercises or custom items are preserved
                    draft.exercises.append(
                        DraftExercise(
                            exerciseId: logged.exerciseId,
                            exerciseName: logged.exerciseName,
                            equipment: .other,
                            restSeconds: nil,
                            prescription: "",
                            sets: logged.sets.map {
                                DraftSet(setNumber: $0.setNumber, weightKg: $0.weightKg,
                                         reps: $0.reps, rpe: $0.rpe, completed: $0.completed)
                            }
                        )
                    )
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
        guard case .idle = finishState else { return }
        finishState = .saving
        WorkoutActivityManager.shared.endActivity(immediate: true)
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
        _ = await saveTask?.value
        WorkoutActivityManager.shared.endActivity(immediate: true)
        _ = try? await client.discardActiveSession()
    }

    func substitutes(for exercise: Int) async throws -> [ExerciseSubstituteItem] {
        guard draft.exercises.indices.contains(exercise) else { return [] }
        let target = draft.exercises[exercise]
        let targetMuscle = target.primaryMuscle.isEmpty ? target.exerciseName : target.primaryMuscle
        let response = try await client.substituteExercise(
            ExerciseSubstituteRequest(
                exerciseName: target.exerciseName,
                targetMuscle: targetMuscle,
                preferredEquipment: nil
            )
        )
        return response.substitutes
    }

    /// Replaces the exercise but keeps the logged rows, so the checklist does not
    /// reset when a machine is taken.
    func swap(exercise: Int, to item: ExerciseSubstituteItem) {
        guard draft.exercises.indices.contains(exercise) else { return }
        let existing = draft.exercises[exercise]
        draft.exercises[exercise] = DraftExercise(
            exerciseId: existing.exerciseId,
            exerciseName: item.exerciseName,
            equipment: EquipmentType(rawValue: item.equipment) ?? existing.equipment,
            primaryMuscle: existing.primaryMuscle,
            restSeconds: existing.restSeconds,
            prescription: item.recommendedVolume ?? existing.prescription,
            sets: existing.sets
        )
        scheduleSave()
    }
}
