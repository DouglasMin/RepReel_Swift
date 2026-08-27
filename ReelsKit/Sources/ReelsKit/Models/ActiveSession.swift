import Foundation

// MARK: - Volume analytics (server-computed)

public struct ExerciseVolumeAnalytics: Codable, Identifiable, Sendable {
    public var id: String { exerciseId }

    public let exerciseId: String
    public let exerciseName: String
    public let volumeKg: Double
    public let completedSets: Int
    public let completedReps: Int
    public let topSetWeightKg: Double?
    public let estimated1rmKg: Double?

    public init(exerciseId: String, exerciseName: String, volumeKg: Double,
                completedSets: Int, completedReps: Int,
                topSetWeightKg: Double? = nil, estimated1rmKg: Double? = nil) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.volumeKg = volumeKg
        self.completedSets = completedSets
        self.completedReps = completedReps
        self.topSetWeightKg = topSetWeightKg
        self.estimated1rmKg = estimated1rmKg
    }

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case volumeKg = "volume_kg"
        case completedSets = "completed_sets"
        case completedReps = "completed_reps"
        case topSetWeightKg = "top_set_weight_kg"
        case estimated1rmKg = "estimated_1rm_kg"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.exerciseId = (try? container.decodeIfPresent(String.self, forKey: .exerciseId)) ?? UUID().uuidString
        self.exerciseName = (try? container.decodeIfPresent(String.self, forKey: .exerciseName)) ?? ""
        self.volumeKg = (try? container.decodeIfPresent(Double.self, forKey: .volumeKg)) ?? 0
        self.completedSets = (try? container.decodeIfPresent(Int.self, forKey: .completedSets)) ?? 0
        self.completedReps = (try? container.decodeIfPresent(Int.self, forKey: .completedReps)) ?? 0
        self.topSetWeightKg = try? container.decodeIfPresent(Double.self, forKey: .topSetWeightKg)
        self.estimated1rmKg = try? container.decodeIfPresent(Double.self, forKey: .estimated1rmKg)
    }
}

/// Total tonnage for a workout. The backend recomputes this on every draft save
/// and on finish, so treat it as read-only.
public struct WorkoutVolumeAnalytics: Codable, Sendable {
    public let totalVolumeKg: Double
    public let totalSetsCompleted: Int
    public let totalRepsCompleted: Int
    public let exerciseBreakdown: [ExerciseVolumeAnalytics]

    public init(totalVolumeKg: Double, totalSetsCompleted: Int,
                totalRepsCompleted: Int, exerciseBreakdown: [ExerciseVolumeAnalytics] = []) {
        self.totalVolumeKg = totalVolumeKg
        self.totalSetsCompleted = totalSetsCompleted
        self.totalRepsCompleted = totalRepsCompleted
        self.exerciseBreakdown = exerciseBreakdown
    }

    public var volumeSummaryString: String {
        let tonnage = totalVolumeKg.formatted(.number.precision(.fractionLength(0...1)))
        return "\(tonnage) kg (\(totalSetsCompleted)세트 · \(totalRepsCompleted)회)"
    }

    enum CodingKeys: String, CodingKey {
        case totalVolumeKg = "total_volume_kg"
        case totalSetsCompleted = "total_sets_completed"
        case totalRepsCompleted = "total_reps_completed"
        case exerciseBreakdown = "exercise_breakdown"
    }
}

extension WorkoutVolumeAnalytics {
    /// `exercise_breakdown` is absent from the documented `PUT /sessions/active`
    /// response (`docs/API_SPECIFICATION.md`) even though the deployed backend
    /// sends it. Defaulting to `[]` keeps a doc-conforming response decodable —
    /// otherwise every draft save would throw and live tonnage would silently die.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.totalVolumeKg = (try? container.decodeIfPresent(Double.self, forKey: .totalVolumeKg)) ?? 0
        self.totalSetsCompleted = (try? container.decodeIfPresent(Int.self, forKey: .totalSetsCompleted)) ?? 0
        self.totalRepsCompleted = (try? container.decodeIfPresent(Int.self, forKey: .totalRepsCompleted)) ?? 0
        self.exerciseBreakdown = (try? container.decodeIfPresent(
            [ExerciseVolumeAnalytics].self, forKey: .exerciseBreakdown
        )) ?? []
    }
}

// MARK: - In-progress draft

/// The server-side draft of a workout in progress. There is exactly one per
/// user, keyed on `x-user-email` — not one per program.
///
/// The wire payload also carries DynamoDB bookkeeping (`PK`, `SK`,
/// `entity_type`); those keys are deliberately not modelled.
public struct ActiveWorkoutDraft: Codable, Sendable {
    public let userId: String?
    public let programId: String?
    public let dayNumber: Int?
    public let startedAt: Int?
    public let lastUpdatedAt: Int?
    public var sessionData: WorkoutSessionLog?
    public var volumeAnalytics: WorkoutVolumeAnalytics?

    public var startedDate: Date? {
        startedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case programId = "program_id"
        case dayNumber = "day_number"
        case startedAt = "started_at"
        case lastUpdatedAt = "last_updated_at"
        case sessionData = "session_data"
        case volumeAnalytics = "volume_analytics"
    }
}

/// `GET /sessions/active`. Answers 200 with a draft, or 404 with
/// `has_active_session: false` when nothing is in progress — the client turns
/// that 404 into a normal empty result rather than an error.
public struct ActiveSessionResponse: Codable, Sendable {
    public let hasActiveSession: Bool
    public let activeSession: ActiveWorkoutDraft?
    public let message: String?

    public static let none = ActiveSessionResponse(
        hasActiveSession: false, activeSession: nil, message: nil
    )

    public init(
        hasActiveSession: Bool,
        activeSession: ActiveWorkoutDraft? = nil,
        message: String? = nil
    ) {
        self.hasActiveSession = hasActiveSession
        self.activeSession = activeSession
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case hasActiveSession = "has_active_session"
        case activeSession = "active_session"
        case message
    }
}

/// `PUT /sessions/active` body. Note `started_at` rather than the `logged_at`
/// that a finished session carries.
public struct ActiveSessionUpdateRequest: Codable, Sendable {
    public let programId: String
    public let dayNumber: Int
    public let startedAt: Int
    public var completedExercises: [ExecutedExerciseLog]

    public init(
        programId: String,
        dayNumber: Int,
        startedAt: Int,
        completedExercises: [ExecutedExerciseLog]
    ) {
        self.programId = programId
        self.dayNumber = dayNumber
        self.startedAt = startedAt
        self.completedExercises = completedExercises
    }

    enum CodingKeys: String, CodingKey {
        case programId = "program_id"
        case dayNumber = "day_number"
        case startedAt = "started_at"
        case completedExercises = "completed_exercises"
    }
}

public struct ActiveSessionUpdateResponse: Codable, Sendable {
    public let success: Bool
    public let activeSession: ActiveWorkoutDraft?

    enum CodingKeys: String, CodingKey {
        case success
        case activeSession = "active_session"
    }
}

public struct ActiveSessionDeleteResponse: Codable, Sendable {
    public let success: Bool
    public let deleted: Bool?
}
