import ReelsKit
import SwiftUI

/// Sheet to edit completed workout session sets, weights, reps, duration, and notes.
struct EditSessionSheet: View {
    let session: WorkoutSessionLog
    let onSave: (WorkoutSessionLog) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var notes: String
    @State private var durationMinutes: Int
    @State private var exercises: [ExecutedExerciseLog]
    @State private var isSaving = false

    init(session: WorkoutSessionLog, onSave: @escaping (WorkoutSessionLog) async -> Void) {
        self.session = session
        self.onSave = onSave
        _notes = State(initialValue: session.sessionNotes ?? "")
        _durationMinutes = State(initialValue: (session.durationSeconds ?? 0) / 60)
        _exercises = State(initialValue: session.completedExercises)
    }

    private var calculatedTotalVolumeKg: Double {
        exercises.reduce(0) { total, ex in
            total + ex.sets.filter(\.completed).reduce(0) { setTotal, s in
                setTotal + (s.weightKg * Double(s.reps))
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                exercisesSection
            }
            .navigationTitle("운동 기록 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveChanges()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("저장")
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.brandPrimary)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var basicInfoSection: some View {
        Section("기본 정보") {
            HStack {
                Text("운동 시간")
                Spacer()
                TextField("분", value: $durationMinutes, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("분")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("운동 메모")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("메모를 입력하세요...", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            HStack {
                Text("총 예상 볼륨")
                Spacer()
                Text("\(calculatedTotalVolumeKg.formatted(.number.precision(.fractionLength(0...1)))) kg")
                    .font(.body.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.brandPrimary)
            }
        }
    }

    private var exercisesSection: some View {
        ForEach(Array(exercises.enumerated()), id: \.element.id) { exIndex, exercise in
            Section {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                    setRow(exIndex: exIndex, setIndex: setIndex, set: set)
                }
                .onDelete { indexSet in
                    deleteSet(at: indexSet, in: exIndex)
                }

                Button {
                    addSet(to: exIndex)
                } label: {
                    Label("세트 추가", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.brandPrimary)
                }
            } header: {
                Text(exercise.exerciseName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func setRow(exIndex: Int, setIndex: Int, set: LoggedSet) -> some View {
        HStack(spacing: 12) {
            Text("\(set.setNumber)세트")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

            HStack(spacing: 4) {
                TextField("무게", value: Binding(
                    get: { exercises[exIndex].sets[setIndex].weightKg },
                    set: { exercises[exIndex].sets[setIndex].weightKg = $0 }
                ), format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit())
                .frame(width: 54)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                Text("kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                TextField("회", value: Binding(
                    get: { exercises[exIndex].sets[setIndex].reps },
                    set: { exercises[exIndex].sets[setIndex].reps = $0 }
                ), format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit())
                .frame(width: 44)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                Text("회")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                exercises[exIndex].sets[setIndex].completed.toggle()
            } label: {
                Image(systemName: exercises[exIndex].sets[setIndex].completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(exercises[exIndex].sets[setIndex].completed ? Theme.brandPrimary : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func deleteSet(at indexSet: IndexSet, in exIndex: Int) {
        exercises[exIndex].sets.remove(atOffsets: indexSet)
        for i in exercises[exIndex].sets.indices {
            let old = exercises[exIndex].sets[i]
            exercises[exIndex].sets[i] = LoggedSet(
                setNumber: i + 1,
                weightKg: old.weightKg,
                reps: old.reps,
                rpe: old.rpe,
                completed: old.completed
            )
        }
    }

    private func addSet(to exIndex: Int) {
        let nextNumber = (exercises[exIndex].sets.last?.setNumber ?? 0) + 1
        let lastWeight = exercises[exIndex].sets.last?.weightKg ?? 0
        let lastReps = exercises[exIndex].sets.last?.reps ?? 10
        exercises[exIndex].sets.append(
            LoggedSet(setNumber: nextNumber, weightKg: lastWeight, reps: lastReps, completed: true)
        )
    }

    private func saveChanges() {
        Task {
            isSaving = true
            var updated = session
            updated.completedExercises = exercises
            updated.sessionNotes = notes.isEmpty ? nil : notes
            let totalSets = exercises.flatMap(\.sets).filter(\.completed).count
            let totalReps = exercises.flatMap(\.sets).filter(\.completed).reduce(0) { $0 + $1.reps }
            let breakdown = exercises.map { ex in
                let exVol = ex.sets.filter(\.completed).reduce(0.0) { $0 + ($1.weightKg * Double($1.reps)) }
                let topWeight = ex.sets.filter(\.completed).map(\.weightKg).max()
                return ExerciseVolumeAnalytics(
                    exerciseId: ex.exerciseId,
                    exerciseName: ex.exerciseName,
                    volumeKg: exVol,
                    completedSets: ex.sets.filter(\.completed).count,
                    completedReps: ex.sets.filter(\.completed).reduce(0) { $0 + $1.reps },
                    topSetWeightKg: topWeight,
                    estimated1rmKg: topWeight
                )
            }
            updated.volumeAnalytics = WorkoutVolumeAnalytics(
                totalVolumeKg: calculatedTotalVolumeKg,
                totalSetsCompleted: totalSets,
                totalRepsCompleted: totalReps,
                exerciseBreakdown: breakdown
            )
            await onSave(updated)
            isSaving = false
            dismiss()
        }
    }
}
