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

    @Test("Weight carry-down happens on commitWeight")
    func carriesWeightDown() async {
        let transport = CountingTransport()
        let store = makeStore(transport: transport)

        store.commitWeight(80, exercise: 0, set: 0)

        #expect(store.draft.exercises[0].sets.map(\.weightKg) == [80, 80, 80])
    }

    @Test("Setting weight without commit does not carry down")
    func setWeightDoesNotCarryDown() async {
        let transport = CountingTransport()
        let store = makeStore(transport: transport)

        store.setWeight(80, exercise: 0, set: 0)

        #expect(store.draft.exercises[0].sets.map(\.weightKg) == [80, nil, nil])
    }

    @Test("Completing a set starts a rest countdown from the prescription")
    func startsRestTimer() throws {
        let transport = CountingTransport()
        let store = makeStore(transport: transport)

        #expect(store.restEndsAt == nil)
        store.completeSet(exercise: 0, set: 0)

        let endsAt = try #require(store.restEndsAt)
        // restSeconds is 120 in the fixture.
        #expect(abs(endsAt.timeIntervalSinceNow - 120) < 2)
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

        #expect(transport.calls.count == 1)
        #expect(store.analytics == nil)
        #expect(store.draft.exercises[0].sets[0].weightKg == 80)
    }
}
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
    func resumeRebuilds() async throws {
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

        let resumed = try #require(store)
        #expect(resumed.draft.startedAt == 1000)
        #expect(resumed.draft.exercises[0].sets[0].completed == true)
        #expect(resumed.draft.exercises[0].sets[0].weightKg == 80)
        #expect(resumed.isOrphaned == false)
    }

    @Test("Resume survives a draft whose program no longer exists")
    func resumeWithDeadProgram() async throws {
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

        let resumed = try #require(store)
        #expect(resumed.isOrphaned == true)
        // Still shows what was logged, so discarding is an informed choice.
        #expect(resumed.draft.exercises[0].sets.count == 1)
    }

    @Test("Resume returns nil on transient network failure instead of orphaning")
    func resumeTransientFailureReturnsNil() async {
        let active = #"""
        {"has_active_session":true,"active_session":{"program_id":"p1",
         "day_number":1,"started_at":1000,"user_id":"lifter@example.com",
         "session_data":{"program_id":"p1","day_number":1,
         "completed_exercises":[{"exercise_id":"bench","exercise_name":"벤치프레스",
         "sets":[{"set_number":1,"weight_kg":80,"reps":10,"completed":true}]}]}}}
        """#
        let transport = RouteTransport([
            "GET /sessions/active": (200, active),
            "GET /programs/p1": (500, #"{"error":"internal error"}"#)
        ])

        let store = await WorkoutSessionStore.resume(client: makeClient(transport))

        #expect(store == nil)
    }
}
