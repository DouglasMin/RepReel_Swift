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
        // The substitution endpoint wants a muscle, not the exercise's own name.
        #expect(draft.exercises[0].primaryMuscle == "대흉근")
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

    @Test("Committing a weight fills the empty sets below it")
    func fillsBelow() {
        var d = draft()
        d.commitWeight(80, exercise: 0, set: 0)

        #expect(d.exercises[0].sets.map(\.weightKg) == [80, 80, 80, 80])
    }

    @Test("Typing writes only the set being typed into")
    func typingDoesNotCascade() {
        var d = draft()
        d.setWeight(80, exercise: 0, set: 0)

        #expect(d.exercises[0].sets.map(\.weightKg) == [80, nil, nil, nil])
    }

    @Test("An intermediate keystroke never reaches the sets below")
    func keystrokesDoNotCarryDown() {
        var d = draft()
        // "80" typed one digit at a time: the '8' must not land on sets 2-4,
        // because they would then be non-empty and the '0' could not correct them.
        d.setWeight(8, exercise: 0, set: 0)
        d.setWeight(80, exercise: 0, set: 0)
        d.commitWeight(80, exercise: 0, set: 0)   // focus leaves the field

        #expect(d.exercises[0].sets.map(\.weightKg) == [80, 80, 80, 80])
    }

    @Test("Editing set 2 cascades to subsequent uncompleted sets 3-4 while preserving set 1")
    func cascadesForwardToRemainingSets() {
        var d = draft()
        // Setting set 1 (80kg) cascades to sets 2-4
        d.commitWeight(80, exercise: 0, set: 0)
        #expect(d.exercises[0].sets.map(\.weightKg) == [80, 80, 80, 80])

        // Rewriting set 2 (85kg) cascades to sets 3-4 while set 1 stays 80kg
        d.commitWeight(85, exercise: 0, set: 1)
        #expect(d.exercises[0].sets.map(\.weightKg) == [80, 85, 85, 85])

        // Complete set 1 and set 2
        d.exercises[0].sets[0].completed = true
        d.exercises[0].sets[1].completed = true

        // Rewriting set 3 (90kg) cascades to set 4 while completed sets 1 and 2 are preserved
        d.commitWeight(90, exercise: 0, set: 2)
        #expect(d.exercises[0].sets.map(\.weightKg) == [80, 85, 90, 90])
    }

    @Test("Clearing a weight does not cascade")
    func clearingIsLocal() {
        var d = draft()
        d.commitWeight(80, exercise: 0, set: 0)
        d.commitWeight(nil, exercise: 0, set: 1)

        #expect(d.exercises[0].sets[1].weightKg == nil)
        #expect(d.exercises[0].sets[2].weightKg == 80)
    }
}
@Suite("WorkoutDraft wire conversion")
struct WorkoutDraftWireTests {

    private func loggedDraft() -> WorkoutDraft {
        var d = WorkoutDraft.seed(
            programId: "p1",
            day: makeDay([makeExercise(id: "bench", sets: 3, minReps: 8, maxReps: 10)]),
            startedAt: 1771979000
        )
        d.commitWeight(80, exercise: 0, set: 0)
        d.exercises[0].sets[0].completed = true
        d.exercises[0].sets[1].completed = true
        return d
    }

    @Test("Update request carries started_at and every set, complete or not")
    func buildsUpdateRequest() {
        let request = loggedDraft().makeUpdateRequest()

        #expect(request.programId == "p1")
        #expect(request.dayNumber == 1)
        #expect(request.startedAt == 1771979000)
        #expect(request.completedExercises.count == 1)
        // The server needs the unfinished rows too, so a resume restores them.
        #expect(request.completedExercises[0].sets.count == 3)
        #expect(request.completedExercises[0].sets[0].completed)
        #expect(!request.completedExercises[0].sets[2].completed)
    }

    @Test("An empty weight becomes 0 kg on the wire, for bodyweight work")
    func emptyWeightBecomesZero() {
        var d = WorkoutDraft.seed(
            programId: "p1",
            day: makeDay([makeExercise(id: "pullup", sets: 2, minReps: 8, maxReps: nil)]),
            startedAt: 100
        )
        d.exercises[0].sets[0].completed = true

        let request = d.makeUpdateRequest()
        #expect(request.completedExercises[0].sets[0].weightKg == 0)
    }

    @Test("Session log stamps logged_at and notes")
    func buildsSessionLog() {
        let log = loggedDraft().makeSessionLog(loggedAt: 1771982600, notes: "좋았음")

        #expect(log.programId == "p1")
        #expect(log.loggedAt == 1771982600)
        #expect(log.durationSeconds == 1771982600 - 1771979000)
        #expect(log.sessionNotes == "좋았음")
    }

    @Test("Counts only completed sets")
    func countsCompleted() {
        #expect(loggedDraft().completedSetCount == 2)
    }

    @Test("Adding a set appends a new set and inherits previous weight and reps")
    func addsSet() {
        var d = loggedDraft()
        #expect(d.exercises[0].sets.count == 3)

        d.addSet(to: 0)
        #expect(d.exercises[0].sets.count == 4)
        #expect(d.exercises[0].sets[3].setNumber == 4)
        #expect(d.exercises[0].sets[3].weightKg == 80)
        #expect(d.exercises[0].sets[3].reps == 10)
        #expect(d.exercises[0].sets[3].completed == false)
    }

    @Test("Calculates progress metrics correctly")
    func computesProgress() {
        var d = loggedDraft()
        #expect(d.totalSetCount == 3)
        #expect(d.completedSetCount == 2)
        #expect(d.totalExerciseCount == 1)
        #expect(d.completedExerciseCount == 0)
        #expect(d.progressFraction == 2.0 / 3.0)

        // Complete remaining set
        d.exercises[0].sets[2].completed = true
        #expect(d.completedSetCount == 3)
        #expect(d.completedExerciseCount == 1)
        #expect(d.progressFraction == 1.0)
    }
}
