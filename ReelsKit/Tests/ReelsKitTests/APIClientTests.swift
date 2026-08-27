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
}
