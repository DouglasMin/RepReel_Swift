import Foundation
import Testing
@testable import ReelsWorkout
import ReelsKit

private struct ScriptedTransport: HTTPTransport {
    let routes: [String: (Int, String)]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let match = routes.first { path.hasSuffix($0.key) }
        let (status, body) = match?.value ?? (404, #"{"message":"no stub"}"#)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}

@MainActor
private func makeHistoryStore(routes: [String: (Int, String)]) -> HistoryStore {
    let config = AppConfig(
        apiHost: "test.example.com", appSecret: "s", appGroupID: "group.test"
    )
    let client = APIClient(config: config, transport: ScriptedTransport(routes: routes)) {
        "lifter@example.com"
    }
    return HistoryStore(client: client)
}

@MainActor
@Suite("HistoryStore")
struct HistoryStoreTests {

    @Test("Loads past workout sessions and computes aggregated volume analytics")
    func loadsPastSessions() async {
        let store = makeHistoryStore(routes: [
            "/sessions": (200, #"""
            {
              "count": 2,
              "sessions": [
                {
                  "session_id": "s1",
                  "program_id": "prog_1",
                  "day_number": 1,
                  "logged_at": \#(Int(Date().timeIntervalSince1970)),
                  "duration_seconds": 3600,
                  "session_notes": "Great session",
                  "volume_analytics": {
                    "total_volume_kg": 4000.0,
                    "total_sets_completed": 10,
                    "total_reps_completed": 80,
                    "exercise_breakdown": [
                      {
                        "exercise_id": "bench",
                        "exercise_name": "Bench Press",
                        "volume_kg": 4000.0,
                        "completed_sets": 10,
                        "completed_reps": 80,
                        "top_set_weight_kg": 100.0,
                        "estimated_1rm_kg": 125.0
                      }
                    ]
                  },
                  "completed_exercises": []
                },
                {
                  "session_id": "s2",
                  "program_id": "prog_1",
                  "day_number": 2,
                  "logged_at": \#(Int(Date().timeIntervalSince1970) - 86400),
                  "duration_seconds": 3000,
                  "volume_analytics": {
                    "total_volume_kg": 3000.0,
                    "total_sets_completed": 8,
                    "total_reps_completed": 64,
                    "exercise_breakdown": []
                  },
                  "completed_exercises": []
                }
              ]
            }
            """#)
        ])

        await store.loadHistory()

        #expect(store.sessions.count == 2)
        #expect(store.totalVolumeKg == 7000.0)
        #expect(store.totalSets == 18)
        #expect(store.totalReps == 144)
        #expect(store.weeklySessionCount == 2)
        #expect(store.weeklyVolumeKg == 7000.0)
        #expect(store.errorMessage == nil)
    }

    @Test("Surfaces network failure into errorMessage")
    func surfacesErrors() async {
        let store = makeHistoryStore(routes: [
            "/sessions": (500, #"{"error":"internal error"}"#)
        ])

        await store.loadHistory()

        #expect(store.sessions.isEmpty)
        #expect(store.errorMessage != nil)
    }

    @Test("Filters sessions and volume by specific date")
    func calendarDateQueries() async {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let lastWeek = now.addingTimeInterval(-86400 * 10)

        let store = makeHistoryStore(routes: [
            "/sessions": (200, #"""
            {
              "count": 2,
              "sessions": [
                {
                  "session_id": "s1",
                  "program_id": "prog_today",
                  "day_number": 1,
                  "logged_at": \#(Int(now.timeIntervalSince1970)),
                  "duration_seconds": 3600,
                  "volume_analytics": {
                    "total_volume_kg": 4500.0,
                    "total_sets_completed": 10,
                    "total_reps_completed": 80,
                    "exercise_breakdown": []
                  },
                  "completed_exercises": []
                },
                {
                  "session_id": "s2",
                  "program_id": "prog_yesterday",
                  "day_number": 2,
                  "logged_at": \#(Int(yesterday.timeIntervalSince1970)),
                  "duration_seconds": 2400,
                  "volume_analytics": {
                    "total_volume_kg": 3200.0,
                    "total_sets_completed": 8,
                    "total_reps_completed": 60,
                    "exercise_breakdown": []
                  },
                  "completed_exercises": []
                }
              ]
            }
            """#)
        ])

        await store.loadHistory()

        #expect(store.hasWorkout(on: now))
        #expect(store.hasWorkout(on: yesterday))
        #expect(!store.hasWorkout(on: lastWeek))

        let todaySessions = store.sessions(on: now)
        #expect(todaySessions.count == 1)
        #expect(todaySessions.first?.programId == "prog_today")
        #expect(store.dailyVolumeKg(on: now) == 4500.0)

        let yesterdaySessions = store.sessions(on: yesterday)
        #expect(yesterdaySessions.count == 1)
        #expect(yesterdaySessions.first?.programId == "prog_yesterday")
        #expect(store.dailyVolumeKg(on: yesterday) == 3200.0)

        #expect(store.sessions(on: lastWeek).isEmpty)
        #expect(store.dailyVolumeKg(on: lastWeek) == 0.0)
    }

    @Test("Computes weekly dashboard and streak metrics")
    func weeklyDashboardAndStreak() async {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)

        let store = makeHistoryStore(routes: [
            "/sessions": (200, #"""
            {
              "count": 2,
              "sessions": [
                {
                  "session_id": "s1",
                  "program_id": "prog_today",
                  "day_number": 1,
                  "logged_at": \#(Int(now.timeIntervalSince1970)),
                  "duration_seconds": 3600,
                  "volume_analytics": {
                    "total_volume_kg": 5000.0,
                    "total_sets_completed": 10,
                    "total_reps_completed": 80,
                    "exercise_breakdown": []
                  },
                  "completed_exercises": []
                },
                {
                  "session_id": "s2",
                  "program_id": "prog_yesterday",
                  "day_number": 2,
                  "logged_at": \#(Int(yesterday.timeIntervalSince1970)),
                  "duration_seconds": 2400,
                  "volume_analytics": {
                    "total_volume_kg": 3000.0,
                    "total_sets_completed": 8,
                    "total_reps_completed": 60,
                    "exercise_breakdown": []
                  },
                  "completed_exercises": []
                }
              ]
            }
            """#)
        ])

        await store.loadHistory()

        #expect(store.currentStreakDays >= 2)
        #expect(store.currentWeekDays.count == 7)
        #expect(store.thisWeekVolumeKg >= 5000.0)
    }
}
