import ReelsKit
import SwiftUI

/// Detailed inspection view for a completed past workout session log.
struct SessionDetailView: View {
    let session: WorkoutSessionLog
    var store: HistoryStore? = nil
    var onDeleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var currentSession: WorkoutSessionLog
    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var isDeleting = false

    init(session: WorkoutSessionLog, store: HistoryStore? = nil, onDeleted: (() -> Void)? = nil) {
        self.session = session
        self.store = store
        self.onDeleted = onDeleted
        _currentSession = State(initialValue: session)
    }

    private var formattedDate: String {
        guard let loggedAt = currentSession.loggedAt else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(loggedAt))
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var durationString: String? {
        guard let durationSeconds = currentSession.durationSeconds, durationSeconds > 0 else { return nil }
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return "\(hours)시간 \(remMinutes)분"
        }
        return seconds > 0 ? "\(minutes)분 \(seconds)초" : "\(minutes)분"
    }

    var body: some View {
        List {
            // Header Stats Hero Card
            Section {
                headerCard
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            if let notes = currentSession.sessionNotes, !notes.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("운동 메모", systemImage: "text.bubble.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.brandPrimary)
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.cardBackground)
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if let analytics = currentSession.volumeAnalytics, !analytics.exerciseBreakdown.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("종목별 볼륨 기여도", systemImage: "chart.pie.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.brandPrimary)

                        ForEach(analytics.exerciseBreakdown) { item in
                            ExerciseVolumeRow(item: item)
                            if item.id != analytics.exerciseBreakdown.last?.id {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.cardBackground)
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(currentSession.completedExercises) { exercise in
                    ExerciseDetailCard(exercise: exercise)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            } header: {
                Text("수행한 운동 세트")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .listStyle(.plain)
        .background(Theme.listBackground)
        .navigationTitle(currentSession.dayNumber > 0 ? "Day \(currentSession.dayNumber) 기록" : "운동 상세 기록")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isEditing = true
                    } label: {
                        Label("기록 수정", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("기록 삭제", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditSessionSheet(session: currentSession) { updated in
                currentSession = updated
                if let store {
                    Task { try? await store.updateSession(updated) }
                } else {
                    Task { try? await environment.client.updateSession(id: updated.sessionId ?? updated.id, updated) }
                }
            }
        }
        .confirmationDialog(
            "운동 기록 삭제",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                Task {
                    isDeleting = true
                    let sid = currentSession.sessionId ?? currentSession.id
                    if let store {
                        try? await store.deleteSession(id: sid)
                    } else {
                        _ = try? await environment.client.deleteSession(id: sid)
                    }
                    onDeleted?()
                    isDeleting = false
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 운동 기록을 완전히 삭제하시겠습니까?\n삭제된 기록은 복구할 수 없습니다.")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentSession.programId)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.brandPrimary)
                        .lineLimit(1)
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let duration = durationString {
                    Label(duration, systemImage: "clock")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.secondary.opacity(0.12), in: .capsule)
                }
            }

            Divider()

            if let analytics = currentSession.volumeAnalytics {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("총 볼륨")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(analytics.totalVolumeKg.formatted(.number.precision(.fractionLength(0...1)))) kg")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.brandGradient)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("완료 세트")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(analytics.totalSetsCompleted) 세트")
                            .font(.title3.weight(.bold))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("완료 반복수")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(analytics.totalRepsCompleted) 회")
                            .font(.title3.weight(.bold))
                    }
                }
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

private struct ExerciseVolumeRow: View {
    let item: ExerciseVolumeAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.exerciseName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(item.volumeKg.formatted(.number.precision(.fractionLength(0...1)))) kg")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.brandPrimary)
            }
            HStack(spacing: 12) {
                Text("\(item.completedSets)세트 · \(item.completedReps)회")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let topWeight = item.topSetWeightKg, topWeight > 0 {
                    Text("최고 \(topWeight.formatted())kg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let oneRepMax = item.estimated1rmKg, oneRepMax > 0 {
                    Text("추정 1RM \(oneRepMax.formatted(.number.precision(.fractionLength(0...1))))kg")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.brandSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ExerciseDetailCard: View {
    let exercise: ExecutedExerciseLog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.exerciseName)
                .font(.headline.weight(.semibold))

            VStack(spacing: 6) {
                ForEach(exercise.sets) { set in
                    HStack(spacing: 12) {
                        Text("\(set.setNumber)세트")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)

                        if set.weightKg > 0 {
                            Text("\(set.weightKg.formatted()) kg")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .frame(width: 70, alignment: .leading)
                        } else {
                            Text("맨몸")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)
                        }

                        Text("\(set.reps) 회")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 50, alignment: .leading)

                        Spacer()

                        if let rpe = set.rpe {
                            Text("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.15), in: .capsule)
                        }

                        Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(set.completed ? Theme.brandGreen : .secondary)
                    }
                    .padding(.vertical, 2)
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

#if DEBUG
#Preview("세션 상세") {
    NavigationStack {
        SessionDetailView(
            session: WorkoutSessionLog(
                sessionId: "session_demo_1",
                programId: "che-dan-sil-ppl-routine-part2",
                dayNumber: 1,
                loggedAt: Int(Date().timeIntervalSince1970),
                durationSeconds: 3120,
                completedExercises: [
                    ExecutedExerciseLog(
                        exerciseId: "bench_press",
                        exerciseName: "바벨 벤치프레스",
                        sets: [
                            LoggedSet(setNumber: 1, weightKg: 80, reps: 8, rpe: 8.0, completed: true),
                            LoggedSet(setNumber: 2, weightKg: 80, reps: 8, rpe: 8.5, completed: true),
                            LoggedSet(setNumber: 3, weightKg: 80, reps: 8, rpe: 9.0, completed: true)
                        ]
                    )
                ],
                sessionNotes: "가슴 펌핑 최고였음. 다음 주 증량 예정."
            )
        )
    }
}
#endif
