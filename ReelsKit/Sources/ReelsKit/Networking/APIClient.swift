import Foundation

/// Typed client for the 12 endpoints in `docs/API_SPECIFICATION.md`.
///
/// Every request carries `x-app-secret` plus `x-user-email`; the email is read
/// lazily through `emailProvider` so a sign-in does not require rebuilding the
/// client.
public struct APIClient: Sendable {
    private let config: AppConfig
    private let transport: any HTTPTransport
    private let emailProvider: @Sendable () -> String?

    public init(
        config: AppConfig,
        transport: any HTTPTransport = URLSession.shared,
        emailProvider: @escaping @Sendable () -> String?
    ) {
        self.config = config
        self.transport = transport
        self.emailProvider = emailProvider
    }

    // MARK: - 1-2. Ingestion & polling

    public func ingestReel(url: String) async throws -> IngestResponse {
        try await send(.post, "/reels", body: IngestRequest(url: url))
    }

    public func jobStatus(jobId: String) async throws -> JobStatusResponse {
        try await send(.get, "/jobs/\(escape(jobId))")
    }

    /// Polls `GET /jobs/{id}` until the job leaves `PROCESSING` or the deadline passes.
    public func awaitJobCompletion(
        jobId: String,
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(180)
    ) async throws -> JobStatusResponse {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            let status = try await jobStatus(jobId: jobId)
            if status.status.isTerminal { return status }
            guard ContinuousClock.now < deadline else { return status }
            try await Task.sleep(for: pollInterval)
        }
    }

    // MARK: - 3-7. Programs

    public func program(id: String) async throws -> WorkoutProgramResponse {
        try await send(.get, "/programs/\(escape(id))")
    }

    public func programs(creator: String? = nil, limit: Int? = nil) async throws -> [ProgramSummary] {
        var query: [URLQueryItem] = []
        if let creator { query.append(URLQueryItem(name: "creator", value: creator)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        let response: ProgramListResponse = try await send(.get, "/programs", query: query)
        return response.programs
    }

    public func updateProgram(id: String, program: WorkoutProgram) async throws -> WorkoutProgramResponse {
        let response: ProgramUpdateResponse = try await send(.put, "/programs/\(escape(id))", body: program)
        return response.program
    }

    public func deleteProgram(id: String) async throws {
        let _: DeleteResponse = try await send(.delete, "/programs/\(escape(id))")
    }

    public func mergePrograms(_ request: ProgramMergeRequest) async throws -> ProgramMergeResponse {
        try await send(.post, "/programs/merge", body: request)
    }

    // MARK: - 8-10. AI coaching

    public func nextSession(programId: String, dayNumber: Int) async throws -> NextSessionRecommendationResponse {
        try await send(
            .get,
            "/programs/\(escape(programId))/next-session",
            query: [URLQueryItem(name: "day_number", value: String(dayNumber))]
        )
    }

    public func coachQuery(programId: String, question: String) async throws -> CoachQueryResponse {
        try await send(
            .post,
            "/programs/\(escape(programId))/coach-query",
            body: CoachQueryRequest(question: question)
        )
    }

    public func substituteExercise(_ request: ExerciseSubstituteRequest) async throws -> ExerciseSubstituteResponse {
        try await send(.post, "/exercises/substitute", body: request)
    }

    // MARK: - 11-13. Live workout draft

    /// Fire-and-forget from the set checklist; safe to call on every tap.
    @discardableResult
    public func saveActiveSession(
        _ draft: ActiveSessionUpdateRequest
    ) async throws -> ActiveSessionUpdateResponse {
        try await send(.put, "/sessions/active", body: draft)
    }

    /// A 404 here means "no workout in progress" — the ordinary case on a clean
    /// launch — so it resolves to an empty result instead of `APIError.notFound`.
    public func activeSession() async throws -> ActiveSessionResponse {
        do {
            return try await send(.get, "/sessions/active")
        } catch APIError.notFound {
            return .none
        }
    }

    @discardableResult
    public func discardActiveSession() async throws -> Bool {
        let response: ActiveSessionDeleteResponse = try await send(.delete, "/sessions/active")
        return response.deleted ?? response.success
    }

    // MARK: - 14-15. Session logging

    public func logSession(_ session: WorkoutSessionLog) async throws -> SessionCreateResponse {
        try await send(.post, "/sessions", body: session)
    }

    public func sessions(programId: String? = nil, limit: Int? = nil) async throws -> [WorkoutSessionLog] {
        var query: [URLQueryItem] = []
        if let programId { query.append(URLQueryItem(name: "program_id", value: programId)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        let response: SessionListResponse = try await send(.get, "/sessions", query: query)
        return response.sessions
    }

    @discardableResult
    public func deleteSession(id: String) async throws -> Bool {
        struct SessionDeleteResponse: Codable {
            let success: Bool?
            let message: String?
        }
        let response: SessionDeleteResponse = try await send(.delete, "/sessions/\(id)")
        return response.success ?? true
    }

    public func updateSession(id: String, _ session: WorkoutSessionLog) async throws -> SessionCreateResponse {
        try await send(.put, "/sessions/\(id)", body: session)
    }

    // MARK: - Request plumbing

    enum Method: String {
        case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
    }

    private func send<Response: Decodable>(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        try await perform(makeRequest(method, path, query: query, body: nil))
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: Method,
        _ path: String,
        body: Body,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        let data: Data
        do {
            data = try JSONEncoder().encode(body)
        } catch {
            throw APIError.decoding(error)
        }
        return try await perform(makeRequest(method, path, query: query, body: data))
    }

    func makeRequest(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem],
        body: Data?
    ) throws -> URLRequest {
        guard let email = emailProvider(), !email.isEmpty else {
            throw APIError.missingUserEmail
        }
        var components = URLComponents(
            url: config.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.badURL(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appSecret, forHTTPHeaderField: "x-app-secret")
        request.setValue(email, forHTTPHeaderField: "x-user-email")
        request.httpBody = body
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.send(request)
        } catch {
            #if DEBUG
            print("[APIClient] Transport failed for \(request.httpMethod ?? "") \(request.url?.path ?? ""): \(error)")
            #endif
            throw APIError.transport(error)
        }

        #if DEBUG
        print("[APIClient] \(request.httpMethod ?? "") \(request.url?.path ?? "") -> HTTP \(http.statusCode)")
        #endif

        switch http.statusCode {
        case 200..<300:
            break
        case 403:
            #if DEBUG
            print("[APIClient] 403 Forbidden! Check x-user-email and x-app-secret.")
            #endif
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        default:
            let body = String(data: data, encoding: .utf8)
            #if DEBUG
            print("[APIClient] Error HTTP \(http.statusCode): \(body ?? "<nil>")")
            #endif
            throw APIError.http(status: http.statusCode, body: body)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[APIClient] Failed to decode \(Response.self): \(error)\nRaw response body was:\n\(body)")
            #endif
            throw APIError.decoding(error)
        }
    }

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }
}
