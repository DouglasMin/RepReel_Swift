import Foundation

/// Hierarchical workout program: Program -> Day -> ExerciseGroup -> Exercise.
///
/// Every scalar field is optional because the backend duplicates most of them on
/// the enclosing `WorkoutProgramResponse` and omits them from the nested
/// `program_data` payload (see `docs/API_SPECIFICATION.md` §3.3). Decoding stays
/// tolerant either way; read display values off the response wrapper.
public struct WorkoutProgram: Codable, Sendable {
    public var programId: String?
    public var title: String?
    public var splitType: SplitType?
    public var overview: String?
    public var cycleFrequency: String?
    public var days: [WorkoutDay]
    public var progression: ProgressionRule?
    public var audit: DataQualityAudit?

    enum CodingKeys: String, CodingKey {
        case programId = "program_id"
        case title
        case splitType = "split_type"
        case overview
        case cycleFrequency = "cycle_frequency"
        case days
        case progression
        case audit
    }
}

public struct WorkoutDay: Codable, Identifiable, Sendable {
    public var id: Int { dayNumber }

    public let dayNumber: Int
    public var dayTitle: String
    public let dayFocus: String?
    public let targetMuscleGroups: [String]
    public var exerciseGroups: [ExerciseGroup]

    enum CodingKeys: String, CodingKey {
        case dayNumber = "day_number"
        case dayTitle = "day_title"
        case dayFocus = "day_focus"
        case targetMuscleGroups = "target_muscle_groups"
        case exerciseGroups = "exercise_groups"
    }
}

public struct ExerciseGroup: Codable, Identifiable, Sendable {
    /// The API sends no group id, so it is derived. The leading exercise id is
    /// folded in because a day can legitimately repeat a category/region pair,
    /// and duplicate ids break `ForEach`.
    public var id: String {
        "\(category.rawValue)|\(targetRegion ?? "-")|\(exercises.first?.exerciseId ?? "-")"
    }

    public let category: GroupCategory
    public let targetRegion: String?
    public var exercises: [StructuredExercise]

    enum CodingKeys: String, CodingKey {
        case category
        case targetRegion = "target_region"
        case exercises
    }
}

public struct StructuredExercise: Codable, Identifiable, Sendable {
    public var id: String { exerciseId }

    public let exerciseId: String
    public var canonicalNameKo: String
    public var canonicalNameEn: String
    public let equipment: EquipmentType
    public let primaryMuscle: String
    public let secondaryMuscles: [String]
    public let isMainLift: Bool
    public var volume: PrescribedVolume
    public let guide: CoachingGuide?

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case canonicalNameKo = "canonical_name_ko"
        case canonicalNameEn = "canonical_name_en"
        case equipment
        case primaryMuscle = "primary_muscle"
        case secondaryMuscles = "secondary_muscles"
        case isMainLift = "is_main_lift"
        case volume
        case guide
    }
}

public struct PrescribedVolume: Codable, Sendable {
    public var minSets: Int
    public var maxSets: Int
    public var minReps: Int
    public var maxReps: Int?
    public var repType: RepType
    public var restSeconds: Int?
    public var weightGuidance: String?
    public var rpeTarget: Double?

    public var volumeDisplayString: String {
        let setsStr = minSets == maxSets ? "\(minSets)세트" : "\(minSets)-\(maxSets)세트"
        let repsStr: String
        if let maxReps {
            repsStr = minReps == maxReps ? "\(minReps)회" : "\(minReps)-\(maxReps)회"
        } else {
            repsStr = "\(minReps)회+"
        }
        return "\(setsStr) × \(repsStr)"
    }

    public var restDisplayString: String? {
        guard let restSeconds else { return nil }
        let minutes = restSeconds / 60
        let seconds = restSeconds % 60
        if minutes > 0 && seconds > 0 { return "휴식 \(minutes)분 \(seconds)초" }
        if minutes > 0 { return "휴식 \(minutes)분" }
        return "휴식 \(seconds)초"
    }

    enum CodingKeys: String, CodingKey {
        case minSets = "min_sets"
        case maxSets = "max_sets"
        case minReps = "min_reps"
        case maxReps = "max_reps"
        case repType = "rep_type"
        case restSeconds = "rest_seconds"
        case weightGuidance = "weight_guidance"
        case rpeTarget = "rpe_target"
    }
}

public struct CoachingGuide: Codable, Sendable {
    public let formCues: [String]
    public let commonMistakesToAvoid: [String]
    public let tempoNotes: String?

    enum CodingKeys: String, CodingKey {
        case formCues = "form_cues"
        case commonMistakesToAvoid = "common_mistakes_to_avoid"
        case tempoNotes = "tempo_notes"
    }
}

public struct ProgressionRule: Codable, Sendable {
    public let overloadStrategy: String
    public let frequencySchedule: String?
    public let recoveryGuidance: String?

    enum CodingKeys: String, CodingKey {
        case overloadStrategy = "overload_strategy"
        case frequencySchedule = "frequency_schedule"
        case recoveryGuidance = "recovery_guidance"
    }
}

public struct DataQualityAudit: Codable, Sendable {
    public let confidenceScore: Double
    public let setsAmbiguous: Bool?
    public let weightMissing: Bool?
    public let restMissing: Bool?
    public let userActionItems: [String]
    public let auditNotes: String?

    /// True when the AI flagged the extraction as needing a human pass.
    public var needsReview: Bool {
        confidenceScore < 0.9 || !userActionItems.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case confidenceScore = "confidence_score"
        case setsAmbiguous = "sets_ambiguous"
        case weightMissing = "weight_missing"
        case restMissing = "rest_missing"
        case userActionItems = "user_action_items"
        case auditNotes = "audit_notes"
    }
}
