import Foundation
import Testing
@testable import ReelsKit

@Suite("APIClient")
struct APIClientTests {

    @Test("Sends the auth headers the backend requires on every call")
    func sendsAuthHeaders() async throws {
        let (client, recorder) = makeClient(
            body: #"{"success":true,"job_id":"job_1","status":"PROCESSING"}"#
        )

        _ = try await client.ingestReel(url: "https://www.instagram.com/reel/DccqEKJPPqR/")

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-app-secret") == "secret-token")
        #expect(request.value(forHTTPHeaderField: "x-user-email") == "lifter@example.com")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.absoluteString
            == "https://abc123.execute-api.ap-northeast-2.amazonaws.com/dev/reels")
    }

    @Test("Keeps the stage path when building nested paths and query items")
    func buildsNestedURL() async throws {
        let (client, recorder) = makeClient(
            body: #"{"success":true,"program_id":"p1","day_number":1,"exercise_recommendations":[]}"#
        )

        _ = try await client.nextSession(programId: "che-dan-sil", dayNumber: 1)

        let url = try #require(recorder.requests.first?.url?.absoluteString)
        #expect(url == "https://abc123.execute-api.ap-northeast-2.amazonaws.com"
            + "/dev/programs/che-dan-sil/next-session?day_number=1")
    }

    @Test("Percent-encodes a Korean creator filter — raw UTF-8 gets a 400")
    func encodesKoreanQuery() async throws {
        let (client, recorder) = makeClient(body: #"{"count":0,"programs":[]}"#)

        _ = try await client.programs(creator: "이정훈")

        let url = try #require(recorder.requests.first?.url?.absoluteString)
        #expect(url.hasSuffix("/programs?creator=%EC%9D%B4%EC%A0%95%ED%9B%88"))
    }

    @Test("Maps 403 to .forbidden rather than a generic HTTP error")
    func mapsForbidden() async throws {
        let (client, _) = makeClient(status: 403, body: #"{"message":"not allowed"}"#)

        await #expect(throws: APIError.self) {
            _ = try await client.programs()
        }
    }

    @Test("Refuses to call the API before a user email is known")
    func requiresUserEmail() async throws {
        let (client, recorder) = makeClient(email: nil)

        await #expect(throws: APIError.self) {
            _ = try await client.programs()
        }
        #expect(recorder.requests.isEmpty)
    }

    @Test("Ingests YouTube Shorts URL via POST /reels")
    func ingestsYouTubeShorts() async throws {
        let (client, recorder) = makeClient(
            body: #"{"success":true,"job_id":"job_bcb4c9367546","reel_id":"3jZp9-k9v9M","status":"PROCESSING","status_url":"/jobs/job_bcb4c9367546"}"#
        )

        let response = try await client.ingestReel(url: "https://www.youtube.com/shorts/3jZp9-k9v9M")

        #expect(response.jobId == "job_bcb4c9367546")
        #expect(response.reelId == "3jZp9-k9v9M")
        #expect(response.status == .processing)

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/dev/reels")
    }

    @Test("Deletes workout session via DELETE /sessions/{session_id}")
    func deletesSession() async throws {
        let (client, recorder) = makeClient(
            body: #"{"success":true,"message":"Session deleted successfully"}"#
        )

        let success = try await client.deleteSession(id: "session_123")
        #expect(success)

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/dev/sessions/session_123")
    }

    @Test("Updates workout session via PUT /sessions/{session_id}")
    func updatesSession() async throws {
        let (client, recorder) = makeClient(
            body: #"""
            {
              "session_id": "session_123",
              "program_id": "p1",
              "day_number": 1,
              "duration_seconds": 3600,
              "completed_exercises": [],
              "volume_analytics": {
                "total_volume_kg": 2500.0,
                "total_sets_completed": 4,
                "total_reps_completed": 36
              }
            }
            """#
        )

        let session = WorkoutSessionLog(
            sessionId: "session_123",
            programId: "p1",
            dayNumber: 1,
            completedExercises: []
        )
        let response = try await client.updateSession(id: "session_123", session)
        #expect(response.sessionId == "session_123")
        #expect(response.session?.volumeAnalytics?.totalVolumeKg == 2500.0)

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/dev/sessions/session_123")
    }
}
