import Foundation

// MARK: - Series merge

public struct ProgramMergeRequest: Codable, Sendable {
    public let programIds: [String]
    public let title: String?

    public init(programIds: [String], title: String? = nil) {
        self.programIds = programIds
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case programIds = "program_ids"
        case title
    }
}

public struct ProgramMergeResponse: Codable, Sendable {
    public let success: Bool
    public let mergedProgramId: String
    public let program: WorkoutProgramResponse

    enum CodingKeys: String, CodingKey {
        case success
        case mergedProgramId = "merged_program_id"
        case program
    }
}

// MARK: - Progressive overload

public struct NextSessionRecommendationItem: Codable, Identifiable, Sendable {
    public var id: String { exerciseId }

    public let exerciseId: String
    public let exerciseName: String
    public let lastWeightKg: Double?
    public let recommendedWeightKg: Double
    public let targetSets: Int
    public let targetReps: String
    public let targetRpe: Double?
    public let progressionNote: String?

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case lastWeightKg = "last_weight_kg"
        case recommendedWeightKg = "recommended_weight_kg"
        case targetSets = "target_sets"
        case targetReps = "target_reps"
        case targetRpe = "target_rpe"
        case progressionNote = "progression_note"
    }
}

public struct NextSessionRecommendationResponse: Codable, Sendable {
    public let success: Bool
    public let programId: String
    public let dayNumber: Int
    public let dayTitle: String?
    public let overloadSummary: String?
    public let exerciseRecommendations: [NextSessionRecommendationItem]

    enum CodingKeys: String, CodingKey {
        case success
        case programId = "program_id"
        case dayNumber = "day_number"
        case dayTitle = "day_title"
        case overloadSummary = "overload_summary"
        case exerciseRecommendations = "exercise_recommendations"
    }
}

// MARK: - Coach Q&A

public struct CoachQueryRequest: Codable, Sendable {
    public let question: String
    public init(question: String) { self.question = question }
}

public struct CoachQueryResponse: Codable, Sendable {
    public let success: Bool
    public let programId: String?
    public let question: String?
    public let answer: String
    public let suggestedActionItems: [String]?

    enum CodingKeys: String, CodingKey {
        case success
        case programId = "program_id"
        case question
        case answer
        case suggestedActionItems = "suggested_action_items"
    }
}

// MARK: - Exercise substitution

public struct ExerciseSubstituteRequest: Codable, Sendable {
    public let exerciseName: String
    public let targetMuscle: String
    public let preferredEquipment: [String]?

    public init(exerciseName: String, targetMuscle: String, preferredEquipment: [String]? = nil) {
        self.exerciseName = exerciseName
        self.targetMuscle = targetMuscle
        self.preferredEquipment = preferredEquipment
    }

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case targetMuscle = "target_muscle"
        case preferredEquipment = "preferred_equipment"
    }
}

public struct ExerciseSubstituteItem: Codable, Identifiable, Sendable {
    public var id: String { exerciseName }

    public let exerciseName: String
    public let equipment: String
    public let targetMuscle: String?
    public let rationale: String?
    public let recommendedVolume: String?

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case equipment
        case targetMuscle = "target_muscle"
        case rationale
        case recommendedVolume = "recommended_volume"
    }
}

public struct ExerciseSubstituteResponse: Codable, Sendable {
    public let success: Bool
    public let originalExercise: String
    public let targetMuscle: String?
    public let substitutes: [ExerciseSubstituteItem]

    enum CodingKeys: String, CodingKey {
        case success
        case originalExercise = "original_exercise"
        case targetMuscle = "target_muscle"
        case substitutes
    }
}
