import Foundation
@testable import ReelsKit

/// Canned HTTP responder shared by the client test suites.
struct StubTransport: HTTPTransport {
    let status: Int
    let body: Data
    let recorder: Recorder

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URLRequest] = []

        var requests: [URLRequest] { lock.withLock { _requests } }

        func record(_ request: URLRequest) {
            lock.withLock { _requests.append(request) }
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorder.record(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }
}

let testConfig = AppConfig(
    apiHost: "abc123.execute-api.ap-northeast-2.amazonaws.com",
    apiStagePath: "/dev",
    appSecret: "secret-token",
    appGroupID: "group.test"
)

func makeClient(
    status: Int = 200,
    body: String = "{}",
    email: String? = "lifter@example.com"
) -> (APIClient, StubTransport.Recorder) {
    let recorder = StubTransport.Recorder()
    let transport = StubTransport(status: status, body: Data(body.utf8), recorder: recorder)
    return (APIClient(config: testConfig, transport: transport) { email }, recorder)
}
