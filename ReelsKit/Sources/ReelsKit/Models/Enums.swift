import Foundation

public enum SplitType: String, Codable, Sendable, CaseIterable {
    case ppl = "PPL (Push/Pull/Legs)"
    case upperLower = "Upper/Lower (상체/하체)"
    case broSplit = "Bro Split (부위별 4-5분할)"
    case fullBody = "Full Body (무분할/전신)"
    case custom = "Custom Routine"
}

public enum EquipmentType: String, Codable, Sendable, CaseIterable {
    case barbell = "Barbell (바벨)"
    case dumbbell = "Dumbbell (덤벨)"
    case cable = "Cable (케이블)"
    case machine = "Machine (머신)"
    case bodyweight = "Bodyweight (맨몸)"
    case kettlebell = "Kettlebell (케틀벨)"
    case other = "Other (기타)"

    public var iconName: String {
        switch self {
        case .barbell: "figure.strengthtraining.traditional"
        case .dumbbell: "dumbbell.fill"
        case .cable: "cable.connector"
        case .machine: "gearshape.2.fill"
        case .bodyweight: "figure.walk"
        case .kettlebell: "circle.grid.cross.fill"
        case .other: "questionmark.circle"
        }
    }
}

public enum GroupCategory: String, Codable, Sendable, CaseIterable {
    case mainCompound = "Main Compound (메인 복합 다관절 운동)"
    case accessory = "Accessory (보조 복합/단일 운동)"
    case isolation = "Isolation (고립/레이즈 운동)"
    case coreFinisher = "Core / Finisher (코어 및 마무리 운동)"

    public var badgeColorHex: String {
        switch self {
        case .mainCompound: "#FF3B30" // Red
        case .accessory: "#007AFF"    // Blue
        case .isolation: "#FF9500"    // Orange
        case .coreFinisher: "#34C759" // Green
        }
    }

    public var shortLabel: String {
        switch self {
        case .mainCompound: "메인"
        case .accessory: "보조"
        case .isolation: "고립"
        case .coreFinisher: "코어"
        }
    }
}

public enum RepType: String, Codable, Sendable {
    case repsRange = "Reps Range (반복 횟수 범위)"
    case fixedReps = "Fixed Reps (고정 횟수)"
    case toFailure = "To Failure (실패 지점까지)"
    case timedSeconds = "Timed Seconds (시간/초 단위)"
}

public enum JobStatus: String, Codable, Sendable {
    case processing = "PROCESSING"
    case completed = "COMPLETED"
    case failed = "FAILED"

    public var isTerminal: Bool { self != .processing }
}
