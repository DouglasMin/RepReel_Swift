import ReelsKit
import SwiftUI

struct ProgramDetailView: View {
    let programId: String

    @Environment(AppEnvironment.self) private var environment
    @State private var program: WorkoutProgramResponse?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let program {
                if let audit = program.audit, audit.needsReview {
                    Section { AuditBanner(audit: audit) }
                }
                ForEach(program.days) { day in
                    Section {
                        ForEach(day.exerciseGroups) { group in
                            ExerciseGroupCard(group: group)
                        }
                    } header: {
                        DayHeader(day: day)
                    }
                }
                if let progression = program.progression {
                    Section("점진적 과부하") {
                        Text(progression.overloadStrategy)
                            .font(.subheadline)
                        if let recovery = progression.recoveryGuidance {
                            Text(recovery)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView("불러오지 못했습니다", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(program?.title ?? "루틴")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            program = try await environment.client.program(id: programId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DayHeader: View {
    let day: WorkoutDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.dayTitle)
                .font(.headline)
                .textCase(nil)
            if let focus = day.dayFocus {
                Text(focus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .padding(.bottom, 4)
    }
}

private struct ExerciseGroupCard: View {
    let group: ExerciseGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(group.category.shortLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: group.category.badgeColorHex), in: .capsule)
                if let region = group.targetRegion {
                    Text(region)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(group.exercises) { exercise in
                ExerciseRow(exercise: exercise)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ExerciseRow: View {
    let exercise: StructuredExercise

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: exercise.equipment.iconName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.canonicalNameKo)
                    .font(.subheadline.weight(.semibold))
                Text(exercise.volume.volumeDisplayString)
                    .font(.subheadline)
                    .monospacedDigit()
                HStack(spacing: 8) {
                    if let rest = exercise.volume.restDisplayString {
                        Text(rest)
                    }
                    if let rpe = exercise.volume.rpeTarget {
                        Text("RPE \(rpe, format: .number.precision(.fractionLength(0...1)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct AuditBanner: View {
    let audit: DataQualityAudit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                "확인 필요 (신뢰도 \(audit.confidenceScore, format: .percent.precision(.fractionLength(0))))",
                systemImage: "exclamationmark.bubble"
            )
            .font(.subheadline.weight(.semibold))
            ForEach(audit.userActionItems, id: \.self) { item in
                Text("• \(item)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview("루틴 상세") {
    NavigationStack {
        ProgramDetailView(programId: "che-dan-sil-ppl-routine-part2")
    }
    .environment(PreviewFixtures.environment())
}
#endif
