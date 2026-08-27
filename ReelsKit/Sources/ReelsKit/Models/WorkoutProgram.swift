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

    public init(
        programId: String? = nil,
        title: String? = nil,
        splitType: SplitType? = nil,
        overview: String? = nil,
        cycleFrequency: String? = nil,
        days: [WorkoutDay] = [],
        progression: ProgressionRule? = nil,
        audit: DataQualityAudit? = nil
    ) {
        self.programId = programId
        self.title = title
        self.splitType = splitType
        self.overview = overview
        self.cycleFrequency = cycleFrequency
        self.days = days
        self.progression = progression
        self.audit = audit
    }

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

    public init(dayNumber: Int, dayTitle: String, dayFocus: String?,
                targetMuscleGroups: [String], exerciseGroups: [ExerciseGroup]) {
        self.dayNumber = dayNumber
        self.dayTitle = dayTitle
        self.dayFocus = dayFocus
        self.targetMuscleGroups = targetMuscleGroups
        self.exerciseGroups = exerciseGroups
    }

    enum CodingKeys: String, CodingKey {
        case dayNumber = "day_number"
        case dayTitle = "day_title"
        case dayFocus = "day_focus"
        case targetMuscleGroups = "target_muscle_groups"
        case exerciseGroups = "exercise_groups"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dayNumber = try container.decode(Int.self, forKey: .dayNumber)
        self.dayTitle = (try? container.decodeIfPresent(String.self, forKey: .dayTitle)) ?? "Day \(dayNumber)"
        self.dayFocus = try? container.decodeIfPresent(String.self, forKey: .dayFocus)
        self.targetMuscleGroups = (try? container.decodeIfPresent([String].self, forKey: .targetMuscleGroups)) ?? []
        self.exerciseGroups = (try? container.decodeIfPresent([ExerciseGroup].self, forKey: .exerciseGroups)) ?? []
    }

    /// Regroups exercises into clean, accurate category/targetRegion groups based on
    /// each exercise's actual biomechanical role (Main Compound vs Accessory vs Isolation)
    /// and specific target muscle, preventing non-main movements from being lumped under Main.
    public var normalizedExerciseGroups: [ExerciseGroup] {
        var groups: [ExerciseGroup] = []

        for rawGroup in exerciseGroups {
            // Check if all exercises in this group naturally belong to rawGroup.category
            let distinctCategories = Set(rawGroup.exercises.map { $0.effectiveCategory })
            if distinctCategories.count <= 1 && (distinctCategories.first == rawGroup.category || distinctCategories.isEmpty) {
                groups.append(rawGroup)
            } else {
                // Regroup by (effectiveCategory, primaryMuscle / targetRegion)
                var categorized: [(category: GroupCategory, region: String?, exercises: [StructuredExercise])] = []
                for ex in rawGroup.exercises {
                    let cat = ex.effectiveCategory
                    let region = !ex.primaryMuscle.isEmpty ? ex.primaryMuscle : rawGroup.targetRegion
                    if let idx = categorized.firstIndex(where: { $0.category == cat && $0.region == region }) {
                        categorized[idx].exercises.append(ex)
                    } else {
                        categorized.append((category: cat, region: region, exercises: [ex]))
                    }
                }
                for item in categorized {
                    groups.append(ExerciseGroup(category: item.category, targetRegion: item.region, exercises: item.exercises))
                }
            }
        }

        return groups.isEmpty ? exerciseGroups : groups
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

    public init(category: GroupCategory, targetRegion: String?,
                exercises: [StructuredExercise]) {
        self.category = category
        self.targetRegion = targetRegion
        self.exercises = exercises
    }

    enum CodingKeys: String, CodingKey {
        case category
        case targetRegion = "target_region"
        case exercises
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.category = (try? container.decodeIfPresent(GroupCategory.self, forKey: .category)) ?? .accessory
        self.targetRegion = try? container.decodeIfPresent(String.self, forKey: .targetRegion)
        self.exercises = (try? container.decodeIfPresent([StructuredExercise].self, forKey: .exercises)) ?? []
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
    public var category: GroupCategory?
    public var volume: PrescribedVolume
    public let guide: CoachingGuide?

    public init(exerciseId: String, canonicalNameKo: String, canonicalNameEn: String,
                equipment: EquipmentType, primaryMuscle: String,
                secondaryMuscles: [String], isMainLift: Bool,
                category: GroupCategory? = nil,
                volume: PrescribedVolume, guide: CoachingGuide?) {
        self.exerciseId = exerciseId
        self.canonicalNameKo = canonicalNameKo
        self.canonicalNameEn = canonicalNameEn
        self.equipment = equipment
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.isMainLift = isMainLift
        self.category = category
        self.volume = volume
        self.guide = guide
    }

    /// Accurately resolves whether this exercise is Main Compound, Accessory, Isolation, or Core Finisher
    public var effectiveCategory: GroupCategory {
        if let category {
            return category
        }
        if isMainLift {
            return .mainCompound
        }
        let text = "\(canonicalNameKo) \(canonicalNameEn) \(primaryMuscle)".lowercased()
        if text.contains("레이즈") || text.contains("raise") ||
           text.contains("사레레") || text.contains("사이드") ||
           text.contains("플라이") || text.contains("fly") ||
           text.contains("익스텐션") || text.contains("extension") ||
           text.contains("컬") || text.contains("curl") ||
           text.contains("푸시다운") || text.contains("pushdown") ||
           text.contains("킥백") || text.contains("kickback") ||
           text.contains("페이스풀") || text.contains("face pull") ||
           text.contains("슈러그") || text.contains("shrug") ||
           text.contains("카프") || text.contains("calf") {
            return .isolation
        }
        if text.contains("플랭크") || text.contains("plank") ||
           text.contains("크런치") || text.contains("crunch") ||
           text.contains("레그레이즈") || text.contains("leg raise") ||
           text.contains("복근") || text.contains("코어") || text.contains("core") ||
           text.contains("행잉") || text.contains("hanging") {
            return .coreFinisher
        }
        return .accessory
    }

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case canonicalNameKo = "canonical_name_ko"
        case canonicalNameEn = "canonical_name_en"
        case equipment
        case primaryMuscle = "primary_muscle"
        case secondaryMuscles = "secondary_muscles"
        case isMainLift = "is_main_lift"
        case category
        case volume
        case guide
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.exerciseId = try container.decode(String.self, forKey: .exerciseId)
        self.canonicalNameKo = (try? container.decodeIfPresent(String.self, forKey: .canonicalNameKo)) ?? ""
        self.canonicalNameEn = (try? container.decodeIfPresent(String.self, forKey: .canonicalNameEn)) ?? ""
        self.equipment = (try? container.decodeIfPresent(EquipmentType.self, forKey: .equipment)) ?? .other
        self.primaryMuscle = (try? container.decodeIfPresent(String.self, forKey: .primaryMuscle)) ?? ""
        self.secondaryMuscles = (try? container.decodeIfPresent([String].self, forKey: .secondaryMuscles)) ?? []
        self.isMainLift = (try? container.decodeIfPresent(Bool.self, forKey: .isMainLift)) ?? false
        self.category = try? container.decodeIfPresent(GroupCategory.self, forKey: .category)
        self.volume = try container.decode(PrescribedVolume.self, forKey: .volume)
        self.guide = try? container.decodeIfPresent(CoachingGuide.self, forKey: .guide)
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

    public init(minSets: Int, maxSets: Int, minReps: Int, maxReps: Int?,
                repType: RepType, restSeconds: Int?, weightGuidance: String?,
                rpeTarget: Double?) {
        self.minSets = minSets
        self.maxSets = maxSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.repType = repType
        self.restSeconds = restSeconds
        self.weightGuidance = weightGuidance
        self.rpeTarget = rpeTarget
    }

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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.minSets = (try? container.decodeIfPresent(Int.self, forKey: .minSets)) ?? 3
        self.maxSets = (try? container.decodeIfPresent(Int.self, forKey: .maxSets)) ?? minSets
        self.minReps = (try? container.decodeIfPresent(Int.self, forKey: .minReps)) ?? 10
        self.maxReps = try? container.decodeIfPresent(Int.self, forKey: .maxReps)
        self.repType = (try? container.decodeIfPresent(RepType.self, forKey: .repType)) ?? .repsRange
        self.restSeconds = try? container.decodeIfPresent(Int.self, forKey: .restSeconds)
        self.weightGuidance = try? container.decodeIfPresent(String.self, forKey: .weightGuidance)
        self.rpeTarget = try? container.decodeIfPresent(Double.self, forKey: .rpeTarget)
    }
}

public struct CoachingGuide: Codable, Sendable {
    public let formCues: [String]
    public let commonMistakesToAvoid: [String]
    public let tempoNotes: String?

    public init(formCues: [String], commonMistakesToAvoid: [String], tempoNotes: String?) {
        self.formCues = formCues
        self.commonMistakesToAvoid = commonMistakesToAvoid
        self.tempoNotes = tempoNotes
    }

    enum CodingKeys: String, CodingKey {
        case formCues = "form_cues"
        case commonMistakesToAvoid = "common_mistakes_to_avoid"
        case tempoNotes = "tempo_notes"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formCues = (try? container.decodeIfPresent([String].self, forKey: .formCues)) ?? []
        self.commonMistakesToAvoid = (try? container.decodeIfPresent([String].self, forKey: .commonMistakesToAvoid)) ?? []
        self.tempoNotes = try? container.decodeIfPresent(String.self, forKey: .tempoNotes)
    }
}

public struct ProgressionRule: Codable, Sendable {
    public let overloadStrategy: String
    public let frequencySchedule: String?
    public let recoveryGuidance: String?

    public init(overloadStrategy: String, frequencySchedule: String?, recoveryGuidance: String?) {
        self.overloadStrategy = overloadStrategy
        self.frequencySchedule = frequencySchedule
        self.recoveryGuidance = recoveryGuidance
    }

    enum CodingKeys: String, CodingKey {
        case overloadStrategy = "overload_strategy"
        case frequencySchedule = "frequency_schedule"
        case recoveryGuidance = "recovery_guidance"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.overloadStrategy = (try? container.decodeIfPresent(String.self, forKey: .overloadStrategy)) ?? ""
        self.frequencySchedule = try? container.decodeIfPresent(String.self, forKey: .frequencySchedule)
        self.recoveryGuidance = try? container.decodeIfPresent(String.self, forKey: .recoveryGuidance)
    }
}

public struct DataQualityAudit: Codable, Sendable {
    public let confidenceScore: Double
    public let setsAmbiguous: Bool?
    public let weightMissing: Bool?
    public let restMissing: Bool?
    public let userActionItems: [String]
    public let auditNotes: String?

    public init(confidenceScore: Double, setsAmbiguous: Bool?, weightMissing: Bool?,
                restMissing: Bool?, userActionItems: [String], auditNotes: String?) {
        self.confidenceScore = confidenceScore
        self.setsAmbiguous = setsAmbiguous
        self.weightMissing = weightMissing
        self.restMissing = restMissing
        self.userActionItems = userActionItems
        self.auditNotes = auditNotes
    }

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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.confidenceScore = (try? container.decodeIfPresent(Double.self, forKey: .confidenceScore)) ?? 1.0
        self.setsAmbiguous = try? container.decodeIfPresent(Bool.self, forKey: .setsAmbiguous)
        self.weightMissing = try? container.decodeIfPresent(Bool.self, forKey: .weightMissing)
        self.restMissing = try? container.decodeIfPresent(Bool.self, forKey: .restMissing)
        self.userActionItems = (try? container.decodeIfPresent([String].self, forKey: .userActionItems)) ?? []
        self.auditNotes = try? container.decodeIfPresent(String.self, forKey: .auditNotes)
    }
}
