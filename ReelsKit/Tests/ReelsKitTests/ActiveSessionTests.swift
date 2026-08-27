import Foundation
import Testing
@testable import ReelsKit

/// The fixture below is a verbatim capture from the deployed backend
/// (`GET /sessions/active`), not the tidied example in the docs. It differs in
/// ways that matter: `session_data` has no `logged_at`, sets omit `rpe`,
/// numbers arrive as integers, and DynamoDB keys ride along.
private let realActiveSessionPayload = #"""
{
  "has_active_session": true,
  "active_session": {
    "session_data": {
      "program_id": "prog_test_123",
      "completed_exercises": [
        {
          "exercise_id": "bench_press",
          "exercise_name": "벤치프레스",
          "sets": [
            { "set_number": 1, "weight_kg": 80, "reps": 10, "completed": true },
            { "completed": true, "set_number": 2, "weight_kg": 85, "reps": 8 }
          ]
        }
      ],
      "day_number": 1
    },
    "program_id": "prog_test_123",
    "user_id": "dongik@example.com",
    "entity_type": "ACTIVE_SESSION",
    "volume_analytics": {
      "total_sets_completed": 2,
      "exercise_breakdown": [
        {
          "exercise_name": "벤치프레스",
          "completed_sets": 2,
          "exercise_id": "bench_press",
          "completed_reps": 18,
          "estimated_1rm_kg": 107.7,
          "top_set_weight_kg": 85,
          "volume_kg": 1480
        }
      ],
      "total_volume_kg": 1480,
      "total_reps_completed": 18
    },
    "last_updated_at": 1787796796,
    "day_number": 1,
    "PK": "USER#dongik@example.com",
    "started_at": 1787796796,
    "SK": "ACTIVE_SESSION"
  }
}
"""#

@Suite("Active workout draft")
struct ActiveSessionTests {

    @Test("Decodes the live payload, including a draft with no logged_at")
    func decodesRealPayload() throws {
        let response = try JSONDecoder().decode(
            ActiveSessionResponse.self, from: Data(realActiveSessionPayload.utf8)
        )

        #expect(response.hasActiveSession)
        let draft = try #require(response.activeSession)
        #expect(draft.userId == "dongik@example.com")
        #expect(draft.dayNumber == 1)
        #expect(draft.startedDate != nil)

        let sessionData = try #require(draft.sessionData)
        #expect(sessionData.loggedAt == nil)
        #expect(sessionData.completedExercises.first?.sets.count == 2)

        let analytics = try #require(draft.volumeAnalytics)
        #expect(analytics.totalVolumeKg == 1480)
        #expect(analytics.exerciseBreakdown.first?.estimated1rmKg == 107.7)
    }

    @Test("Turns the 404 'nothing in progress' answer into an empty result")
    func mapsNotFoundToEmpty() async throws {
        let recorder = StubTransport.Recorder()
        let transport = StubTransport(
            status: 404,
            body: Data(#"{"has_active_session": false, "message": "No active workout."}"#.utf8),
            recorder: recorder
        )
        let client = APIClient(config: testConfig, transport: transport) { "lifter@example.com" }

        let response = try await client.activeSession()

        #expect(response.hasActiveSession == false)
        #expect(response.activeSession == nil)
    }

    @Test("Sends started_at, not logged_at, when saving a draft")
    func draftUsesStartedAt() async throws {
        let recorder = StubTransport.Recorder()
        let transport = StubTransport(
            status: 200, body: Data(#"{"success":true}"#.utf8), recorder: recorder
        )
        let client = APIClient(config: testConfig, transport: transport) { "lifter@example.com" }

        try await client.saveActiveSession(
            ActiveSessionUpdateRequest(
                programId: "p1",
                dayNumber: 1,
                startedAt: 1771979000,
                completedExercises: [
                    ExecutedExerciseLog(
                        exerciseId: "bench_press",
                        exerciseName: "벤치프레스",
                        sets: [LoggedSet(setNumber: 1, weightKg: 80, reps: 10, completed: true)]
                    )
                ]
            )
        )

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/dev/sessions/active")

        let httpBody = try #require(request.httpBody)
        let body = try #require(
            try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
        )
        #expect(body["started_at"] as? Int == 1771979000)
        #expect(body["logged_at"] == nil)
    }
}

@Suite("Volume helpers")
struct VolumeTests {

    @Test("An unchecked set contributes no tonnage")
    func uncheckedSetIsZero() {
        let done = LoggedSet(setNumber: 1, weightKg: 80, reps: 10, completed: true)
        let pending = LoggedSet(setNumber: 2, weightKg: 85, reps: 8, completed: false)

        #expect(done.setVolumeKg == 800)
        #expect(pending.setVolumeKg == 0)
    }

    @Test("Exercise tonnage sums only the completed sets")
    func exerciseTonnage() {
        let log = ExecutedExerciseLog(
            exerciseId: "bench_press",
            exerciseName: "벤치프레스",
            sets: [
                LoggedSet(setNumber: 1, weightKg: 80, reps: 10, completed: true),
                LoggedSet(setNumber: 2, weightKg: 85, reps: 8, completed: true),
                LoggedSet(setNumber: 3, weightKg: 85, reps: 8, completed: false)
            ]
        )
        // Matches what the backend reported for the same two sets.
        #expect(log.totalExerciseVolumeKg == 1480)
    }

    @Test("Decodes the finished-session response with server volume")
    func decodesFinishedSession() throws {
        let json = #"""
        {
          "success": true,
          "session_id": "session_8f9e0d1c2b3a",
          "session": {
            "session_id": "session_8f9e0d1c2b3a",
            "program_id": "p1",
            "day_number": 1,
            "duration_seconds": 3600,
            "completed_exercises": [],
            "volume_analytics": {
              "total_volume_kg": 3555.0,
              "total_sets_completed": 5,
              "total_reps_completed": 42,
              "exercise_breakdown": []
            }
          }
        }
        """#

        let response = try JSONDecoder().decode(
            SessionCreateResponse.self, from: Data(json.utf8)
        )

        #expect(response.sessionId == "session_8f9e0d1c2b3a")
        let analytics = try #require(response.session?.volumeAnalytics)
        #expect(analytics.totalVolumeKg == 3555)
        #expect(analytics.volumeSummaryString == "3,555 kg (5세트 · 42회)")
    }
}
