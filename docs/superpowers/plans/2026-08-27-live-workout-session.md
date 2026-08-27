# Live Workout Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user run a workout from a saved program — follow prescribed sets, check them off, and get a server-computed volume report.

**Architecture:** A custom expanding container (collapsed bar ↔ full screen) driven by one continuous `progress` value, so content tracks the drag 1:1. Workout state lives in a `WorkoutSessionStore` owned by `AppEnvironment` so it outlives the screen. Pure draft logic lives in ReelsKit and is unit-tested without a simulator.

**Tech Stack:** Swift 6.2, SwiftUI (iOS 18), Swift Testing, XcodeGen, local SPM package `ReelsKit`.

**Spec:** `docs/superpowers/specs/2026-08-27-live-workout-session-design.md`

## Global Constraints

- **`ReelsKit` must not import UIKit or SwiftUI.** It declares a macOS platform so `swift test` runs without a simulator; a UI import breaks that.
- **Run `make generate` after creating any new file** or the Xcode build will not see it. Sources are picked up by directory.
- **Test framework is Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`) — not XCTest.
- **Never nest `#require` inside `#require`** — it causes "recursive expansion of macro". Bind to a local first.
- **`@MainActor` test helpers:** any free function constructing a `@MainActor` type must itself be marked `@MainActor`, or the call fails to compile.
- **`testConfig` in ReelsKit tests has `apiStagePath: "/dev"`.** URL assertions must include that prefix. The real app config has an empty stage path.
- **Simulator is `iPhone 17 Pro`.**
- **Precondition:** this repo currently has **zero commits** with ~40 files staged. Make a baseline commit of the existing scaffold before Task 1, so each task's commit is reviewable.

**Existing types this plan builds on** (all in `ReelsKit`, already implemented and tested):

```swift
struct WorkoutDay { let dayNumber: Int; var dayTitle: String; let dayFocus: String?
                   let targetMuscleGroups: [String]; var exerciseGroups: [ExerciseGroup] }
struct ExerciseGroup { let category: GroupCategory; let targetRegion: String?
                       var exercises: [StructuredExercise] }
struct StructuredExercise { let exerciseId: String; var canonicalNameKo: String
                            var canonicalNameEn: String; let equipment: EquipmentType
                            let primaryMuscle: String; let secondaryMuscles: [String]
                            let isMainLift: Bool; var volume: PrescribedVolume
                            let guide: CoachingGuide? }
struct PrescribedVolume { var minSets: Int; var maxSets: Int; var minReps: Int
                          var maxReps: Int?; var repType: RepType; var restSeconds: Int?
                          var weightGuidance: String?; var rpeTarget: Double?
                          var volumeDisplayString: String }
struct LoggedSet { let setNumber: Int; var weightKg: Double   // NON-optional
                   var reps: Int; var rpe: Double?; var completed: Bool }
struct ExecutedExerciseLog { let exerciseId: String; let exerciseName: String
                             var sets: [LoggedSet] }
struct ActiveSessionUpdateRequest { let programId: String; let dayNumber: Int
                                    let startedAt: Int
                                    var completedExercises: [ExecutedExerciseLog] }
struct WorkoutSessionLog { let sessionId: String?; let programId: String
                           let dayNumber: Int; let loggedAt: Int?
                           let durationSeconds: Int?
                           var completedExercises: [ExecutedExerciseLog]
                           var volumeAnalytics: WorkoutVolumeAnalytics?
                           var sessionNotes: String? }
struct WorkoutVolumeAnalytics { let totalVolumeKg: Double; let totalSetsCompleted: Int
                                let totalRepsCompleted: Int
                                let exerciseBreakdown: [ExerciseVolumeAnalytics] }
```

`APIClient` methods available: `saveActiveSession(_:)`, `activeSession()`,
`discardActiveSession()`, `logSession(_:)`, `substituteExercise(_:)`, `program(id:)`.

**Key constraint driving Task 2:** `LoggedSet.weightKg` is a non-optional `Double`,
but the UI must show an *empty* weight field until the user types one. The draft
therefore uses its own `DraftSet` with `weightKg: Double?` and converts to
`LoggedSet` (nil → `0`) only when building a request.

---

### Task 1: Container prototype (throwaway)

Builds the expanding container with dummy content so its feel can be judged by hand
before real content goes inside. **This task has no unit tests** — motion is verified
by holding it (spec §5, "the motion is not unit-testable").

**Files:**
- Create: `ReelsWorkout/Features/Workout/WorkoutContainer.swift`
- Modify: `ReelsWorkout/Features/Library/LibraryView.swift` (temporary preview hook, removed in Task 9)

**Interfaces:**
- Consumes: nothing
- Produces: `struct WorkoutContainer<Bar: View, Expanded: View>: View` with
  `init(isPresented: Binding<Bool>, @ViewBuilder bar: () -> Bar, @ViewBuilder expanded: () -> Expanded)`

- [ ] **Step 1: Create the container**

```swift
import SwiftUI

/// Collapsed bar ↔ full screen, driven by one continuous `progress` value so the
/// content inside tracks the drag 1:1 rather than switching at a threshold.
struct WorkoutContainer<Bar: View, Expanded: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let bar: () -> Bar
    @ViewBuilder let expanded: () -> Expanded

    /// 0 = collapsed bar, 1 = full screen. Everything is a function of this.
    @State private var progress: Double = 0
    @State private var dragStartProgress: Double?
    @State private var animation: SpringRun?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight: CGFloat = 76
    private let spring = Spring(duration: 0.3, bounce: 0.2)

    /// An in-flight spring, evaluated per frame so velocity can be handed off and
    /// sampled again on interruption.
    private struct SpringRun {
        let from: Double, to: Double, velocity: Double, start: Date
    }

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.height - barHeight
            let height = barHeight + progress * travel

            ZStack(alignment: .top) {
                bar().opacity(1 - min(1, progress * 2))
                expanded().opacity(max(0, progress * 2 - 1))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 16 + progress * 22))
            .shadow(color: .black.opacity(0.12 + progress * 0.18),
                    radius: 8 + progress * 20, y: -2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .gesture(drag(travel: travel))
            .overlay { springDriver }
        }
        .ignoresSafeArea(edges: .bottom)
        .opacity(isPresented ? 1 : 0)
        .allowsHitTesting(isPresented)
    }

    /// Evaluates the spring per frame so release velocity flows straight into the
    /// animation. `withAnimation` cannot inject initial velocity, which would
    /// leave a visible seam the instant the finger lifts.
    @ViewBuilder
    private var springDriver: some View {
        if let run = animation {
            TimelineView(.animation) { timeline in
                Color.clear
                    .onChange(of: timeline.date, initial: true) { _, now in
                        let t = now.timeIntervalSince(run.start)
                        if t >= spring.settlingDuration {
                            progress = run.to
                            animation = nil
                        } else {
                            progress = spring.value(fromValue: run.from, toValue: run.to,
                                                    initialVelocity: run.velocity, time: t)
                        }
                    }
            }
            .allowsHitTesting(false)
        }
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartProgress == nil {
                    // Interruption: adopt the in-flight position, kill the spring.
                    dragStartProgress = progress
                    animation = nil
                }
                let raw = (dragStartProgress ?? 0) - value.translation.height / travel
                progress = clampWithRubberband(raw)
            }
            .onEnded { value in
                let start = dragStartProgress ?? progress
                dragStartProgress = nil

                // Project where the flick was going, then snap to the nearer end.
                let projected = start - value.predictedEndTranslation.height / travel
                let target: Double = projected > 0.5 ? 1 : 0
                let velocity = -value.velocity.height / travel

                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2)) { progress = target }
                } else {
                    animation = SpringRun(from: progress, to: target,
                                          velocity: velocity, start: .now)
                }
            }
    }

    /// Progressive resistance past either end instead of a hard stop.
    private func clampWithRubberband(_ value: Double) -> Double {
        if value > 1 { return 1 + rubberband(value - 1) }
        if value < 0 { return -rubberband(-value) }
        return value
    }

    private func rubberband(_ overshoot: Double, constant: Double = 0.55) -> Double {
        (overshoot * constant) / (1 + constant * abs(overshoot))
    }
}
```

- [ ] **Step 2: Add a preview with dummy content**

Append to `WorkoutContainer.swift`:

```swift
#if DEBUG
private struct ContainerDemo: View {
    @State private var presented = true
    var body: some View {
        ZStack {
            List(1..<20) { Text("라이브러리 항목 \($0)") }
            WorkoutContainer(isPresented: $presented) {
                HStack {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("Day 1 푸쉬").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("32:14").font(.subheadline.monospacedDigit())
                }
                .padding(.horizontal, 20).padding(.top, 18)
            } expanded: {
                VStack(spacing: 12) {
                    Capsule().fill(.secondary).frame(width: 36, height: 5).padding(.top, 8)
                    Text("확장된 운동 화면").font(.title2.bold())
                    ForEach(1..<6) { Text("세트 \($0)") }
                    Spacer()
                }
            }
        }
    }
}

#Preview("Container") { ContainerDemo() }
#endif
```

- [ ] **Step 3: Regenerate and build**

```bash
make generate
xcodebuild build -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: HAND-REVIEW GATE — stop and get feedback**

Open `WorkoutContainer.swift` in Xcode, run the "Container" preview in Live mode,
and drag the bar. Check by hand:
- Dragging tracks the finger 1:1 with no lag
- A flick upward throws it open; a slow drag past halfway settles open
- Grabbing it mid-flight stops it dead and follows the finger, with no jump
- Pulling past the top resists instead of stopping hard

**Do not proceed to Task 2 until a human confirms the feel.** If it is wrong, fix
here — every later task builds on this container.

- [ ] **Step 5: Commit**

```bash
git add ReelsWorkout/Features/Workout/WorkoutContainer.swift
git commit -m "feat: add expanding workout container with velocity-aware spring"
```

---

### Task 2: WorkoutDraft — seeding and weight carry-down

**Files:**
- Create: `ReelsKit/Sources/ReelsKit/Models/WorkoutDraft.swift`
- Test: `ReelsKit/Tests/ReelsKitTests/WorkoutDraftTests.swift`

**Interfaces:**
- Consumes: `WorkoutDay`, `StructuredExercise`, `PrescribedVolume`, `EquipmentType` (existing)
- Produces:
  - `struct DraftSet { let setNumber: Int; var weightKg: Double?; var reps: Int; var rpe: Double?; var completed: Bool }`
  - `struct DraftExercise { let exerciseId: String; let exerciseName: String; let equipment: EquipmentType; let restSeconds: Int?; let prescription: String; var sets: [DraftSet] }`
  - `struct WorkoutDraft { let programId: String; let dayNumber: Int; let dayTitle: String; let startedAt: Int; var exercises: [DraftExercise] }`
  - `static func WorkoutDraft.seed(programId: String, day: WorkoutDay, startedAt: Int) -> WorkoutDraft`
  - `mutating func WorkoutDraft.setWeight(_ weight: Double?, exercise: Int, set: Int)`

- [ ] **Step 1: Write the failing tests**

Create `ReelsKit/Tests/ReelsKitTests/WorkoutDraftTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ReelsKit && swift test --filter "WorkoutDraft"
```
Expected: FAIL — `cannot find 'WorkoutDraft' in scope`

- [ ] **Step 3: Write the implementation**

Create `ReelsKit/Sources/ReelsKit/Models/WorkoutDraft.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ReelsKit && swift test --filter "WorkoutDraft"
```
Expected: PASS, 7 tests

Note: `preservesExplicitWeights` passes because carry-down only fills sets whose
weight is `nil`. After the first `setWeight(80,…)` all four are `80`, so the later
re-edit of set 1 fills nothing.

- [ ] **Step 5: Commit**

```bash
git add ReelsKit/Sources/ReelsKit/Models/WorkoutDraft.swift \
        ReelsKit/Tests/ReelsKitTests/WorkoutDraftTests.swift
git commit -m "feat: add WorkoutDraft seeding and weight carry-down"
```

---

### Task 3: WorkoutDraft → wire conversion

**Files:**
- Modify: `ReelsKit/Sources/ReelsKit/Models/WorkoutDraft.swift`
- Modify: `ReelsKit/Tests/ReelsKitTests/WorkoutDraftTests.swift`

**Interfaces:**
- Consumes: `WorkoutDraft` (Task 2), `ActiveSessionUpdateRequest`, `WorkoutSessionLog`, `ExecutedExerciseLog`, `LoggedSet`
- Produces:
  - `func WorkoutDraft.makeUpdateRequest() -> ActiveSessionUpdateRequest`
  - `func WorkoutDraft.makeSessionLog(loggedAt: Int, notes: String?) -> WorkoutSessionLog`
  - `var WorkoutDraft.completedSetCount: Int`

- [ ] **Step 1: Write the failing tests**

Append to `ReelsKit/Tests/ReelsKitTests/WorkoutDraftTests.swift`:

```swift
@Suite("WorkoutDraft wire conversion")
struct WorkoutDraftWireTests {

    private func loggedDraft() -> WorkoutDraft {
        var d = WorkoutDraft.seed(
            programId: "p1",
            day: makeDay([makeExercise(id: "bench", sets: 3, minReps: 8, maxReps: 10)]),
            startedAt: 1771979000
        )
        d.setWeight(80, exercise: 0, set: 0)
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ReelsKit && swift test --filter "wire conversion"
```
Expected: FAIL — `value of type 'WorkoutDraft' has no member 'makeUpdateRequest'`

- [ ] **Step 3: Write the implementation**

Append inside `extension WorkoutDraft` in `WorkoutDraft.swift`:

```swift
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
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ReelsKit && swift test --filter "WorkoutDraft"
```
Expected: PASS, 11 tests total

- [ ] **Step 5: Commit**

```bash
git add ReelsKit/Sources/ReelsKit/Models/WorkoutDraft.swift \
        ReelsKit/Tests/ReelsKitTests/WorkoutDraftTests.swift
git commit -m "feat: convert WorkoutDraft to active-session and session-log payloads"
```

---

### Task 4: WorkoutSessionStore — start, mutate, debounced sync

**Files:**
- Create: `ReelsWorkout/Features/Workout/WorkoutSessionStore.swift`
- Test: `ReelsWorkoutTests/WorkoutSessionStoreTests.swift`

**Interfaces:**
- Consumes: `WorkoutDraft`, `APIClient`, `ActiveSessionUpdateResponse`
- Produces:
  - `@MainActor @Observable final class WorkoutSessionStore`
  - `init(client: APIClient, draft: WorkoutDraft)`
  - `var draft: WorkoutDraft` (read-only outside)
  - `var analytics: WorkoutVolumeAnalytics?`
  - `func completeSet(exercise: Int, set: Int)`
  - `func setWeight(_ weight: Double?, exercise: Int, set: Int)`
  - `func setReps(_ reps: Int, exercise: Int, set: Int)`
  - `func setRPE(_ rpe: Double?, exercise: Int, set: Int)`
  - `func flushPendingSave() async`
  - `var restEndsAt: Date?`

- [ ] **Step 1: Write the failing tests**

Create `ReelsWorkoutTests/WorkoutSessionStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import ReelsWorkout
import ReelsKit

/// Counts calls per path suffix so debounce behaviour can be asserted.
private final class CountingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }

    let body: String
    init(body: String = #"{"success":true}"#) { self.body = body }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _calls.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")") }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

@MainActor
private func makeStore(
    transport: CountingTransport, sets: Int = 3
) -> WorkoutSessionStore {
    let config = AppConfig(apiHost: "test.example.com", appSecret: "s",
                           appGroupID: "group.test")
    let client = APIClient(config: config, transport: transport) { "lifter@example.com" }

    let exercise = StructuredExercise(
        exerciseId: "bench", canonicalNameKo: "벤치프레스", canonicalNameEn: "Bench Press",
        equipment: .barbell, primaryMuscle: "대흉근", secondaryMuscles: [], isMainLift: true,
        volume: PrescribedVolume(minSets: sets, maxSets: sets, minReps: 8, maxReps: 10,
                                 repType: .repsRange, restSeconds: 120,
                                 weightGuidance: nil, rpeTarget: nil),
        guide: nil
    )
    let day = WorkoutDay(dayNumber: 1, dayTitle: "Day 1: 푸쉬", dayFocus: nil,
                         targetMuscleGroups: [],
                         exerciseGroups: [ExerciseGroup(category: .mainCompound,
                                                        targetRegion: nil,
                                                        exercises: [exercise])])
    let draft = WorkoutDraft.seed(programId: "p1", day: day, startedAt: 1_000)
    return WorkoutSessionStore(client: client, draft: draft)
}

@MainActor
@Suite("WorkoutSessionStore")
struct WorkoutSessionStoreTests {

    @Test("Completing a set flushes immediately rather than waiting for the debounce")
    func completeFlushesNow() async {
        let transport = CountingTransport()
        let store = makeStore(transport: transport)

        store.completeSet(exercise: 0, set: 0)
        await store.flushPendingSave()

        #expect(store.draft.exercises[0].sets[0].completed)
        #expect(transport.calls == ["PUT /sessions/active"])
    }

    @Test("Rapid weight edits coalesce into a single save")
    func editsCoalesce() async {
        let transport = CountingTransport()
        let store = makeStore(transport: transport)

        store.setWeight(80, exercise: 0, set: 0)
        store.setWeight(82.5, exercise: 0, set: 0)
        store.setWeight(85, exercise: 0, set: 0)
        await store.flushPendingSave()

        #expect(transport.calls.count == 1)
        #expect(store.draft.exercises[0].sets[0].weightKg == 85)
    }

    @Test("Weight carry-down happens through the store too")
    func carriesWeightDown() async {
        let transport = CountingTransport()
        let store = makeStore(transport: transport)

        store.setWeight(80, exercise: 0, set: 0)

        #expect(store.draft.exercises[0].sets.map(\.weightKg) == [80, 80, 80])
    }

    @Test("Completing a set starts a rest countdown from the prescription")
    func startsRestTimer() async {
        let transport = CountingTransport()
        let store = makeStore(transport: transport)

        #expect(store.restEndsAt == nil)
        store.completeSet(exercise: 0, set: 0)

        let endsAt = try? #require(store.restEndsAt)
        #expect(endsAt != nil)
        // restSeconds is 120 in the fixture.
        #expect(abs(endsAt!.timeIntervalSinceNow - 120) < 2)
    }

    @Test("Un-completing a set clears the rest countdown")
    func uncompleteClearsRest() async {
        let transport = CountingTransport()
        let store = makeStore(transport: transport)

        store.completeSet(exercise: 0, set: 0)
        store.completeSet(exercise: 0, set: 0)   // toggles back off

        #expect(!store.draft.exercises[0].sets[0].completed)
        #expect(store.restEndsAt == nil)
    }

    @Test("A failed save does not surface an error or lose local state")
    func saveFailureIsSilent() async {
        let transport = CountingTransport(body: "nope")   // undecodable body
        let store = makeStore(transport: transport)

        store.setWeight(80, exercise: 0, set: 0)
        await store.flushPendingSave()

        #expect(store.draft.exercises[0].sets[0].weightKg == 80)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ReelsWorkoutTests/WorkoutSessionStoreTests CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `cannot find 'WorkoutSessionStore' in scope`

- [ ] **Step 3: Write the implementation**

Create `ReelsWorkout/Features/Workout/WorkoutSessionStore.swift`:

```swift
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
```

- [ ] **Step 4: Regenerate, then run the tests to verify they pass**

```bash
make generate
xcodebuild test -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ReelsWorkoutTests/WorkoutSessionStoreTests CODE_SIGNING_ALLOWED=NO
```
Expected: PASS, 6 tests

- [ ] **Step 5: Commit**

```bash
git add ReelsWorkout/Features/Workout/WorkoutSessionStore.swift \
        ReelsWorkoutTests/WorkoutSessionStoreTests.swift project.yml
git commit -m "feat: add WorkoutSessionStore with debounced draft sync"
```

---

### Task 5: Finish, discard, and resume

**Files:**
- Modify: `ReelsWorkout/Features/Workout/WorkoutSessionStore.swift`
- Modify: `ReelsWorkoutTests/WorkoutSessionStoreTests.swift`

**Interfaces:**
- Consumes: `WorkoutSessionStore` (Task 4), `APIClient.logSession(_:)`, `.discardActiveSession()`, `.activeSession()`, `.program(id:)`
- Produces:
  - `enum WorkoutFinishState { case idle, saving, finished(WorkoutSessionLog), failed(String) }`
  - `var WorkoutSessionStore.finishState: WorkoutFinishState`
  - `func WorkoutSessionStore.finish(notes: String?) async`
  - `func WorkoutSessionStore.discard() async`
  - `static func WorkoutSessionStore.resume(client: APIClient) async -> WorkoutSessionStore?`
  - `var WorkoutSessionStore.isOrphaned: Bool` — draft whose program no longer exists

- [ ] **Step 1: Write the failing tests**

Append to `ReelsWorkoutTests/WorkoutSessionStoreTests.swift`:

```swift
/// Routes by "METHOD /path" so finish/discard/resume can be scripted separately.
private final class RouteTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }

    let routes: [String: (Int, String)]
    init(_ routes: [String: (Int, String)]) { self.routes = routes }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
        lock.withLock { _calls.append(key) }
        let (status, body) = routes[key] ?? (404, #"{"error":"no stub"}"#)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

@MainActor
private func makeClient(_ transport: any HTTPTransport) -> APIClient {
    let config = AppConfig(apiHost: "test.example.com", appSecret: "s",
                           appGroupID: "group.test")
    return APIClient(config: config, transport: transport) { "lifter@example.com" }
}

@MainActor
@Suite("WorkoutSessionStore lifecycle")
struct WorkoutSessionLifecycleTests {

    private static let finishBody = #"""
    {"success":true,"session_id":"s1","session":{"session_id":"s1","program_id":"p1",
     "day_number":1,"duration_seconds":3600,"completed_exercises":[],
     "volume_analytics":{"total_volume_kg":3555.0,"total_sets_completed":5,
     "total_reps_completed":42,"exercise_breakdown":[]}}}
    """#

    @Test("Finishing posts the session and exposes the server's volume report")
    func finishSucceeds() async {
        let transport = RouteTransport([
            "PUT /sessions/active": (200, #"{"success":true}"#),
            "POST /sessions": (201, Self.finishBody)
        ])
        let store = makeStore(transport: CountingTransport())
        let finishing = WorkoutSessionStore(client: makeClient(transport),
                                            draft: store.draft)

        await finishing.finish(notes: nil)

        guard case .finished(let log) = finishing.finishState else {
            Issue.record("expected .finished, got \(finishing.finishState)")
            return
        }
        #expect(log.volumeAnalytics?.totalVolumeKg == 3555)
        #expect(transport.calls.contains("POST /sessions"))
    }

    @Test("A failed finish surfaces an error and keeps the draft for retry")
    func finishFailureSurfaces() async {
        let transport = RouteTransport(["POST /sessions": (500, #"{"message":"boom"}"#)])
        let store = WorkoutSessionStore(client: makeClient(transport),
                                        draft: makeStore(transport: CountingTransport()).draft)

        await store.finish(notes: nil)

        guard case .failed = store.finishState else {
            Issue.record("expected .failed, got \(store.finishState)")
            return
        }
        #expect(store.draft.exercises.count == 1)   // draft retained
    }

    @Test("Discarding sends DELETE")
    func discardSendsDelete() async {
        let transport = RouteTransport([
            "DELETE /sessions/active": (200, #"{"success":true,"deleted":true}"#)
        ])
        let store = WorkoutSessionStore(client: makeClient(transport),
                                        draft: makeStore(transport: CountingTransport()).draft)

        await store.discard()

        #expect(transport.calls == ["DELETE /sessions/active"])
    }

    @Test("Resume returns nil when the server has no draft")
    func resumeWithNoDraft() async {
        let transport = RouteTransport([
            "GET /sessions/active": (404, #"{"has_active_session":false}"#)
        ])

        let store = await WorkoutSessionStore.resume(client: makeClient(transport))

        #expect(store == nil)
    }

    @Test("Resume rebuilds the draft from the server plus the program")
    func resumeRebuilds() async {
        let active = #"""
        {"has_active_session":true,"active_session":{"program_id":"p1","day_number":1,
         "started_at":1000,"user_id":"lifter@example.com",
         "session_data":{"program_id":"p1","day_number":1,"completed_exercises":[
           {"exercise_id":"bench","exercise_name":"벤치프레스","sets":[
             {"set_number":1,"weight_kg":80,"reps":10,"completed":true},
             {"set_number":2,"weight_kg":80,"reps":10,"completed":false}]}]}}}
        """#
        let program = #"""
        {"program_id":"p1","title":"체단실","program_data":{"days":[{"day_number":1,
         "day_title":"Day 1: 푸쉬","target_muscle_groups":[],"exercise_groups":[
         {"category":"Main Compound (메인 복합 다관절 운동)","exercises":[
         {"exercise_id":"bench","canonical_name_ko":"벤치프레스",
          "canonical_name_en":"Bench Press","equipment":"Barbell (바벨)",
          "primary_muscle":"대흉근","secondary_muscles":[],"is_main_lift":true,
          "volume":{"min_sets":2,"max_sets":2,"min_reps":8,"max_reps":10,
                    "rep_type":"Reps Range (반복 횟수 범위)","rest_seconds":120}}]}]}]}}
        """#
        let transport = RouteTransport([
            "GET /sessions/active": (200, active),
            "GET /programs/p1": (200, program)
        ])

        let store = await WorkoutSessionStore.resume(client: makeClient(transport))

        let resumed = try? #require(store)
        #expect(resumed != nil)
        #expect(resumed?.draft.startedAt == 1000)
        #expect(resumed?.draft.exercises[0].sets[0].completed == true)
        #expect(resumed?.draft.exercises[0].sets[0].weightKg == 80)
        #expect(resumed?.isOrphaned == false)
    }

    @Test("Resume survives a draft whose program no longer exists")
    func resumeWithDeadProgram() async {
        let active = #"""
        {"has_active_session":true,"active_session":{"program_id":"prog_test_123",
         "day_number":1,"started_at":1000,"user_id":"lifter@example.com",
         "session_data":{"program_id":"prog_test_123","day_number":1,
         "completed_exercises":[{"exercise_id":"bench","exercise_name":"벤치프레스",
         "sets":[{"set_number":1,"weight_kg":80,"reps":10,"completed":true}]}]}}}
        """#
        let transport = RouteTransport([
            "GET /sessions/active": (200, active),
            "GET /programs/prog_test_123": (404, #"{"error":"not found"}"#)
        ])

        let store = await WorkoutSessionStore.resume(client: makeClient(transport))

        let resumed = try? #require(store)
        #expect(resumed?.isOrphaned == true)
        // Still shows what was logged, so discarding is an informed choice.
        #expect(resumed?.draft.exercises[0].sets.count == 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ReelsWorkoutTests/WorkoutSessionLifecycleTests CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `type 'WorkoutSessionStore' has no member 'resume'`

- [ ] **Step 3: Write the implementation**

Append to `WorkoutSessionStore.swift`:

```swift
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
            dayTitle: "이어하기", startedAt: startedAt,
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
```

Then add these stored properties to the class body in `WorkoutSessionStore`
(alongside `restEndsAt`), and relax `saveTask` so the extension can reach it:

```swift
    var finishState: WorkoutFinishState = .idle
    private(set) var isOrphaned = false
```

No access-level changes are needed: the extension lives in the same file as the
class, and Swift lets same-file extensions reach `private` members. `isOrphaned`
uses `private(set)` so `WorkoutBar` in another file can read it.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ReelsWorkoutTests CODE_SIGNING_ALLOWED=NO
```
Expected: PASS, all suites

- [ ] **Step 5: Commit**

```bash
git add ReelsWorkout/Features/Workout/WorkoutSessionStore.swift \
        ReelsWorkoutTests/WorkoutSessionStoreTests.swift
git commit -m "feat: add workout finish, discard, and resume-from-server"
```

---

### Task 6: SetRow

The highest-frequency interaction. No unit tests — this is view code whose value is
in feel; correctness of the underlying mutations is covered by Task 4.

**Files:**
- Create: `ReelsWorkout/Features/Workout/SetRow.swift`

**Interfaces:**
- Consumes: `DraftSet` (Task 2)
- Produces:
  - `struct WorkoutFieldID: Hashable` with `enum Kind { case weight, reps }`, `init(exercise: Int, set: Int, kind: Kind)`
  - `struct SetRow: View` with
    `init(set: DraftSet, exerciseIndex: Int, setIndex: Int, isRPEExpanded: Bool, focused: FocusState<WorkoutFieldID?>.Binding, onToggle: () -> Void, onWeight: (Double?) -> Void, onReps: (Int) -> Void, onRPE: (Double?) -> Void, onToggleRPE: () -> Void)`

- [ ] **Step 1: Create the row**

```swift
import ReelsKit
import SwiftUI

/// One set. Press feedback fires on touch-*down*; the haptic generator is primed
/// there too, so the tap and the tap-back land on the same frame.
/// Identifies one text field across the whole workout, so the keyboard toolbar
/// can step 이전/다음 between rows and exercises.
struct WorkoutFieldID: Hashable {
    enum Kind { case weight, reps }
    let exercise: Int
    let set: Int
    let kind: Kind
}

struct SetRow: View {
    let set: DraftSet
    let exerciseIndex: Int
    let setIndex: Int
    let isRPEExpanded: Bool
    @FocusState.Binding var focused: WorkoutFieldID?
    let onToggle: () -> Void
    let onWeight: (Double?) -> Void
    let onReps: (Int) -> Void
    let onRPE: (Double?) -> Void
    let onToggleRPE: () -> Void

    @State private var isPressed = false
    @State private var weightText = ""
    @State private var repsText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("\(set.setNumber)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                stepper("−2.5") { adjustWeight(by: -2.5) }

                field($weightText, placeholder: "kg", width: 62)
                    .focused($focused, equals: WorkoutFieldID(exercise: exerciseIndex,
                                                             set: setIndex, kind: .weight))
                    .onChange(of: weightText) { _, new in onWeight(Double(new)) }

                stepper("+2.5") { adjustWeight(by: 2.5) }

                field($repsText, placeholder: "회", width: 48)
                    .focused($focused, equals: WorkoutFieldID(exercise: exerciseIndex,
                                                             set: setIndex, kind: .reps))
                    .onChange(of: repsText) { _, new in if let r = Int(new) { onReps(r) } }

                Spacer(minLength: 4)

                Button(action: onToggleRPE) {
                    Text(set.rpe.map { "RPE \($0.formatted(.number.precision(.fractionLength(0...1))))" } ?? "RPE")
                        .font(.caption2)
                        .foregroundStyle(set.rpe == nil ? .secondary : .primary)
                }
                .buttonStyle(.plain)

                completionCircle
            }

            if isRPEExpanded { rpeScale }
        }
        .padding(.vertical, 6)
        .background(
            // Fills outward from the circle, so the motion starts where the finger did.
            RoundedRectangle(cornerRadius: 10)
                .fill(.tint.opacity(set.completed ? 0.10 : 0))
        )
        .onAppear {
            weightText = set.weightKg.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            repsText = "\(set.reps)"
        }
        .onChange(of: set.weightKg) { _, new in
            let text = new.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            if text != weightText { weightText = text }   // reflect carry-down
        }
    }

    private var completionCircle: some View {
        ZStack {
            Circle()
                .strokeBorder(set.completed ? Color.accentColor : .secondary.opacity(0.5),
                              lineWidth: 2)
                .background(Circle().fill(set.completed ? Color.accentColor : .clear))
                .frame(width: 30, height: 30)

            Checkmark(progress: set.completed ? 1 : 0)
                .stroke(.white, style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 12)
        }
        .scaleEffect(isPressed ? 0.94 : 1)
        .contentShape(Circle().inset(by: -10))   // ~10pt of extra hit area
        .animation(reduceMotion ? .easeOut(duration: 0.15)
                                : .spring(duration: 0.3, bounce: 0.2), value: set.completed)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let inside = Circle()
                        .path(in: CGRect(x: -10, y: -10, width: 50, height: 50))
                        .contains(value.location)
                    if inside != isPressed {
                        isPressed = inside
                        if inside { haptic.prepare() }   // prime before the lift
                    }
                }
                .onEnded { _ in
                    if isPressed { haptic.impactOccurred(); onToggle() }
                    isPressed = false
                }
        )
    }

    private var rpeScale: some View {
        HStack(spacing: 4) {
            ForEach(Array(stride(from: 6.0, through: 10.0, by: 0.5)), id: \.self) { value in
                Button {
                    onRPE(set.rpe == value ? nil : value)
                } label: {
                    Text(value.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(set.rpe == value ? Color.accentColor.opacity(0.25) : .clear,
                                    in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
        .animation(.spring(duration: 0.3, bounce: 0), value: isRPEExpanded)
    }

    private func stepper(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.caption2.monospacedDigit())
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.mini)
    }

    private func field(_ text: Binding<String>, placeholder: String, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .frame(width: width)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    private func adjustWeight(by delta: Double) {
        let current = Double(weightText) ?? 0
        let next = max(0, current + delta)
        weightText = next.formatted(.number.precision(.fractionLength(0...1)))
        onWeight(next)
    }
}

/// Strokes on rather than popping in.
private struct Checkmark: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path.trimmedPath(from: 0, to: progress)
    }
}
```

- [ ] **Step 2: Add a preview**

Append to `SetRow.swift`:

```swift
#if DEBUG
#Preview("SetRow") {
    @Previewable @State var set = DraftSet(setNumber: 1, weightKg: 80, reps: 10)
    @Previewable @State var rpeOpen = false
    @Previewable @FocusState var focused: WorkoutFieldID?

    List {
        SetRow(set: set, exerciseIndex: 0, setIndex: 0, isRPEExpanded: rpeOpen,
               focused: $focused,
               onToggle: { set.completed.toggle() },
               onWeight: { set.weightKg = $0 },
               onReps: { set.reps = $0 },
               onRPE: { set.rpe = $0 },
               onToggleRPE: { rpeOpen.toggle() })
    }
}
#endif
```

- [ ] **Step 3: Regenerate and build**

```bash
make generate
xcodebuild build -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Hand-check the preview**

Run the "SetRow" preview in Live mode. Confirm: the circle dims the instant you
touch it (not on release), the checkmark strokes on, dragging off before lifting
cancels, and ±2.5 updates the field.

- [ ] **Step 5: Commit**

```bash
git add ReelsWorkout/Features/Workout/SetRow.swift
git commit -m "feat: add set row with touch-down feedback and stroking checkmark"
```

---

### Task 7: RestTimerBar

**Files:**
- Create: `ReelsWorkout/Features/Workout/RestTimerBar.swift`

**Interfaces:**
- Consumes: `WorkoutSessionStore.restEndsAt` (Task 4)
- Produces: `struct RestTimerBar: View` with `init(endsAt: Date, onDismiss: () -> Void)`

- [ ] **Step 1: Create the bar**

```swift
import SwiftUI

/// Counts down from the program's prescribed rest. Time is derived from a
/// deadline rather than a ticking counter, so backgrounding does not desync it.
struct RestTimerBar: View {
    let endsAt: Date
    let onDismiss: () -> Void

    @State private var didFire = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let remaining = max(0, endsAt.timeIntervalSince(timeline.date))

            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)

                Text(format(remaining))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText(countsDown: true))

                ProgressView(value: remaining, total: max(1, total))
                    .tint(remaining <= 5 ? .orange : .accentColor)

                Button("건너뛰기", action: onDismiss)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .onChange(of: remaining <= 0) { _, done in
                guard done, !didFire else { return }
                didFire = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Captured once so the progress bar has a stable denominator.
    @State private var total: TimeInterval = 0

    private func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
```

- [ ] **Step 2: Fix the denominator — `total` must be set on appear**

`total` starts at `0`, which makes the progress bar wrong on first render. Add to
the `HStack`'s modifiers, right after `.background(...)`:

```swift
            .onAppear { if total == 0 { total = max(1, endsAt.timeIntervalSinceNow) } }
```

- [ ] **Step 3: Add a preview**

```swift
#if DEBUG
#Preview("RestTimerBar") {
    RestTimerBar(endsAt: .now.addingTimeInterval(12), onDismiss: {})
        .padding()
}
#endif
```

- [ ] **Step 4: Regenerate and build**

```bash
make generate
xcodebuild build -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ReelsWorkout/Features/Workout/RestTimerBar.swift
git commit -m "feat: add rest timer bar driven by a deadline"
```

---

### Task 8: WorkoutSessionView and WorkoutBar

**Files:**
- Create: `ReelsWorkout/Features/Workout/WorkoutSessionView.swift`
- Create: `ReelsWorkout/Features/Workout/WorkoutBar.swift`

**Interfaces:**
- Consumes: `WorkoutSessionStore` (Tasks 4–5), `SetRow` (Task 6), `RestTimerBar` (Task 7)
- Produces:
  - `struct WorkoutSessionView: View` with `init(store: WorkoutSessionStore, onFinish: () -> Void, onDiscard: () -> Void)`
  - `struct WorkoutBar: View` with `init(store: WorkoutSessionStore)`

- [ ] **Step 1: Create the collapsed bar**

`WorkoutBar.swift`:

```swift
import ReelsKit
import SwiftUI

/// Collapsed state of the workout container: what is running, for how long, and
/// how much has been moved. Tonnage comes from the server, never recomputed here.
struct WorkoutBar: View {
    let store: WorkoutSessionStore

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.isOrphaned ? .orange : .red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.isOrphaned ? "\(store.draft.dayTitle) · 이어하기"
                                      : store.draft.dayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let analytics = store.analytics {
                    Text(analytics.volumeSummaryString)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(elapsed(at: timeline.date))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.up").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func elapsed(at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince1970) - store.draft.startedAt)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
```

- [ ] **Step 2: Create the expanded view**

`WorkoutSessionView.swift`:

```swift
import ReelsKit
import SwiftUI

struct WorkoutSessionView: View {
    let store: WorkoutSessionStore
    let onFinish: () -> Void
    let onDiscard: () -> Void

    @State private var expandedRPE: String?
    @State private var confirmDiscard = false
    @FocusState private var focused: WorkoutFieldID?

    /// Every text field in visit order, so 이전/다음 can step across exercises.
    private var fieldOrder: [WorkoutFieldID] {
        store.draft.exercises.enumerated().flatMap { exerciseIndex, exercise in
            exercise.sets.indices.flatMap { setIndex in
                [WorkoutFieldID(exercise: exerciseIndex, set: setIndex, kind: .weight),
                 WorkoutFieldID(exercise: exerciseIndex, set: setIndex, kind: .reps)]
            }
        }
    }

    private func step(_ offset: Int) {
        guard let focused, let index = fieldOrder.firstIndex(of: focused) else { return }
        let next = index + offset
        guard fieldOrder.indices.contains(next) else { return }
        self.focused = fieldOrder[next]
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            header

            if store.isOrphaned {
                ContentUnavailableView(
                    "루틴을 찾을 수 없습니다",
                    systemImage: "questionmark.folder",
                    description: Text("이 기록이 속한 루틴이 삭제되었습니다. 삭제만 가능합니다.")
                )
            } else {
                list
            }

            footer
        }
        .overlay(alignment: .bottom) {
            if let endsAt = store.restEndsAt {
                RestTimerBar(endsAt: endsAt) { store.dismissRest() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 92)
            }
        }
        .confirmationDialog("이 운동을 삭제할까요?", isPresented: $confirmDiscard,
                            titleVisibility: .visible) {
            Button("삭제", role: .destructive, action: onDiscard)
            Button("취소", role: .cancel) {}
        } message: {
            Text("기록한 세트가 모두 사라집니다. 되돌릴 수 없습니다.")
        }
    }

    private var grabber: some View {
        Capsule().fill(.secondary.opacity(0.5))
            .frame(width: 36, height: 5).padding(.top, 8)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(store.draft.dayTitle).font(.headline)
            if let analytics = store.analytics {
                Text(analytics.volumeSummaryString)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private var list: some View {
        List {
            ForEach(Array(store.draft.exercises.enumerated()), id: \.element.id) { exerciseIndex, exercise in
                Section {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                        SetRow(
                            set: set,
                            exerciseIndex: exerciseIndex,
                            setIndex: setIndex,
                            isRPEExpanded: expandedRPE == "\(exercise.id)-\(set.setNumber)",
                            focused: $focused,
                            onToggle: { store.completeSet(exercise: exerciseIndex, set: setIndex) },
                            onWeight: { store.setWeight($0, exercise: exerciseIndex, set: setIndex) },
                            onReps: { store.setReps($0, exercise: exerciseIndex, set: setIndex) },
                            onRPE: { store.setRPE($0, exercise: exerciseIndex, set: setIndex) },
                            onToggleRPE: {
                                let key = "\(exercise.id)-\(set.setNumber)"
                                expandedRPE = expandedRPE == key ? nil : key
                            }
                        )
                        .listRowInsets(.init(top: 2, leading: 12, bottom: 2, trailing: 12))
                    }
                } header: {
                    HStack {
                        Image(systemName: exercise.equipment.iconName)
                        Text(exercise.exerciseName).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(exercise.prescription).font(.caption).foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("이전") { step(-1) }
                    .disabled(focused.flatMap { fieldOrder.firstIndex(of: $0) } == 0)
                Button("다음") { step(1) }
                    .disabled(focused.flatMap { fieldOrder.firstIndex(of: $0) }
                        == fieldOrder.count - 1)
                Spacer()
                Button("완료") { focused = nil }.fontWeight(.semibold)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("삭제", role: .destructive) { confirmDiscard = true }
                .buttonStyle(.bordered)

            Button("운동 끝내기", action: onFinish)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(store.isOrphaned)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }
}
```

- [ ] **Step 3: Regenerate and build**

```bash
make generate
xcodebuild build -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ReelsWorkout/Features/Workout/WorkoutSessionView.swift \
        ReelsWorkout/Features/Workout/WorkoutBar.swift
git commit -m "feat: add expanded workout view and collapsed bar"
```

---

### Task 9: Wire it up — environment, entry point, resume

**Files:**
- Modify: `ReelsWorkout/App/AppEnvironment.swift`
- Modify: `ReelsWorkout/Features/Library/LibraryView.swift`
- Modify: `ReelsWorkout/Features/ProgramDetail/ProgramDetailView.swift:14-30`

**Interfaces:**
- Consumes: everything from Tasks 1–8
- Produces: `AppEnvironment.workout: WorkoutSessionStore?`, `AppEnvironment.startWorkout(programId:day:)`, `AppEnvironment.endWorkout()`

- [ ] **Step 1: Add workout ownership to AppEnvironment**

In `AppEnvironment.swift`, add inside the class:

```swift
    /// The workout in progress, or nil. The bar's existence is derived from this
    /// rather than a separate flag that could drift.
    var workout: WorkoutSessionStore?

    /// True when starting a new workout would destroy an existing one — the
    /// server keeps a single draft per user, so this needs a confirmation.
    var hasWorkoutInProgress: Bool { workout != nil }

    func startWorkout(programId: String, day: WorkoutDay) {
        workout = WorkoutSessionStore(
            client: client,
            draft: .seed(programId: programId, day: day,
                         startedAt: Int(Date().timeIntervalSince1970))
        )
    }

    /// Discards the running draft server-side before replacing it.
    func replaceWorkout(programId: String, day: WorkoutDay) async {
        await workout?.discard()
        startWorkout(programId: programId, day: day)
    }

    func endWorkout() { workout = nil }

    /// Called on foreground. Does nothing if a workout is already in memory.
    func restoreWorkoutIfNeeded() async {
        guard workout == nil else { return }
        workout = await WorkoutSessionStore.resume(client: client)
    }
```

- [ ] **Step 2: Add the 시작 button to each day**

In `ProgramDetailView.swift`, replace the `DayHeader(day: day)` call in the
`header:` closure with:

```swift
                    } header: {
                        HStack {
                            DayHeader(day: day)
                            Spacer()
                            Button("시작") {
                                if environment.hasWorkoutInProgress {
                                    pendingStart = day
                                } else {
                                    environment.startWorkout(programId: programId, day: day)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .textCase(nil)
                        }
                    }
```

Add the confirmation state and dialog to `ProgramDetailView`:

```swift
    @State private var pendingStart: WorkoutDay?

    // ...attach to the List's modifiers:
        .confirmationDialog(
            "진행 중인 운동이 있습니다",
            isPresented: .init(get: { pendingStart != nil },
                               set: { if !$0 { pendingStart = nil } }),
            titleVisibility: .visible
        ) {
            Button("기존 기록 삭제하고 시작", role: .destructive) {
                if let day = pendingStart {
                    Task { await environment.replaceWorkout(programId: programId, day: day) }
                }
                pendingStart = nil
            }
            Button("취소", role: .cancel) { pendingStart = nil }
        } message: {
            Text("새 운동을 시작하면 진행 중이던 기록이 사라집니다.")
        }
```

- [ ] **Step 3: Mount the container over the library**

In `LibraryView.swift`, wrap the `NavigationStack` in a `ZStack` and add the
container. Replace the outermost `NavigationStack(path: $path) { ... }` closing
so the structure is:

```swift
    var body: some View {
        @Bindable var environment = environment

        ZStack {
            NavigationStack(path: $path) {
                // ...existing content unchanged...
            }

            if let workout = environment.workout {
                WorkoutContainer(isPresented: .constant(true)) {
                    WorkoutBar(store: workout)
                } expanded: {
                    WorkoutSessionView(
                        store: workout,
                        onFinish: { Task { await finish(workout) } },
                        onDiscard: {
                            Task {
                                await workout.discard()
                                environment.endWorkout()
                            }
                        }
                    )
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0), value: environment.workout == nil)
        .task {
            // ...existing store setup unchanged...
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store?.reloadPendingJobs()
                Task { await environment.restoreWorkoutIfNeeded() }
            }
        }
    }

    private func finish(_ workout: WorkoutSessionStore) async {
        await workout.flushPendingSave()
        await workout.finish(notes: nil)
    }
```

- [ ] **Step 4: Regenerate, build, and run both test suites**

```bash
make generate
xcodebuild test -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
cd ReelsKit && swift test
```
Expected: both PASS

- [ ] **Step 5: Run it against the real backend and hand-check**

```bash
xcodebuild build -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
xcrun simctl install "iPhone 17 Pro" \
  ~/Library/Developer/Xcode/DerivedData/ReelsWorkout-*/Build/Products/Debug-iphonesimulator/ReelsWorkout.app
xcrun simctl launch "iPhone 17 Pro" com.dongik.repreel
```

The backend holds a stale draft for `prog_test_123`, so on launch the bar should
appear in orphaned state offering only 삭제. Discard it, then start a real workout
from a program.

- [ ] **Step 6: Commit**

```bash
git add ReelsWorkout/App/AppEnvironment.swift \
        ReelsWorkout/Features/Library/LibraryView.swift \
        ReelsWorkout/Features/ProgramDetail/ProgramDetailView.swift
git commit -m "feat: wire workout container into the library and program detail"
```

---

### Task 10: ExerciseSwapSheet

**Files:**
- Create: `ReelsWorkout/Features/Workout/ExerciseSwapSheet.swift`
- Modify: `ReelsWorkout/Features/Workout/WorkoutSessionStore.swift`
- Modify: `ReelsWorkout/Features/Workout/WorkoutSessionView.swift`

**Interfaces:**
- Consumes: `APIClient.substituteExercise(_:)`, `ExerciseSubstituteItem`, `WorkoutSessionStore`
- Produces:
  - `func WorkoutSessionStore.substitutes(for exercise: Int) async throws -> [ExerciseSubstituteItem]`
  - `func WorkoutSessionStore.swap(exercise: Int, to item: ExerciseSubstituteItem)`
  - `struct ExerciseSwapSheet: View`

- [ ] **Step 1: Add swap support to the store**

Append to the `extension WorkoutSessionStore` in `WorkoutSessionStore.swift`:

```swift
    func substitutes(for exercise: Int) async throws -> [ExerciseSubstituteItem] {
        guard draft.exercises.indices.contains(exercise) else { return [] }
        let target = draft.exercises[exercise]
        let response = try await client.substituteExercise(
            ExerciseSubstituteRequest(
                exerciseName: target.exerciseName,
                targetMuscle: target.exerciseName,
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
            restSeconds: existing.restSeconds,
            prescription: item.recommendedVolume ?? existing.prescription,
            sets: existing.sets
        )
        scheduleSave()
    }
```

No access-level change is needed for `scheduleSave` — this extension is in the
same file as the class.

- [ ] **Step 2: Create the sheet**

```swift
import ReelsKit
import SwiftUI

struct ExerciseSwapSheet: View {
    let store: WorkoutSessionStore
    let exerciseIndex: Int
    let onPick: (ExerciseSubstituteItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ExerciseSubstituteItem] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ContentUnavailableView("대체 운동을 불러오지 못했습니다",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else if items.isEmpty {
                    ProgressView()
                } else {
                    List(items) { item in
                        Button {
                            onPick(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.exerciseName).font(.subheadline.weight(.semibold))
                                Text(item.equipment).font(.caption).foregroundStyle(.secondary)
                                if let rationale = item.rationale {
                                    Text(rationale).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("대체 운동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .task {
            do { items = try await store.substitutes(for: exerciseIndex) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
```

- [ ] **Step 3: Add the trigger to the exercise header**

In `WorkoutSessionView.swift`, add `@State private var swapTarget: Int?` and
replace the section `header:` closure's `Spacer()` line block with:

```swift
                        Spacer()
                        Text(exercise.prescription).font(.caption).foregroundStyle(.secondary)
                        Menu {
                            Button("대체 운동 찾기", systemImage: "arrow.triangle.swap") {
                                swapTarget = exerciseIndex
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                        }
```

And add to the view's modifiers:

```swift
        .sheet(item: Binding(get: { swapTarget.map(SwapTarget.init) },
                             set: { swapTarget = $0?.index })) { target in
            ExerciseSwapSheet(store: store, exerciseIndex: target.index) { item in
                store.swap(exercise: target.index, to: item)
            }
        }
```

with this helper at file scope:

```swift
private struct SwapTarget: Identifiable {
    let index: Int
    var id: Int { index }
}
```

- [ ] **Step 4: Regenerate and build**

```bash
make generate
xcodebuild build -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ReelsWorkout/Features/Workout/ExerciseSwapSheet.swift \
        ReelsWorkout/Features/Workout/WorkoutSessionStore.swift \
        ReelsWorkout/Features/Workout/WorkoutSessionView.swift
git commit -m "feat: add inline exercise substitution"
```

---

### Task 11: WorkoutSummaryView

**Files:**
- Create: `ReelsWorkout/Features/Workout/WorkoutSummaryView.swift`
- Modify: `ReelsWorkout/Features/Library/LibraryView.swift`

**Interfaces:**
- Consumes: `WorkoutFinishState` (Task 5), `WorkoutVolumeAnalytics`, `ExerciseVolumeAnalytics`
- Produces: `struct WorkoutSummaryView: View` with `init(log: WorkoutSessionLog, onDone: () -> Void)`

- [ ] **Step 1: Create the summary**

```swift
import ReelsKit
import SwiftUI

/// Replaces the workout's content in place, so the session becomes the report
/// rather than a new screen appearing over it.
struct WorkoutSummaryView: View {
    let log: WorkoutSessionLog
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.secondary.opacity(0.5))
                .frame(width: 36, height: 5).padding(.top, 8)

            ScrollView {
                VStack(spacing: 24) {
                    headline
                    if let breakdown = log.volumeAnalytics?.exerciseBreakdown, !breakdown.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(breakdown) { ExerciseVolumeCard(item: $0) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 32)
            }

            Button("확인", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
        }
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text("운동 완료").font(.subheadline).foregroundStyle(.secondary)

            Text(volumeText)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var volumeText: String {
        guard let total = log.volumeAnalytics?.totalVolumeKg else { return "—" }
        return "\(total.formatted(.number.precision(.fractionLength(0...1)))) kg"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let analytics = log.volumeAnalytics {
            parts.append("\(analytics.totalSetsCompleted)세트")
            parts.append("\(analytics.totalRepsCompleted)회")
        }
        if let duration = log.durationSeconds {
            parts.append("\(duration / 60)분")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ExerciseVolumeCard: View {
    let item: ExerciseVolumeAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.exerciseName).font(.subheadline.weight(.semibold))

            HStack(spacing: 14) {
                stat("볼륨", "\(item.volumeKg.formatted(.number.precision(.fractionLength(0...1)))) kg")
                if let top = item.topSetWeightKg {
                    stat("최고", "\(top.formatted(.number.precision(.fractionLength(0...1)))) kg")
                }
                if let orm = item.estimated1rmKg {
                    stat("추정 1RM", "\(orm.formatted(.number.precision(.fractionLength(0...1)))) kg")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit().weight(.medium))
        }
    }
}

#if DEBUG
#Preview("Summary") {
    WorkoutSummaryView(
        log: WorkoutSessionLog(
            sessionId: "s1", programId: "p1", dayNumber: 1, loggedAt: 1_771_982_600,
            durationSeconds: 3720, completedExercises: [], sessionNotes: nil
        ),
        onDone: {}
    )
}
#endif
```

- [ ] **Step 2: Swap the container's content on finish**

In `LibraryView.swift`, replace the `expanded:` closure of `WorkoutContainer` with:

```swift
                } expanded: {
                    Group {
                        if case .finished(let log) = workout.finishState {
                            WorkoutSummaryView(log: log) { environment.endWorkout() }
                        } else {
                            WorkoutSessionView(
                                store: workout,
                                onFinish: { Task { await finish(workout) } },
                                onDiscard: {
                                    Task {
                                        await workout.discard()
                                        environment.endWorkout()
                                    }
                                }
                            )
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: isFinished(workout))
                }
```

with this helper on `LibraryView`:

```swift
    private func isFinished(_ workout: WorkoutSessionStore) -> Bool {
        if case .finished = workout.finishState { return true }
        return false
    }
```

- [ ] **Step 3: Surface a failed finish**

Add to `WorkoutSessionView.swift`'s modifiers:

```swift
        .alert("저장하지 못했습니다", isPresented: .constant(isFailed)) {
            Button("다시 시도") { onFinish() }
            Button("취소", role: .cancel) { store.finishState = .idle }
        } message: {
            if case .failed(let message) = store.finishState { Text(message) }
        }
```

with:

```swift
    private var isFailed: Bool {
        if case .failed = store.finishState { return true }
        return false
    }
```

- [ ] **Step 4: Regenerate, build, run all tests**

```bash
make generate
xcodebuild test -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
cd ReelsKit && swift test
```
Expected: both PASS

- [ ] **Step 5: Full manual pass against the real backend**

Start a workout, log sets, finish, confirm the summary shows server tonnage, tap
확인 and confirm the container collapses away and the bar disappears.

- [ ] **Step 6: Commit**

```bash
git add ReelsWorkout/Features/Workout/WorkoutSummaryView.swift \
        ReelsWorkout/Features/Library/LibraryView.swift
git commit -m "feat: add workout summary with server volume report"
```

---

## Post-implementation

Update `CLAUDE.md`: move the live session flow out of "Not built yet", and note
that `WorkoutSessionStore` is the second feature store alongside `LibraryStore`.
