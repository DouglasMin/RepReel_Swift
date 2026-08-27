import Foundation

/// One set the user is working through. Distinct from `LoggedSet` because the
/// weight field is empty until typed, and `LoggedSet.weightKg` is non-optional.
public struct DraftSet: Identifiable, Sendable, Equatable {
    public var id: Int { setNumber }

    public let setNumber: Int
    public var weightKg: Double?
    public var reps: Int
    public var rpe: Double?
    public var completed: Bool

    public init(setNumber: Int, weightKg: Double? = nil, reps: Int,
                rpe: Double? = nil, completed: Bool = false) {
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.completed = completed
    }
}

public struct DraftExercise: Identifiable, Sendable {
    public var id: String { exerciseId }

    public let exerciseId: String
    public let exerciseName: String
    public let equipment: EquipmentType
    public let restSeconds: Int?
    /// Pre-rendered prescription, e.g. "5세트 × 8-10회".
    public let prescription: String
    public var sets: [DraftSet]

    // Explicit: the memberwise init is internal, and the app target constructs
    // these when resuming and when swapping an exercise.
    public init(exerciseId: String, exerciseName: String, equipment: EquipmentType,
                restSeconds: Int?, prescription: String, sets: [DraftSet]) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.equipment = equipment
        self.restSeconds = restSeconds
        self.prescription = prescription
        self.sets = sets
    }
}

/// The workout in progress. Seeded from the program's prescription, mutated as
/// the user logs, and converted to wire types only when sending.
public struct WorkoutDraft: Sendable {
    public let programId: String
    public let dayNumber: Int
    public let dayTitle: String
    public let startedAt: Int
    public var exercises: [DraftExercise]

    public init(programId: String, dayNumber: Int, dayTitle: String,
                startedAt: Int, exercises: [DraftExercise]) {
        self.programId = programId
        self.dayNumber = dayNumber
        self.dayTitle = dayTitle
        self.startedAt = startedAt
        self.exercises = exercises
    }

    public static func seed(
        programId: String, day: WorkoutDay, startedAt: Int
    ) -> WorkoutDraft {
        let exercises = day.exerciseGroups.flatMap(\.exercises).map { exercise in
            let volume = exercise.volume
            let targetReps = volume.maxReps ?? volume.minReps
            return DraftExercise(
                exerciseId: exercise.exerciseId,
                exerciseName: exercise.canonicalNameKo,
                equipment: exercise.equipment,
                restSeconds: volume.restSeconds,
                prescription: volume.volumeDisplayString,
                sets: (1...max(1, volume.minSets)).map {
                    DraftSet(setNumber: $0, reps: targetReps)
                }
            )
        }
        return WorkoutDraft(
            programId: programId, dayNumber: day.dayNumber,
            dayTitle: day.dayTitle, startedAt: startedAt, exercises: exercises
        )
    }

    /// Sets a weight and fills the still-empty sets below it, so a working weight
    /// is typed once rather than once per set. Clearing never cascades.
    public mutating func setWeight(_ weight: Double?, exercise: Int, set: Int) {
        guard exercises.indices.contains(exercise),
              exercises[exercise].sets.indices.contains(set) else { return }

        exercises[exercise].sets[set].weightKg = weight
        guard let weight else { return }

        for index in (set + 1)..<exercises[exercise].sets.count
        where exercises[exercise].sets[index].weightKg == nil {
            exercises[exercise].sets[index].weightKg = weight
        }
    }
}
