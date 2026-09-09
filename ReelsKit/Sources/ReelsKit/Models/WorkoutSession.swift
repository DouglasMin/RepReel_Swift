import Foundation

public struct LoggedSet: Codable, Identifiable, Sendable {
    public var id: Int { setNumber }

    public let setNumber: Int
    public var weightKg: Double
    public var reps: Int
    public var rpe: Double?
    public var completed: Bool

    public init(setNumber: Int, weightKg: Double, reps: Int, rpe: Double? = nil, completed: Bool = false) {
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.completed = completed
    }

    enum CodingKeys: String, CodingKey {
        case setNumber = "set_number"
        case weightKg = "weight_kg"
        case reps
        case rpe
        case completed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.setNumber = (try? container.decodeIfPresent(Int.self, forKey: .setNumber)) ?? 1
        self.weightKg = (try? container.decodeIfPresent(Double.self, forKey: .weightKg)) ?? 0
        self.reps = (try? container.decodeIfPresent(Int.self, forKey: .reps)) ?? 0
        self.rpe = try? container.decodeIfPresent(Double.self, forKey: .rpe)
        self.completed = (try? container.decodeIfPresent(Bool.self, forKey: .completed)) ?? true
    }

    /// Optimistic client-side tonnage, for the counter that ticks up between
    /// draft saves. The authoritative number is `volume_analytics` from the
    /// server — never reconcile the two on screen.
    public var setVolumeKg: Double {
        completed ? weightKg * Double(reps) : 0
    }
}

public struct ExecutedExerciseLog: Codable, Identifiable, Sendable {
    public var id: String { exerciseId }

    public let exerciseId: String
    public let exerciseName: String
    public var sets: [LoggedSet]

    public init(exerciseId: String, exerciseName: String, sets: [LoggedSet]) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.sets = sets
    }

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case sets
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.exerciseId = (try? container.decodeIfPresent(String.self, forKey: .exerciseId)) ?? UUID().uuidString
        self.exerciseName = (try? container.decodeIfPresent(String.self, forKey: .exerciseName)) ?? ""
        self.sets = (try? container.decodeIfPresent([LoggedSet].self, forKey: .sets)) ?? []
    }

    public var totalExerciseVolumeKg: Double {
        sets.reduce(0) { $0 + $1.setVolumeKg }
    }
}

public struct WorkoutSessionLog: Codable, Identifiable, Sendable {
    public var id: String { sessionId ?? "\(programId)-\(dayNumber)-\(loggedAt ?? 0)" }

    public let sessionId: String?
    public let programId: String
    public let dayNumber: Int
    /// Absent on an in-progress draft — the server only stamps it on finish.
    public let loggedAt: Int?
    public let durationSeconds: Int?
    public var completedExercises: [ExecutedExerciseLog]
    /// Computed server-side; nil on a locally built log that has not been sent.
    public var volumeAnalytics: WorkoutVolumeAnalytics?
    public var sessionNotes: String?

    public init(
        sessionId: String? = nil,
        programId: String,
        dayNumber: Int,
        loggedAt: Int? = Int(Date().timeIntervalSince1970),
        durationSeconds: Int? = nil,
        completedExercises: [ExecutedExerciseLog],
        volumeAnalytics: WorkoutVolumeAnalytics? = nil,
        sessionNotes: String? = nil
    ) {
        self.sessionId = sessionId
        self.programId = programId
        self.dayNumber = dayNumber
        self.loggedAt = loggedAt
        self.durationSeconds = durationSeconds
        self.completedExercises = completedExercises
        self.volumeAnalytics = volumeAnalytics
        self.sessionNotes = sessionNotes
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case programId = "program_id"
        case dayNumber = "day_number"
        case loggedAt = "logged_at"
        case durationSeconds = "duration_seconds"
        case completedExercises = "completed_exercises"
        case volumeAnalytics = "volume_analytics"
        case sessionNotes = "session_notes"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionId = try? container.decodeIfPresent(String.self, forKey: .sessionId)
        self.programId = (try? container.decodeIfPresent(String.self, forKey: .programId)) ?? ""
        self.dayNumber = (try? container.decodeIfPresent(Int.self, forKey: .dayNumber)) ?? 1
        self.loggedAt = try? container.decodeIfPresent(Int.self, forKey: .loggedAt)
        self.durationSeconds = try? container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        self.completedExercises = (try? container.decodeIfPresent([ExecutedExerciseLog].self, forKey: .completedExercises)) ?? []
        self.volumeAnalytics = try? container.decodeIfPresent(WorkoutVolumeAnalytics.self, forKey: .volumeAnalytics)
        self.sessionNotes = try? container.decodeIfPresent(String.self, forKey: .sessionNotes)
    }
}

public struct SessionCreateResponse: Codable, Sendable {
    public let success: Bool?
    public let sessionId: String?
    /// The finished session echoed back, carrying server-computed volume.
    public let session: WorkoutSessionLog?

    enum CodingKeys: String, CodingKey {
        case success
        case sessionId = "session_id"
        case session
    }

    public init(success: Bool? = true, sessionId: String? = nil, session: WorkoutSessionLog? = nil) {
        self.success = success
        self.sessionId = sessionId
        self.session = session
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try? container.decodeIfPresent(Bool.self, forKey: .success)
        let directSessionId = try? container.decodeIfPresent(String.self, forKey: .sessionId)
        if let nestedSession = try? container.decodeIfPresent(WorkoutSessionLog.self, forKey: .session) {
            self.sessionId = directSessionId ?? nestedSession.sessionId
            self.session = nestedSession
        } else if let directSession = try? WorkoutSessionLog(from: decoder) {
            self.sessionId = directSessionId ?? directSession.sessionId
            self.session = directSession
        } else {
            self.sessionId = directSessionId
            self.session = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(success, forKey: .success)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(session, forKey: .session)
    }
}

public struct SessionListResponse: Codable, Sendable {
    public let count: Int?
    public let sessions: [WorkoutSessionLog]
}
