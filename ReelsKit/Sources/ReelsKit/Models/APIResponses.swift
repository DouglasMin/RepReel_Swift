import Foundation

// MARK: - Ingestion

public struct IngestRequest: Codable, Sendable {
    public let url: String
    public init(url: String) { self.url = url }
}

public struct IngestResponse: Codable, Sendable {
    public let success: Bool
    public let jobId: String
    public let reelId: String?
    public let status: JobStatus
    public let message: String?
    public let statusUrl: String?

    enum CodingKeys: String, CodingKey {
        case success
        case jobId = "job_id"
        case reelId = "reel_id"
        case status
        case message
        case statusUrl = "status_url"
    }
}

public struct JobStatusResponse: Codable, Sendable, Identifiable {
    public var id: String { jobId }

    public let jobId: String
    public let reelId: String?
    public let status: JobStatus
    public let programId: String?
    public let confidenceScore: Double?
    public let error: String?
    public let createdAt: Int?
    public let updatedAt: Int?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case reelId = "reel_id"
        case status
        case programId = "program_id"
        case confidenceScore = "confidence_score"
        case error
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Programs

public struct WorkoutProgramResponse: Codable, Identifiable, Sendable {
    public var id: String { programId }

    public let programId: String
    public let reelId: String?
    public let creator: String?
    public let title: String
    public let splitType: SplitType?
    public let cycleFrequency: String?
    public let overview: String?
    public let programData: WorkoutProgram
    public let s3Uri: String?
    public let createdAt: Int?

    public var days: [WorkoutDay] { programData.days }
    public var audit: DataQualityAudit? { programData.audit }
    public var progression: ProgressionRule? { programData.progression }

    enum CodingKeys: String, CodingKey {
        case programId = "program_id"
        case reelId = "reel_id"
        case creator
        case title
        case splitType = "split_type"
        case cycleFrequency = "cycle_frequency"
        case overview
        case programData = "program_data"
        case s3Uri = "s3_uri"
        case createdAt = "created_at"
    }
}

/// Row shape returned by `GET /programs` — no `program_data` payload.
public struct ProgramSummary: Codable, Identifiable, Sendable {
    public var id: String { programId }

    public let programId: String
    public let title: String
    public let creator: String?
    public let splitType: SplitType?
    public let createdAt: Int?

    public var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    enum CodingKeys: String, CodingKey {
        case programId = "program_id"
        case title
        case creator
        case splitType = "split_type"
        case createdAt = "created_at"
    }
}

public struct ProgramListResponse: Codable, Sendable {
    public let count: Int?
    public let programs: [ProgramSummary]
}

public struct ProgramUpdateResponse: Codable, Sendable {
    public let success: Bool
    public let program: WorkoutProgramResponse
}

public struct DeleteResponse: Codable, Sendable {
    public let success: Bool
    public let message: String?
}
