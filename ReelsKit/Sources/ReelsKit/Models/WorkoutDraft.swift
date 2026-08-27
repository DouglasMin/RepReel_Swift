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
    /// Mutable because a mid-workout substitution renames the row in place, and a
    /// resume has to restore that name from the server's log.
    public var exerciseName: String
    public let equipment: EquipmentType
    /// What the substitution endpoint needs as `target_muscle` — a muscle, not the
    /// exercise's own name.
    public let primaryMuscle: String
    public var restSeconds: Int?
    /// Pre-rendered prescription, e.g. "5세트 × 8-10회".
    public var prescription: String
    public var sets: [DraftSet]

    public var effectiveRestSeconds: Int {
        if let restSeconds, restSeconds > 0 { return restSeconds }
        return 90
    }

    // Explicit: the memberwise init is internal, and the app target constructs
    // these when resuming and when swapping an exercise.
    public init(exerciseId: String, exerciseName: String, equipment: EquipmentType,
                primaryMuscle: String = "", restSeconds: Int?,
                prescription: String, sets: [DraftSet]) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.equipment = equipment
        self.primaryMuscle = primaryMuscle
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
                primaryMuscle: exercise.primaryMuscle,
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

    /// Writes one set's weight and nothing else. This is the per-keystroke path:
    /// carrying down while the user is still typing turns "80" into 8 kg on every
    /// set below on the first keystroke, and the second keystroke cannot take it
    /// back because those sets are no longer empty.
    public mutating func setWeight(_ weight: Double?, exercise: Int, set: Int) {
        guard exercises.indices.contains(exercise),
              exercises[exercise].sets.indices.contains(set) else { return }
        exercises[exercise].sets[set].weightKg = weight
    }

    /// Commit — the field lost focus or was submitted. Fills all subsequent
    /// uncompleted sets below it, so adjusting weight on set 1 cascades to 2-5,
    /// and increasing weight on set 2 cascades to 3-5 without manual retyping.
    public mutating func commitWeight(_ weight: Double?, exercise: Int, set: Int) {
        guard exercises.indices.contains(exercise),
              exercises[exercise].sets.indices.contains(set) else { return }

        exercises[exercise].sets[set].weightKg = weight
        guard let weight else { return }

        for index in (set + 1)..<exercises[exercise].sets.count {
            if !exercises[exercise].sets[index].completed {
                exercises[exercise].sets[index].weightKg = weight
            }
        }
    }

    /// Appends an extra set to an exercise, inheriting the last set's weight and reps.
    public mutating func addSet(to exerciseIndex: Int) {
        guard exercises.indices.contains(exerciseIndex) else { return }
        let currentSets = exercises[exerciseIndex].sets
        let nextNumber = (currentSets.last?.setNumber ?? 0) + 1
        let lastWeight = currentSets.last?.weightKg
        let lastReps = currentSets.last?.reps ?? 10
        exercises[exerciseIndex].sets.append(
            DraftSet(setNumber: nextNumber, weightKg: lastWeight, reps: lastReps, completed: false)
        )
    }

    /// Removes a specific set and renumbers the remaining sets.
    public mutating func removeSet(at setIndex: Int, from exerciseIndex: Int) {
        guard exercises.indices.contains(exerciseIndex),
              exercises[exerciseIndex].sets.indices.contains(setIndex),
              exercises[exerciseIndex].sets.count > 1 else { return }
        exercises[exerciseIndex].sets.remove(at: setIndex)
        for i in exercises[exerciseIndex].sets.indices {
            let old = exercises[exerciseIndex].sets[i]
            exercises[exerciseIndex].sets[i] = DraftSet(
                setNumber: i + 1,
                weightKg: old.weightKg,
                reps: old.reps,
                rpe: old.rpe,
                completed: old.completed
            )
        }
    }
}
extension WorkoutDraft {
    /// Every set is sent, finished or not, so resuming restores the full checklist.
    /// `completed` is what the server uses to compute volume.
    private var wireExercises: [ExecutedExerciseLog] {
        exercises.map { exercise in
            ExecutedExerciseLog(
                exerciseId: exercise.exerciseId,
                exerciseName: exercise.exerciseName,
                sets: exercise.sets.map { set in
                    LoggedSet(
                        setNumber: set.setNumber,
                        weightKg: set.weightKg ?? 0,   // bodyweight logs as 0
                        reps: set.reps,
                        rpe: set.rpe,
                        completed: set.completed
                    )
                }
            )
        }
    }

    public func makeUpdateRequest() -> ActiveSessionUpdateRequest {
        ActiveSessionUpdateRequest(
            programId: programId,
            dayNumber: dayNumber,
            startedAt: startedAt,
            completedExercises: wireExercises
        )
    }

    public func makeSessionLog(loggedAt: Int, notes: String?) -> WorkoutSessionLog {
        WorkoutSessionLog(
            programId: programId,
            dayNumber: dayNumber,
            loggedAt: loggedAt,
            durationSeconds: max(0, loggedAt - startedAt),
            completedExercises: wireExercises,
            sessionNotes: notes
        )
    }

    public var completedSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count(where: \.completed) }
    }

    public var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    public var completedExerciseCount: Int {
        exercises.filter { ex in !ex.sets.isEmpty && ex.sets.allSatisfy(\.completed) }.count
    }

    public var totalExerciseCount: Int {
        exercises.count
    }

    public var progressFraction: Double {
        totalSetCount > 0 ? Double(completedSetCount) / Double(totalSetCount) : 0.0
    }
}
