import ReelsKit
import SwiftUI

struct ProgramDetailView: View {
    let programId: String
    var onUpdated: ((WorkoutProgramResponse) -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var program: WorkoutProgramResponse?
    @State private var errorMessage: String?
    @State private var pendingStart: WorkoutDay?
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    var body: some View {
        List {
            if let program {
                // Program Overview Hero Card
                Section {
                    ProgramHeroCard(program: program)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)

                if let audit = program.audit, audit.needsReview {
                    Section { AuditBanner(audit: audit) }
                }

                // Days Section
                ForEach(program.days) { day in
                    Section {
                        DayHeaderCard(
                            day: day,
                            onStartTap: {
                                if environment.hasWorkoutInProgress {
                                    pendingStart = day
                                } else {
                                    environment.startWorkout(programId: programId, day: day)
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)

                        ForEach(day.normalizedExerciseGroups) { group in
                            ExerciseGroupCard(group: group)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                    }
                }

                if let progression = program.progression {
                    Section("점진적 과부하 가이드") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(progression.overloadStrategy)
                                .font(.subheadline)
                            if let recovery = progression.recoveryGuidance {
                                Text(recovery)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView("불러오지 못했습니다", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .background(Theme.listBackground)
        .navigationTitle(program?.title ?? "루틴 상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if program != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isEditing = true
                        } label: {
                            Label("루틴 편집", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("루틴 삭제", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let program {
                EditProgramSheet(program: program) { updated in
                    self.program = updated
                    onUpdated?(updated)
                }
            }
        }
        .confirmationDialog(
            "루틴 삭제",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("루틴 삭제", role: .destructive) {
                Task {
                    try? await environment.client.deleteProgram(id: programId)
                    onDeleted?()
                    dismiss()
                }
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("'\(program?.title ?? "루틴")'을(를) 삭제하시겠습니까?\n삭제된 루틴은 복구할 수 없습니다.")
        }
        .task { await load() }
        .confirmationDialog(
            "진행 중인 운동이 있습니다",
            isPresented: .init(get: { pendingStart != nil },
                               set: { if !$0 { pendingStart = nil } }),
            titleVisibility: .visible
        ) {
            Button("기존 기록 삭제하고 시작", role: .destructive) {
                if let day = pendingStart {
                    Task { await environment.replaceWorkout(programId: programId, day: day) }
                }
                pendingStart = nil
            }
            Button("취소", role: .cancel) { pendingStart = nil }
        } message: {
            Text("새 운동을 시작하면 진행 중이던 기록이 사라집니다.")
        }
    }

    private func load() async {
        do {
            program = try await environment.client.program(id: programId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Program Hero Card

private struct ProgramHeroCard: View {
    let program: WorkoutProgramResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    if let creator = program.creator, !creator.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.brandPrimary)
                            Text(creator)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                if let split = program.splitType {
                    Text(split.rawValue)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.brandPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.brandPrimary.opacity(0.12), in: .capsule)
                }

                if let cycle = program.cycleFrequency, !cycle.isEmpty {
                    Label(cycle, systemImage: "repeat")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text("\(program.days.count) Days")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: .capsule)
            }

            if let overview = program.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.brandPrimary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        )
    }
}

// MARK: - Day Header Card

private struct DayHeaderCard: View {
    let day: WorkoutDay
    let onStartTap: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(day.dayTitle)
                    .font(.headline.weight(.bold))
                if let focus = day.dayFocus {
                    Text(focus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onStartTap) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                    Text("운동 시작")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.brandGradient, in: .capsule)
                .shadow(color: Theme.brandPrimary.opacity(0.35), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Exercise Group Card

private struct ExerciseGroupCard: View {
    let group: ExerciseGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(group.category.shortLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color(hex: group.category.badgeColorHex), in: .capsule)

                if let region = group.targetRegion {
                    Text(region)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(group.exercises) { exercise in
                ExerciseRow(exercise: exercise)
                if exercise.id != group.exercises.last?.id {
                    Divider().opacity(0.4)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        )
    }
}

private struct ExerciseRow: View {
    let exercise: StructuredExercise

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.brandPrimary.opacity(0.10))
                    .frame(width: 36, height: 36)
                Image(systemName: exercise.equipment.iconName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.canonicalNameKo)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if !exercise.primaryMuscle.isEmpty {
                        Text(exercise.primaryMuscle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05), in: .capsule)
                    }
                }

                HStack(spacing: 8) {
                    if let rest = exercise.volume.restDisplayString {
                        Label(rest, systemImage: "timer")
                    }
                    if let rpe = exercise.volume.rpeTarget {
                        Text("RPE \(rpe, format: .number.precision(.fractionLength(0...1)))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(exercise.volume.volumeDisplayString)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(Theme.brandPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.brandPrimary.opacity(0.08), in: .capsule)
        }
        .padding(.vertical, 2)
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
            .foregroundStyle(.orange)
            ForEach(audit.userActionItems, id: \.self) { item in
                Text("• \(item)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
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
