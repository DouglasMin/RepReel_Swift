import Foundation

public enum SplitType: String, Codable, Sendable, CaseIterable {
    case ppl = "PPL (Push/Pull/Legs)"
    case upperLower = "Upper/Lower (상체/하체)"
    case broSplit = "Bro Split (부위별 4-5분할)"
    case fullBody = "Full Body (무분할/전신)"
    case custom = "Custom Routine"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let match = SplitType(rawValue: raw) {
            self = match
        } else if raw.localizedCaseInsensitiveContains("ppl") || raw.contains("3분할") || raw.contains("푸쉬") {
            self = .ppl
        } else if raw.localizedCaseInsensitiveContains("upper") || raw.contains("상체") || raw.contains("2분할") {
            self = .upperLower
        } else if raw.localizedCaseInsensitiveContains("bro") || raw.contains("4분할") || raw.contains("5분할") {
            self = .broSplit
        } else if raw.localizedCaseInsensitiveContains("body") || raw.contains("무분할") || raw.contains("전신") {
            self = .fullBody
        } else {
            self = .custom
        }
    }
}

public enum EquipmentType: String, Codable, Sendable, CaseIterable {
    case barbell = "Barbell (바벨)"
    case dumbbell = "Dumbbell (덤벨)"
    case cable = "Cable (케이블)"
    case machine = "Machine (머신)"
    case bodyweight = "Bodyweight (맨몸)"
    case kettlebell = "Kettlebell (케틀벨)"
    case other = "Other (기타)"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let match = EquipmentType(rawValue: raw) {
            self = match
        } else if raw.localizedCaseInsensitiveContains("barbell") || raw.contains("바벨") {
            self = .barbell
        } else if raw.localizedCaseInsensitiveContains("dumbbell") || raw.contains("덤벨") {
            self = .dumbbell
        } else if raw.localizedCaseInsensitiveContains("cable") || raw.contains("케이블") {
            self = .cable
        } else if raw.localizedCaseInsensitiveContains("machine") || raw.contains("머신") {
            self = .machine
        } else if raw.localizedCaseInsensitiveContains("bodyweight") || raw.contains("맨몸") {
            self = .bodyweight
        } else if raw.localizedCaseInsensitiveContains("kettlebell") || raw.contains("케틀벨") {
            self = .kettlebell
        } else {
            self = .other
        }
    }

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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let lower = raw.lowercased()
        if let match = GroupCategory(rawValue: raw) {
            self = match
        } else if lower.contains("main") || lower.contains("메인") || (lower.contains("compound") && !lower.contains("accessory")) {
            self = .mainCompound
        } else if lower.contains("isolation") || lower.contains("고립") || lower.contains("레이즈") || lower.contains("raise") || lower.contains("fly") || lower.contains("lateral") {
            self = .isolation
        } else if lower.contains("core") || lower.contains("finisher") || lower.contains("코어") || lower.contains("마무리") || lower.contains("복근") {
            self = .coreFinisher
        } else if lower.contains("accessory") || lower.contains("보조") || lower.contains("secondary") {
            self = .accessory
        } else {
            self = .accessory
        }
    }

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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let match = RepType(rawValue: raw) {
            self = match
        } else if raw.localizedCaseInsensitiveContains("failure") || raw.contains("실패") {
            self = .toFailure
        } else if raw.localizedCaseInsensitiveContains("timed") || raw.contains("시간") || raw.contains("초") {
            self = .timedSeconds
        } else if raw.localizedCaseInsensitiveContains("fixed") || raw.contains("고정") {
            self = .fixedReps
        } else {
            self = .repsRange
        }
    }
}

public enum JobStatus: String, Codable, Sendable {
    case processing = "PROCESSING"
    case completed = "COMPLETED"
    case failed = "FAILED"

    public var isTerminal: Bool { self != .processing }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self).uppercased()
        if let match = JobStatus(rawValue: raw) {
            self = match
        } else if raw.contains("COMPLETE") || raw.contains("SUCCESS") || raw.contains("DONE") {
            self = .completed
        } else if raw.contains("FAIL") || raw.contains("ERROR") {
            self = .failed
        } else {
            self = .processing
        }
    }
}
