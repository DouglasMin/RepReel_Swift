import Foundation
import Testing
@testable import ReelsWorkout
import ReelsKit

private struct ScriptedTransport: HTTPTransport {
    /// Path suffix -> (status, JSON body). Matched by `hasSuffix` so query strings
    /// and the stage path do not have to be spelled out.
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
private func makeStore(
    routes: [String: (Int, String)],
    defaults: UserDefaults
) -> LibraryStore {
    let config = AppConfig(
        apiHost: "test.example.com", appSecret: "s", appGroupID: "group.test"
    )
    let client = APIClient(config: config, transport: ScriptedTransport(routes: routes)) {
        "lifter@example.com"
    }
    return LibraryStore(client: client, jobStore: PendingJobStore(defaults: defaults))
}

@MainActor
@Suite("LibraryStore")
struct LibraryStoreTests {

    private func scratchDefaults() -> (UserDefaults, String) {
        let suite = "reelsworkout.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("Loads saved programs from GET /programs")
    func loadsPrograms() async {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = makeStore(
            routes: ["/programs": (200, #"""
            {"count":1,"programs":[{"program_id":"p1","title":"체단실 루틴 2탄",
             "creator":"이정훈","split_type":"PPL (Push/Pull/Legs)","created_at":1771977014}]}
            """#)],
            defaults: defaults
        )

        await store.loadPrograms()

        #expect(store.programs.count == 1)
        #expect(store.programs.first?.title == "체단실 루틴 2탄")
        #expect(store.errorMessage == nil)
    }

    @Test("Surfaces a 403 from the allow-list check instead of an empty list")
    func surfacesForbidden() async {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = makeStore(
            routes: ["/programs": (403, #"{"message":"forbidden"}"#)],
            defaults: defaults
        )

        await store.loadPrograms()

        #expect(store.programs.isEmpty)
        #expect(store.errorMessage != nil)
    }

    @Test("Ingesting a pasted reel queues it as a pending job")
    func ingestQueuesPendingJob() async {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = makeStore(
            routes: [
                "/reels": (202, #"{"success":true,"job_id":"job_1","reel_id":"R1","status":"PROCESSING"}"#),
                "/jobs/job_1": (200, #"{"job_id":"job_1","status":"PROCESSING"}"#)
            ],
            defaults: defaults
        )

        await store.ingest(url: "https://www.instagram.com/reel/DccqEKJPPqR/")

        #expect(store.pending.map(\.jobId) == ["job_1"])
        #expect(store.errorMessage == nil)

        store.dismissPendingJob(store.pending[0])
        #expect(store.pending.isEmpty)
    }

    @Test("Deleting a program removes it from the local list")
    func deletesProgram() async {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = makeStore(
            routes: [
                "/programs": (200, #"""
                {"count":2,"programs":[
                  {"program_id":"p1","title":"루틴 1","created_at":1771977014},
                  {"program_id":"p2","title":"루틴 2","created_at":1771977020}
                ]}
                """#),
                "/programs/p1": (200, #"{"success":true,"message":"deleted"}"#)
            ],
            defaults: defaults
        )

        await store.loadPrograms()
        #expect(store.programs.count == 2)

        await store.deleteProgram(id: "p1")
        #expect(store.programs.count == 1)
        #expect(store.programs.first?.programId == "p2")
        #expect(store.errorMessage == nil)
    }

    @Test("Merging series programs posts request and refreshes program list")
    func mergesPrograms() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        var programsFetchCount = 0

        let store = makeStore(
            routes: [
                "/programs": (200, #"""
                {"count":1,"programs":[
                  {"program_id":"p_merged","title":"통합 3분할 루틴","created_at":1771977050}
                ]}
                """#),
                "/programs/merge": (200, #"""
                {
                  "success": true,
                  "merged_program_id": "p_merged",
                  "program": {
                    "program_id": "p_merged",
                    "title": "통합 3분할 루틴",
                    "program_data": { "days": [] }
                  }
                }
                """#)
            ],
            defaults: defaults
        )

        let mergedId = try await store.mergePrograms(
            programIds: ["p1", "p2", "p3"],
            title: "통합 3분할 루틴"
        )

        #expect(mergedId == "p_merged")
        #expect(store.programs.count == 1)
        #expect(store.programs.first?.title == "통합 3분할 루틴")
    }

    @Test("Updating program summary updates local cached program immediately")
    func updatesProgramSummary() async {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = makeStore(
            routes: [
                "/programs": (200, #"""
                {"count":1,"programs":[
                  {"program_id":"p1","title":"원래 제목","created_at":1771977014}
                ]}
                """#)
            ],
            defaults: defaults
        )

        await store.loadPrograms()
        #expect(store.programs.first?.title == "원래 제목")

        let updated = WorkoutProgramResponse(
            programId: "p1",
            reelId: nil,
            creator: "운동전문가",
            title: "변경된 새 제목",
            splitType: .ppl,
            cycleFrequency: "주 3회",
            overview: "새 설명",
            programData: WorkoutProgram(
                programId: "p1",
                title: "변경된 새 제목",
                splitType: .ppl,
                overview: "새 설명",
                cycleFrequency: "주 3회",
                days: []
            ),
            s3Uri: nil,
            createdAt: 1771977014
        )

        store.updateProgramSummary(from: updated)
        #expect(store.programs.first?.title == "변경된 새 제목")
        #expect(store.programs.first?.splitType == .ppl)

        store.removeProgram(id: "p1")
        #expect(store.programs.isEmpty)
    }
}
