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
