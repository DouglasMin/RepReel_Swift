import ReelsKit
import SwiftUI

/// Modal sheet for reordering exercises via touch and drag during an active workout session.
struct ReorderExercisesSheet: View {
    let store: WorkoutSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [DraftExercise] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Theme.brandPrimary.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: exercise.equipment.iconName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.brandPrimary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.exerciseName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                HStack(spacing: 6) {
                                    Text(exercise.prescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    let completedCount = exercise.sets.count(where: \.completed)
                                    if completedCount > 0 {
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("\(completedCount)/\(exercise.sets.count)세트 완료")
                                            .font(.caption.monospacedDigit().weight(.medium))
                                            .foregroundStyle(completedCount == exercise.sets.count ? Color(hex: "#34C759") : Theme.brandPrimary)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { source, destination in
                        exercises.move(fromOffsets: source, toOffset: destination)
                        store.moveExercise(from: source, to: destination)
                    }
                } header: {
                    Text("원하는 순서대로 드래그하여 배치하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("운동 순서 변경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .tint(Theme.brandPrimary)
                }
            }
            .onAppear {
                exercises = store.draft.exercises
            }
        }
    }
}
