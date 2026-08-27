# Live Workout Session — Design

**Date:** 2026-08-27
**Status:** Approved, ready for implementation planning

## Goal

Let the user run a workout from a saved program: follow the prescribed sets,
check them off, and get a volume report at the end. This is the last major
missing screen and the reason endpoints 11–14 exist. It also uses endpoint 10
(exercise substitution).

The backend is deployed and verified. No API work is required.

## Endpoints used

| Endpoint | Use |
| --- | --- |
| `PUT /sessions/active` | Autosave the draft on every mutation (debounced) |
| `GET /sessions/active` | On foreground, to offer resume |
| `DELETE /sessions/active` | Discard |
| `POST /sessions` | Finish; server returns `volume_analytics` |
| `POST /exercises/substitute` | Swap an exercise mid-workout |

`GET /sessions/active` answers **404 with `has_active_session: false`** when
there is no draft. `APIClient.activeSession()` already maps that to an empty
result rather than an error.

## Decisions

| Decision | Choice | Why |
| --- | --- | --- |
| Set list shape | Pre-filled from the program, weights blank | The program's prescription is the structure; typing a weight carries it down |
| Container | Custom expanding bar (not sheet detents) | Only a custom container can track content continuously during the drag |
| Completion gesture | Checklist, tap to complete | Whole exercise visible; out-of-order edits are cheap |
| Connectivity | Assume it works. No offline queue | Explicit scope call; server autosave already survives app death |
| Finish | Full summary screen | The payoff moment; the server already computes every number on it |
| v1 extras | Rest timer, RPE, inline swap | Coach Q&A deferred |

## Non-goals

Not building, by explicit decision: AI coach Q&A, a workout history screen, an
offline sync queue, a tab bar.

---

## 1. Container & motion

A single `progress: Double` drives everything — `0` is the collapsed bar, `1` is
full screen. Bar height, corner radius, header opacity, the timer's position and
size, and the library's scale behind are all pure functions of it. **Nothing
switches at a threshold.** This is the property a sheet with detents cannot
provide, because SwiftUI does not expose a sheet's live height mid-drag, and it
is the reason for a custom container.

### Dragging

`DragGesture` preserving the grab offset, mapping translation to `progress` 1:1.
Past either end, resistance rather than a hard stop:

```swift
func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
    (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
}
```

### Release

Project the flick's destination with `DragGesture.Value.predictedEndTranslation`
and snap to whichever of `0`/`1` is nearer **that projection**, not nearer the
release point. Then hand the release velocity into the spring:

```swift
let spring = Spring(duration: 0.3, bounce: 0.2)   // drawer: response 0.3, damping 0.8
progress = spring.value(fromValue: released,
                        toValue: target,
                        initialVelocity: releaseVelocity,
                        time: elapsed)
```

Evaluated per frame inside `TimelineView(.animation)`. Driving the spring
directly rather than through `withAnimation` is deliberate: `withAnimation`
offers no way to inject initial velocity, which leaves a visible seam at the
instant the finger lifts.

`Spring`, `Spring.value(fromValue:toValue:initialVelocity:time:)`,
`Spring.velocity(...)` and `Spring.settlingDuration` were compile-checked
against the iOS 18 SDK before this design was written.

### Interruption

On touch-down mid-flight, sample the live `progress` **and**
`spring.velocity(...)` at the current elapsed time, cancel the timeline, and
resume dragging from exactly there. Grabbing a closing bar makes it follow the
thumb with no jump and no wait.

### Materials

The bar and the expanded surface are one `.regularMaterial` layer whose shadow
depth and corner radius interpolate with `progress`, so it reads as a single
surface thickening as it rises. The library behind dims and scales back slightly
as `progress → 1`.

### Reduced motion

Under `accessibilityReduceMotion`, drag still tracks 1:1, but release
cross-fades over 200 ms instead of springing and the library does not scale.

---

## 2. State & draft sync

`WorkoutSessionStore` is `@MainActor @Observable`, owned by `AppEnvironment` so
it outlives the screen. The bar, the expanded view, and the summary read one
instance. It is constructed with an `APIClient`, following the existing
`LibraryStore` pattern.

```
AppEnvironment
├── client, pendingJobs, identity          (existing)
└── workout: WorkoutSessionStore?          nil when nothing is running
```

`nil` is the "no workout" state, so the bar's presence is `workout != nil`
rather than a separate flag that can drift out of sync.

### Seeding

Pure and in ReelsKit, so it is testable without a view:
`WorkoutDraft.seed(from: WorkoutDay)` turns each `StructuredExercise` into an
`ExecutedExerciseLog` with `minSets` rows, reps set to the top of the prescribed
range (`maxReps ?? minReps`), and weight empty. Typing a weight into a set fills
the empty sets below it.

### Sync

Every mutation marks the draft dirty. A trailing 750 ms debounce fires
`PUT /sessions/active`; completing a set flushes immediately instead of waiting.
Fire-and-forget with no retry queue. The response carries `volume_analytics`,
which is what the bar displays — tonnage is never recomputed locally for display.
`LoggedSet.setVolumeKg` exists only for the optimistic count between saves.

### Elapsed time

Derived from `startedAt`; nothing ticks in the store. `TimelineView(.periodic)`
renders it, so returning from background shows the correct time rather than a
frozen counter.

### Two cases that need handling

- **Starting a workout while one is running** destroys the existing draft, since
  the server keeps one per user. This gets a confirmation.
- **A draft whose program no longer exists.** The backend currently holds a stale
  draft for `prog_test_123`. Resume must survive the program fetch returning 404
  and offer discard rather than showing an error.

---

## 3. The set row

The highest-frequency interaction in the app — roughly 30 taps per session.

- **Press feedback fires on touch-down, not release.** A `Button` reports state
  too late; `DragGesture(minimumDistance: 0)` gives `onChanged` at the instant of
  contact. The circle scales to `0.94` and tints immediately. Commit happens on
  lift; dragging off the row cancels, and sliding back on re-arms it. Hit target
  extends ~10 pt past the visible circle.
- **The haptic lands on the same frame as the pixels.**
  `UIImpactFeedbackGenerator(style: .medium)`, with `prepare()` called on
  touch-down so the Taptic Engine is spun up before the finger lifts. Skipping
  `prepare()` introduces a perceptible first-use delay that breaks causality.
- **The checkmark strokes on rather than popping** — a `Path` with animated
  `trim(to:)` under `Spring(duration: 0.3, bounce: 0.2)`. Bounce is earned here
  because the thumb carried momentum into the tap.
- **The completed tint fills outward from the circle**, so the motion originates
  where the finger landed and telegraphs the outcome.
- **RPE is collapsed by default**; a tap on the trailing edge reveals a 1–10
  scale. That reveal springs with `bounce: 0` — no gesture momentum preceded it.
- **Empty weight is legal.** Bodyweight is a real equipment type; a completed set
  with no weight logs 0 kg. Completion validates reps, not weight.
- **Weight field is flanked by ±2.5 kg steppers** — the smallest plate pair, and
  the most tedious thing to type one-handed.
- **Keyboard** is `.decimalPad` with an 이전/다음/완료 toolbar so a column can be
  filled without dismissing. The rest-timer bar sits above the keyboard.

---

## 4. Screens & flow

**Starting.** Each Day header in `ProgramDetailView` gets a 시작 button. Tapping
seeds the draft, creates the store, and the container rises from the bottom edge
already expanded.

**Resuming.** No launch dialog. On `scenePhase == .active`, call
`GET /sessions/active`; if a draft returns, the collapsed bar appears reading
`Day 1 푸쉬 · 이어하기`. Tap to expand into it; swipe down and use 삭제 to
discard. This offers rather than interrupts. If the draft's program 404s, the bar
offers only discard.

**Swapping.** A menu on the exercise header calls `POST /exercises/substitute`
and shows 3 alternatives with equipment and rationale. Picking one replaces the
exercise in place, keeping the prescribed set/rep structure so the checklist does
not reset. Swapping back is another swap.

**Finishing.** 운동 끝내기 at the foot of the expanded view. No confirmation —
incomplete sets are simply not logged, and the action is not destructive.
**Discarding does get a confirmation**, because it is irreversible.

**The summary.** When `POST /sessions` returns, the container's *content*
cross-dissolves into the summary while the surface stays put — the workout
becomes the report rather than a new screen appearing over it. Tapping 확인
collapses the container down through the path it rose along, and the store goes
`nil`.

Start, log, finish, and report are one continuous surface from the moment 시작 is
tapped to the moment it leaves the screen.

---

## 5. Errors, testing, file layout

### What surfaces, what stays quiet

| Failure | Behavior |
| --- | --- |
| Draft save (`PUT`) | Silent. Connectivity is out of scope by decision |
| Finish (`POST /sessions`) | Surfaces inline with retry; the store keeps the draft until it succeeds |
| Substitute | Inline inside the swap sheet |
| Resume fetch | No bar, no error — nothing was lost |

### Tests

Without a simulator (`cd ReelsKit && swift test`): seeding a day into rows,
weight carry-down, and the `ActiveSessionUpdateRequest` shape.

In the app target, using `ScriptedTransport` as `LibraryStoreTests` does: start
creates the store; completing a set flushes immediately; rapid weight edits
coalesce into one `PUT`; resume with a dead program yields a discard-only state;
finish clears the store; discard sends `DELETE`.

**The motion is not unit-testable.** Springs, velocity handoff and interruption
are judged by holding them, so the container is built first as a throwaway with
dummy content and handed over for review before any real content goes inside it.

### New files

```
ReelsKit/Sources/ReelsKit/Models/
  WorkoutDraft.swift            seeding + carry-down (pure, testable)

ReelsWorkout/Features/Workout/
  WorkoutSessionStore.swift     state + debounced sync
  WorkoutContainer.swift        progress, drag, spring, interruption
  WorkoutBar.swift              collapsed content
  WorkoutSessionView.swift      expanded exercise list
  SetRow.swift                  the 30x/session interaction
  RestTimerBar.swift
  ExerciseSwapSheet.swift
  WorkoutSummaryView.swift

ReelsKit/Tests/ReelsKitTests/WorkoutDraftTests.swift
ReelsWorkoutTests/WorkoutSessionStoreTests.swift
```

`make generate` is required after adding these, or the build will not see them.

## Build order

1. `WorkoutContainer` with dummy content — throwaway prototype, reviewed by hand
2. `WorkoutDraft` seeding + tests
3. `WorkoutSessionStore` + tests
4. `SetRow`, `RestTimerBar`, `WorkoutSessionView`
5. Entry point and resume
6. `ExerciseSwapSheet`
7. `WorkoutSummaryView`
