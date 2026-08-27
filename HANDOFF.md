# Handoff — Live Workout Session feature

## What this project is

An iOS app (SwiftUI, Swift 6.2, iOS 18) that turns Instagram Reels workout videos
into structured training programs. A Reel is shared into the app, an AWS backend
runs AI extraction, and the app renders the program and logs workouts against it.

**The backend is not in this repo and needs no work.** It is deployed and verified.
`docs/API_SPECIFICATION.md` is the contract (15 endpoints).

Repo: `/Users/douggy/per-projects/instagram-reels-workout-swift`
Branch: `feat/live-workout-session` (11 commits ahead of `main`)

## Architecture in one picture

```
ReelsWorkout (app)  ─┐
                     ├─→ ReelsKit (local SPM package)
ReelsShareExtension ─┘    models · APIClient · config · App Group stores
```

`ReelsKit` **must not import UIKit or SwiftUI** — it declares a macOS platform so
`swift test` runs in ~1s without booting a simulator. A UI import breaks that.

The feature just built: a live workout session. Start a workout from a program,
check off sets, get a server-computed volume report. State autosaves to a
server-side draft (`PUT /sessions/active`) so a half-finished workout survives the
app being killed.

Key files, all under `ReelsWorkout/Features/Workout/`:

| File | Role |
| --- | --- |
| `WorkoutContainer.swift` | Collapsed bar ↔ full screen, one continuous `progress` value, custom spring |
| `WorkoutSessionStore.swift` | `@MainActor @Observable` state + debounced sync; owned by `AppEnvironment` |
| `WorkoutSessionView.swift` | Expanded list of exercises |
| `SetRow.swift` | One set: weight/reps fields, ±2.5 steppers, RPE, completion circle |
| `WorkoutBar.swift` | Collapsed bar content |
| `RestTimerBar.swift` | Countdown between sets |
| `ExerciseSwapSheet.swift` | AI substitution when a machine is taken |
| `WorkoutSummaryView.swift` | Post-workout volume report |
| `ReelsKit/.../Models/WorkoutDraft.swift` | Pure seeding + carry-down logic (unit-tested) |

## Current state

**Committed:** all 11 tasks of the feature. Builds clean. 46 tests pass
(31 ReelsKit + 15 app).

**Uncommitted:** a partially-applied fix wave touching 4 files. Tests pass (34 in
ReelsKit — 3 new). It completed two findings and stopped halfway through a third:

- ✅ **C4 fixed** — `WorkoutVolumeAnalytics.init(from:)` now defaults
  `exerciseBreakdown` to `[]`.
- ✅ **I1 fixed** — `DraftExercise` now carries `primaryMuscle`.
- ⚠️ **C1 half fixed** — see below. **This is the dangerous state**: the fix looks
  applied but the buggy call path is untouched.

A full code review returned **BLOCK**: 4 Critical, 8 Important, 20 Minor, 4
test-quality findings. The complete list is at
`.superpowers/sdd/2026-08-27-live-workout-session/final-review-findings.md`.

---

## The three problems that must be fixed

### 1. Typing a weight corrupts every set below it (data corruption)

`ReelsWorkout/Features/Workout/SetRow.swift:47` →
`ReelsKit/Sources/ReelsKit/Models/WorkoutDraft.swift`

`SetRow` fires `onWeight` on **every keystroke**, and the carry-down only fills sets
that are still empty. Typing `80` into set 1 of a 4-set exercise:

```
keystroke '8'  → setWeight(8)   → sets 2-4 are empty     → filled with 8 kg
keystroke '0'  → setWeight(80)  → sets 2-4 now non-empty → NOT updated
result: [80, 8, 8, 8]
```

Those 8 kg values reach `PUT /sessions/active`, the server's `volume_analytics`,
the finish summary, and the `GET /next-session` overload recommendation that sets
future working weights.

**Second path, equally bad:** `SetRow.onAppear` assigns `weightText` from the model,
which fires the same `onChange`. Because `List` recycles offscreen rows, merely
*scrolling* a resumed workout invents weights and pushes them to the server.

**Half-done already:** `WorkoutDraft` has been split into
`setWeight(_:exercise:set:)` (writes one set only — the per-keystroke path) and
`commitWeight(_:exercise:set:)` (does the carry-down). **Nothing calls
`commitWeight` yet.**

**Remaining work, in `SetRow.swift`:**
- Keep `onChange(of: weightText)` calling `onWeight` (local write only).
- Add a commit path — `.onSubmit`, or focus loss via the existing
  `@FocusState.Binding var focused: WorkoutFieldID?` — that calls a new
  `onCommitWeight` closure, routed to `store.commitWeight(...)`.
- Guard the callback so programmatic assignment cannot re-enter: only fire when
  `focused` equals this row's field, so `onAppear` and carry-down writes are inert.
- `WorkoutSessionStore` needs a matching `commitWeight` method that calls
  `draft.commitWeight` then `scheduleSave()`.
- **Fix the test that blesses the bug.** `preservesExplicitWeights` in
  `ReelsKit/Tests/ReelsKitTests/WorkoutDraftTests.swift` asserts only `sets[0]` and
  `sets[2]` and never looks at `sets[1]`/`sets[3]` — exactly where the damage lands.

### 2. A network hiccup tells the user their routine was deleted

`ReelsWorkout/Features/Workout/WorkoutSessionStore.swift:117-118` and `:151`

```swift
let program = try? await client.program(id: programId)
let day = program?.days.first { $0.dayNumber == dayNumber }
...
store.isOrphaned = (day == nil)
```

`try?` collapses transport timeouts, HTTP 500, `.forbidden` and `.decoding` into
"this routine was deleted." An orphaned store disables 운동 끝내기 and leaves 삭제
as the only enabled action — so a user resuming a 45-minute workout on flaky wifi
is steered into destroying intact work.

**Fix:** orphan only on a definite 404.

```swift
let day: WorkoutDay?
do {
    day = try await client.program(id: programId)
        .days.first { $0.dayNumber == dayNumber }
} catch APIError.notFound {
    day = nil          // genuinely deleted → orphan
} catch {
    return nil         // transient → show no bar, retry next foreground
}
```

Returning `nil` is safe: the server draft is untouched and the next
`scenePhase == .active` retries.

### 3. Nothing expands the container — the feature is unreachable

`ReelsWorkout/Features/Workout/WorkoutContainer.swift` and
`ReelsWorkout/Features/Library/LibraryView.swift:33`

`progress` starts at `0` (collapsed) and the **only** gesture in the entire feature
is a `DragGesture`. There is no `onTapGesture` anywhere under `Features/Workout/`.
`isPresented` is passed `.constant(true)`, so the binding is inert and the parent
has no way to request expansion.

Two spec requirements are unmet:
- Tapping 시작 should open the container **already expanded**. It doesn't — a 76pt
  bar appears at the bottom and nothing else happens.
- Tapping the collapsed bar should expand it. Taps are inert, while
  `WorkoutBar.swift:37` draws a `chevron.up` promising an interaction that does not
  exist.

VoiceOver users have no path to the screen at all.

**Fix:**
- Add `.onTapGesture` that animates `progress` to `1` (or back to `0`), routed
  through the same `SpringRun` mechanism the drag uses so the motion matches.
- Replace the inert `isPresented` with something meaningful — e.g. a
  `@Binding var progress: Double`, or an `initiallyExpanded: Bool` — so
  `AppEnvironment.startWorkout` can open it expanded.
- Give the collapsed bar button semantics and an accessibility label.

---

## Lower-priority findings

Eight Important and ~20 Minor findings are documented with file:line, failure
scenario, and suggested fix in
`.superpowers/sdd/2026-08-27-live-workout-session/final-review-findings.md`.

The ones most worth doing next:

- **I4** — the rest timer breaks after the first set. `RestTimerBar` keeps the same
  view identity across rest periods, so its `@State total` stays pinned to the first
  exercise's rest duration and `didFire` never resets, meaning the end-of-rest
  haptic fires **once per workout**. Fix with `.id(endsAt)` at the call site.
- **I3** — `finishState = .saving` is never rendered, so a double-tap on 운동 끝내기
  posts two sessions.
- **I5** — duplicate `exerciseId` within a day (LLM-extracted data) breaks `ForEach`
  and collapses the resume overlay.
- **T3** — no test anywhere asserts a request **body**; the stub transports record
  only `"METHOD /path"`. One body assertion would have caught I1 by itself.

## Motion work (deliberate, not yet verified by a human)

`WorkoutContainer` implements Apple's interruptible-motion principles by hand:
one continuous `progress` value, velocity projection via `predictedEndTranslation`,
and a per-frame spring driven through `TimelineView(.animation)` +
`Spring.value(fromValue:toValue:initialVelocity:time:)` (rather than
`withAnimation`, which cannot inject initial velocity).

Three spec requirements are **absent, not merely untuned**:
- `Spring.velocity(...)` is never called, so grabbing a moving bar loses its momentum.
- `DragGesture(minimumDistance: 1)` means touch-*down* does not interrupt the
  animation; needs `0`.
- The unit `spring.settlingDuration` property is used as the cutoff, but the real
  run has different distance and nonzero velocity — use the
  `settlingDuration(fromValue:toValue:initialVelocity:epsilon:)` overload.

**Nobody has held this yet.** The feel is unverified.

## How to build and test

```bash
make generate    # REQUIRED after adding any new file — targets pick up sources by directory
make unit        # ReelsKit only, ~1s, no simulator
make build       # app + extension for the simulator
make test        # full xcodebuild test run
```

Single test:
```bash
cd ReelsKit && swift test --filter "WorkoutDraft"
xcodebuild test -project ReelsWorkout.xcodeproj -scheme ReelsWorkout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ReelsWorkoutTests/WorkoutSessionStoreTests CODE_SIGNING_ALLOWED=NO
```

Run it (the Run scheme carries `-demo`, which uses fixtures instead of the network):
```bash
xcrun simctl launch "iPhone 17 Pro" com.dongik.repreel          # real backend
xcrun simctl launch "iPhone 17 Pro" com.dongik.repreel -demo    # canned fixtures
```

## Gotchas that will bite

- **`ReelsWorkout.xcodeproj` is generated by XcodeGen from `project.yml` and is
  gitignored.** Never hand-edit the `.pbxproj`. Run `make generate` after adding
  files, or the build silently will not see them (symptom: `Cannot find X in scope`
  for a file you just created).
- **`ReelsKit` must stay free of UIKit/SwiftUI.**
- **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`), not XCTest.
  Never nest `#require` inside `#require` — it causes "recursive expansion of macro".
- **Public types need explicit public inits.** Synthesized memberwise inits are
  internal, so the app target cannot construct ReelsKit models without them. This
  already bit once and is why several models carry hand-written `public init`s.
- **`//` starts a comment in xcconfig**, which is why config stores `API_HOST`
  (host only) and the scheme is re-added in `AppConfig.baseURL`.
- **`Config/Secrets.xcconfig` is gitignored** and holds the API host, app secret,
  bundle ID, and App Group. A fresh clone needs `make bootstrap` and the real
  values filled in.
- **`GET /sessions/active` returns 404 with `has_active_session: false` when there
  is simply no draft.** That is the ordinary case, not an error;
  `APIClient.activeSession()` already maps it to an empty result.
- **Connectivity is deliberately out of scope.** Draft-save failures are silent by
  decision. Do not add retry queues or offline caches. A failing *finish*
  (`POST /sessions`) is different and must be loud.
- **`volume_analytics` is computed server-side.** Never recompute tonnage on the
  client for display.

## Suggested order of work

1. Finish C1 (the `SetRow` commit path) — it corrupts user data on every workout.
2. C3 (tap to expand) — without it the feature cannot be reached or tested by hand.
3. C2 (narrow the `try?` to 404).
4. Commit, then have a human actually run a workout end to end. Two of the three
   bugs found so far came from running the app, not from tests.
5. Work down the Important findings.
