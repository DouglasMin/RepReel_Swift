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
        sessionNotes: String? = nil
    ) {
        self.sessionId = sessionId
        self.programId = programId
        self.dayNumber = dayNumber
        self.loggedAt = loggedAt
        self.durationSeconds = durationSeconds
        self.completedExercises = completedExercises
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
}

public struct SessionCreateResponse: Codable, Sendable {
    public let success: Bool
    public let sessionId: String
    /// The finished session echoed back, carrying server-computed volume.
    public let session: WorkoutSessionLog?

    enum CodingKeys: String, CodingKey {
        case success
        case sessionId = "session_id"
        case session
    }
}

public struct SessionListResponse: Codable, Sendable {
    public let count: Int?
    public let sessions: [WorkoutSessionLog]
}
