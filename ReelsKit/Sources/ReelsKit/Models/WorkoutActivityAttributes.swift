#if os(iOS)
import ActivityKit
import Foundation

/// ActivityKit descriptor for live workout tracking across Dynamic Island and Lock Screen.
public struct WorkoutActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var dayTitle: String
        public var exerciseName: String
        public var lastCompletedSetNumber: Int
        public var nextSetNumber: Int
        public var statusBadge: String
        public var nextSetDescription: String
        public var totalSetsInExercise: Int
        public var totalCompletedSets: Int
        public var totalSetsInWorkout: Int
        public var weightKg: Double?
        public var targetReps: Int
        public var restEndsAt: Date?
        public var startedAt: Date
        public var isResting: Bool
        public var isFinished: Bool

        public init(
            dayTitle: String,
            exerciseName: String,
            lastCompletedSetNumber: Int,
            nextSetNumber: Int,
            statusBadge: String,
            nextSetDescription: String,
            totalSetsInExercise: Int,
            totalCompletedSets: Int,
            totalSetsInWorkout: Int,
            weightKg: Double?,
            targetReps: Int,
            restEndsAt: Date?,
            startedAt: Date,
            isResting: Bool,
            isFinished: Bool = false
        ) {
            self.dayTitle = dayTitle
            self.exerciseName = exerciseName
            self.lastCompletedSetNumber = lastCompletedSetNumber
            self.nextSetNumber = nextSetNumber
            self.statusBadge = statusBadge
            self.nextSetDescription = nextSetDescription
            self.totalSetsInExercise = totalSetsInExercise
            self.totalCompletedSets = totalCompletedSets
            self.totalSetsInWorkout = totalSetsInWorkout
            self.weightKg = weightKg
            self.targetReps = targetReps
            self.restEndsAt = restEndsAt
            self.startedAt = startedAt
            self.isResting = isResting
            self.isFinished = isFinished
        }
    }

    public var programId: String
    public var dayNumber: Int

    public init(programId: String, dayNumber: Int) {
        self.programId = programId
        self.dayNumber = dayNumber
    }
}
#endif
