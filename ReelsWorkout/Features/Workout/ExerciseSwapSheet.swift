import ReelsKit
import SwiftUI

struct ExerciseSwapSheet: View {
    let store: WorkoutSessionStore
    let exerciseIndex: Int
    let onPick: (ExerciseSubstituteItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ExerciseSubstituteItem] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ContentUnavailableView("대체 운동을 불러오지 못했습니다",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else if items.isEmpty {
                    ProgressView()
                } else {
                    List(items) { item in
                        Button {
                            onPick(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.exerciseName).font(.subheadline.weight(.semibold))
                                Text(item.equipment).font(.caption).foregroundStyle(.secondary)
                                if let rationale = item.rationale {
                                    Text(rationale).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("대체 운동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .task {
            do { items = try await store.substitutes(for: exerciseIndex) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
