import Foundation
import Testing
@testable import ReelsKit

private func makeExercise(
    id: String, sets: Int, minReps: Int, maxReps: Int?, rest: Int? = 120
) -> StructuredExercise {
    StructuredExercise(
        exerciseId: id,
        canonicalNameKo: "벤치프레스",
        canonicalNameEn: "Bench Press",
        equipment: .barbell,
        primaryMuscle: "대흉근",
        secondaryMuscles: [],
        isMainLift: true,
        volume: PrescribedVolume(
            minSets: sets, maxSets: sets, minReps: minReps, maxReps: maxReps,
            repType: .repsRange, restSeconds: rest, weightGuidance: nil, rpeTarget: nil
        ),
        guide: nil
    )
}

private func makeDay(_ exercises: [StructuredExercise]) -> WorkoutDay {
    WorkoutDay(
        dayNumber: 1, dayTitle: "Day 1: 푸쉬", dayFocus: "가슴",
        targetMuscleGroups: ["대흉근"],
        exerciseGroups: [ExerciseGroup(category: .mainCompound,
                                       targetRegion: "가슴", exercises: exercises)]
    )
}

@Suite("WorkoutDraft seeding")
struct WorkoutDraftSeedingTests {

    @Test("Creates one row per prescribed set, targeting the top of the rep range")
    func seedsRows() {
        let day = makeDay([makeExercise(id: "bench", sets: 5, minReps: 8, maxReps: 10)])
        let draft = WorkoutDraft.seed(programId: "p1", day: day, startedAt: 100)

        #expect(draft.exercises.count == 1)
        #expect(draft.exercises[0].sets.count == 5)
        #expect(draft.exercises[0].sets.map(\.setNumber) == [1, 2, 3, 4, 5])
        #expect(draft.exercises[0].sets.allSatisfy { $0.reps == 10 })
        #expect(draft.exercises[0].sets.allSatisfy { $0.weightKg == nil })
        #expect(draft.exercises[0].sets.allSatisfy { !$0.completed })
    }

    @Test("Falls back to min reps when the program gives no upper bound")
    func seedsOpenEndedReps() {
        let day = makeDay([makeExercise(id: "pullup", sets: 4, minReps: 8, maxReps: nil)])
        let draft = WorkoutDraft.seed(programId: "p1", day: day, startedAt: 100)

        #expect(draft.exercises[0].sets.allSatisfy { $0.reps == 8 })
    }

    @Test("Flattens every group in the day into one ordered exercise list")
    func flattensGroups() {
        let day = WorkoutDay(
            dayNumber: 1, dayTitle: "Day 1", dayFocus: nil, targetMuscleGroups: [],
            exerciseGroups: [
                ExerciseGroup(category: .mainCompound, targetRegion: nil,
                              exercises: [makeExercise(id: "a", sets: 1, minReps: 5, maxReps: nil)]),
                ExerciseGroup(category: .isolation, targetRegion: nil,
                              exercises: [makeExercise(id: "b", sets: 1, minReps: 5, maxReps: nil)])
            ]
        )
        let draft = WorkoutDraft.seed(programId: "p1", day: day, startedAt: 100)

        #expect(draft.exercises.map(\.exerciseId) == ["a", "b"])
    }

    @Test("Carries the prescription string and rest seconds through for display")
    func carriesDisplayData() {
        let day = makeDay([makeExercise(id: "bench", sets: 5, minReps: 8, maxReps: 10, rest: 180)])
        let draft = WorkoutDraft.seed(programId: "p1", day: day, startedAt: 100)

        #expect(draft.exercises[0].prescription == "5세트 × 8-10회")
        #expect(draft.exercises[0].restSeconds == 180)
        #expect(draft.exercises[0].exerciseName == "벤치프레스")
    }
}

@Suite("WorkoutDraft weight carry-down")
struct WorkoutDraftCarryDownTests {

    private func draft() -> WorkoutDraft {
        WorkoutDraft.seed(
            programId: "p1",
            day: makeDay([makeExercise(id: "bench", sets: 4, minReps: 8, maxReps: 10)]),
            startedAt: 100
        )
    }

    @Test("Typing a weight fills the empty sets below it")
    func fillsBelow() {
        var d = draft()
        d.setWeight(80, exercise: 0, set: 0)

        #expect(d.exercises[0].sets.map(\.weightKg) == [80, 80, 80, 80])
    }

    @Test("Does not overwrite a weight the user already set")
    func preservesExplicitWeights() {
        var d = draft()
        d.setWeight(80, exercise: 0, set: 0)
        d.setWeight(85, exercise: 0, set: 2)   // set 3 explicit
        d.setWeight(82.5, exercise: 0, set: 0) // re-edit set 1

        // Set 3 keeps 85; sets already filled by carry-down are not re-filled.
        #expect(d.exercises[0].sets[0].weightKg == 82.5)
        #expect(d.exercises[0].sets[2].weightKg == 85)
    }

    @Test("Clearing a weight does not cascade")
    func clearingIsLocal() {
        var d = draft()
        d.setWeight(80, exercise: 0, set: 0)
        d.setWeight(nil, exercise: 0, set: 1)

        #expect(d.exercises[0].sets[1].weightKg == nil)
        #expect(d.exercises[0].sets[2].weightKg == 80)
    }
}
