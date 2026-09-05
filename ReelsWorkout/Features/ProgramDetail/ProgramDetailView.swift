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

    private var splitColor: Color {
        guard let split = program.splitType else { return Theme.brandPrimary }
        switch split {
        case .ppl: return Theme.brandPrimary
        case .upperLower: return Color(hex: "#8B5CF6")
        case .broSplit: return Color(hex: "#EC4899")
        case .fullBody: return Color(hex: "#10B981")
        case .custom: return Color(hex: "#06B6D4")
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Ambient glow
            Circle()
                .fill(Theme.splitGradient(for: program.splitType?.rawValue))
                .frame(width: 130, height: 130)
                .blur(radius: 45)
                .opacity(0.18)
                .offset(x: 30, y: 20)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if let creator = program.creator, !creator.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.brandPrimary)
                            Text(creator)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(program.title)
                        .font(.title2.weight(.black))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let split = program.splitType {
                        Text(split.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(splitColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(splitColor.opacity(0.12), in: .capsule)
                    }

                    if let cycle = program.cycleFrequency, !cycle.isEmpty {
                        Label(cycle, systemImage: "repeat")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05), in: .capsule)
                    }

                    Text("\(program.days.count) Days")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: .capsule)
                }

                if let overview = program.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.subcardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .premiumCard(cornerRadius: 20, glowColor: splitColor)
    }
}

// MARK: - Day Header Card

private struct DayHeaderCard: View {
    let day: WorkoutDay
    let onStartTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("DAY \(day.dayNumber)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Theme.brandGradient, in: .capsule)

                    Text(day.dayTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                }

                if let focus = day.dayFocus {
                    Text(focus)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button(action: onStartTap) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                    Text("운동 시작")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Theme.brandGradient, in: .capsule)
                .shadow(color: Theme.brandPrimary.opacity(0.4), radius: 8, y: 3)
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
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(group.exercises.count)개 운동")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            ForEach(group.exercises) { exercise in
                ExerciseRow(exercise: exercise)
                if exercise.id != group.exercises.last?.id {
                    Divider().opacity(0.3).padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .premiumCard(cornerRadius: 18, glowColor: Color(hex: group.category.badgeColorHex))
    }
}

private struct ExerciseRow: View {
    let exercise: StructuredExercise

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Equipment Tile
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.brandPrimary.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: exercise.equipment.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(exercise.canonicalNameKo)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    if !exercise.primaryMuscle.isEmpty {
                        Text(exercise.primaryMuscle)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.brandPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.brandPrimary.opacity(0.08), in: .capsule)
                    }
                }

                HStack(spacing: 8) {
                    if let rest = exercise.volume.restDisplayString {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                            Text(rest)
                        }
                    }
                    if let rpe = exercise.volume.rpeTarget {
                        Text("RPE \(rpe, format: .number.precision(.fractionLength(0...1)))")
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Volume Prescription Badge
            Text(exercise.volume.volumeDisplayString)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(Theme.brandPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.brandPrimary.opacity(0.10), in: .capsule)
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
