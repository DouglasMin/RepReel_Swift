import ActivityKit
import Foundation
import ReelsKit

/// Bridges WorkoutSessionStore mutations to the system ActivityKit / Dynamic Island lifecycle.
@MainActor
final class WorkoutActivityManager {
    static let shared = WorkoutActivityManager()

    private var currentActivity: Activity<WorkoutActivityAttributes>?

    private init() {}

    func startActivity(from draft: WorkoutDraft) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            #if DEBUG
            print("[WorkoutActivityManager] Live Activities are disabled by user/system settings")
            #endif
            return
        }

        // 1. If an active activity already exists, reuse it and push the new state immediately
        if let existing = (currentActivity?.activityState == .active ? currentActivity : nil)
            ?? Activity<WorkoutActivityAttributes>.activities.first(where: { $0.activityState == .active }) {
            self.currentActivity = existing
            update(from: draft, restEndsAt: nil)
            #if DEBUG
            print("[WorkoutActivityManager] Reused active Live Activity: \(existing.id)")
            #endif
            return
        }

        // 2. Otherwise request a fresh Live Activity
        self.currentActivity = nil
        let attributes = WorkoutActivityAttributes(
            programId: draft.programId,
            dayNumber: draft.dayNumber
        )
        let state = buildContentState(from: draft, restEndsAt: nil)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            self.currentActivity = activity

            #if DEBUG
            print("[WorkoutActivityManager] Successfully started Live Activity: \(activity.id)")
            #endif
        } catch {
            #if DEBUG
            print("[WorkoutActivityManager] Failed to start Live Activity: \(error)")
            #endif
        }
    }

    func update(from draft: WorkoutDraft, restEndsAt: Date?) {
        let activeActivity = (currentActivity?.activityState == .active ? currentActivity : nil)
            ?? Activity<WorkoutActivityAttributes>.activities.first(where: { $0.activityState == .active })

        guard let activity = activeActivity else {
            startActivity(from: draft)
            return
        }
        self.currentActivity = activity

        let state = buildContentState(from: draft, restEndsAt: restEndsAt)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity(immediate: Bool = true) {
        self.currentActivity = nil
        let activitiesToEnd = Activity<WorkoutActivityAttributes>.activities
        for activity in activitiesToEnd {
            Task {
                await activity.end(nil, dismissalPolicy: immediate ? .immediate : .default)
            }
        }
    }

    private func buildContentState(from draft: WorkoutDraft, restEndsAt: Date?) -> WorkoutActivityAttributes.ContentState {
        let isResting = (restEndsAt != nil && restEndsAt! > Date())

        // 1. Identify currently active / targeted exercise and completed count
        var targetExercise = draft.exercises.first ?? DraftExercise(
            exerciseId: "default",
            exerciseName: "운동",
            equipment: .other,
            restSeconds: 60,
            prescription: "",
            sets: []
        )

        var lastCompletedSet = 0
        var nextSetNumber = 1
        var nextWeight: Double? = nil
        var nextReps = 10
        var foundNext = false

        for exercise in draft.exercises {
            let completedInExercise = exercise.sets.filter(\.completed)
            if let last = completedInExercise.last {
                lastCompletedSet = last.setNumber
                targetExercise = exercise
            }

            if let nextIncomplete = exercise.sets.first(where: { !$0.completed }) {
                targetExercise = exercise
                nextSetNumber = nextIncomplete.setNumber
                nextWeight = nextIncomplete.weightKg
                nextReps = nextIncomplete.reps
                foundNext = true
                break
            }
        }

        if !foundNext, let lastEx = draft.exercises.last, let lastSet = lastEx.sets.last {
            targetExercise = lastEx
            nextSetNumber = lastSet.setNumber
            nextWeight = lastSet.weightKg
            nextReps = lastSet.reps
            lastCompletedSet = lastSet.setNumber
        }

        let totalCompleted = draft.completedSetCount
        let totalSets = max(1, draft.totalSetCount)

        let statusBadge: String
        if isResting {
            statusBadge = lastCompletedSet > 0 ? "\(lastCompletedSet)세트 완료 · 휴식" : "휴식 중"
        } else {
            statusBadge = "\(nextSetNumber)세트 진행 중"
        }

        let weightText = nextWeight.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))kg" } ?? "체중"
        let nextSetDescription = "다음: \(nextSetNumber)세트 (\(weightText) × \(nextReps)회)"

        var startTime = Date(timeIntervalSince1970: TimeInterval(draft.startedAt > 100_000_000_000 ? draft.startedAt / 1000 : draft.startedAt))
        if startTime.timeIntervalSince1970 < 1_500_000_000 || startTime > Date() {
            startTime = Date()
        }

        return WorkoutActivityAttributes.ContentState(
            dayTitle: draft.dayTitle.isEmpty ? "루틴" : draft.dayTitle,
            exerciseName: targetExercise.exerciseName.isEmpty ? "운동" : targetExercise.exerciseName,
            lastCompletedSetNumber: lastCompletedSet,
            nextSetNumber: nextSetNumber,
            statusBadge: statusBadge,
            nextSetDescription: nextSetDescription,
            totalSetsInExercise: max(1, targetExercise.sets.count),
            totalCompletedSets: totalCompleted,
            totalSetsInWorkout: totalSets,
            weightKg: nextWeight,
            targetReps: nextReps,
            restEndsAt: isResting ? restEndsAt : nil,
            startedAt: startTime,
            isResting: isResting,
            isFinished: totalCompleted >= totalSets
        )
    }
}
