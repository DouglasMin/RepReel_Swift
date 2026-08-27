import ReelsKit
import SwiftUI

struct WorkoutSessionView: View {
    let store: WorkoutSessionStore
    let onFinish: () -> Void
    let onDiscard: () -> Void

    @State private var expandedRPE: String?
    @State private var confirmDiscard = false
    @FocusState private var focused: WorkoutFieldID?
    @State private var swapTarget: Int?

    /// Every text field in visit order, so 이전/다음 can step across exercises.
    private var fieldOrder: [WorkoutFieldID] {
        store.draft.exercises.enumerated().flatMap { exerciseIndex, exercise in
            exercise.sets.indices.flatMap { setIndex in
                [WorkoutFieldID(exercise: exerciseIndex, set: setIndex, kind: .weight),
                 WorkoutFieldID(exercise: exerciseIndex, set: setIndex, kind: .reps)]
            }
        }
    }

    private func step(_ offset: Int) {
        guard let focused, let index = fieldOrder.firstIndex(of: focused) else { return }
        let next = index + offset
        guard fieldOrder.indices.contains(next) else { return }
        self.focused = fieldOrder[next]
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            header

            if store.isOrphaned {
                ContentUnavailableView(
                    "루틴을 찾을 수 없습니다",
                    systemImage: "questionmark.folder",
                    description: Text("이 기록이 속한 루틴이 삭제되었습니다. 삭제만 가능합니다.")
                )
            } else {
                list
            }

            footer
        }
        .overlay(alignment: .bottom) {
            if let endsAt = store.restEndsAt {
                RestTimerBar(endsAt: endsAt) { store.dismissRest() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 92)
            }
        }
        .sheet(item: Binding(get: { swapTarget.map(SwapTarget.init) },
                             set: { swapTarget = $0?.index })) { target in
            ExerciseSwapSheet(store: store, exerciseIndex: target.index) { item in
                store.swap(exercise: target.index, to: item)
            }
        }
        .confirmationDialog("이 운동을 삭제할까요?", isPresented: $confirmDiscard,
                            titleVisibility: .visible) {
            Button("삭제", role: .destructive, action: onDiscard)
            Button("취소", role: .cancel) {}
        } message: {
            Text("기록한 세트가 모두 사라집니다. 되돌릴 수 없습니다.")
        }
    }

    private var grabber: some View {
        Capsule().fill(.secondary.opacity(0.5))
            .frame(width: 36, height: 5).padding(.top, 8)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(store.draft.dayTitle).font(.headline)
            if let analytics = store.analytics {
                Text(analytics.volumeSummaryString)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private var list: some View {
        List {
            ForEach(Array(store.draft.exercises.enumerated()), id: \.element.id) { exerciseIndex, exercise in
                Section {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                        SetRow(
                            set: set,
                            exerciseIndex: exerciseIndex,
                            setIndex: setIndex,
                            isRPEExpanded: expandedRPE == "\(exercise.id)-\(set.setNumber)",
                            focused: $focused,
                            onToggle: { store.completeSet(exercise: exerciseIndex, set: setIndex) },
                            onWeight: { store.setWeight($0, exercise: exerciseIndex, set: setIndex) },
                            onReps: { store.setReps($0, exercise: exerciseIndex, set: setIndex) },
                            onRPE: { store.setRPE($0, exercise: exerciseIndex, set: setIndex) },
                            onToggleRPE: {
                                let key = "\(exercise.id)-\(set.setNumber)"
                                expandedRPE = expandedRPE == key ? nil : key
                            }
                        )
                        .listRowInsets(.init(top: 2, leading: 12, bottom: 2, trailing: 12))
                    }
                } header: {
                    HStack {
                        Image(systemName: exercise.equipment.iconName)
                        Text(exercise.exerciseName).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(exercise.prescription).font(.caption).foregroundStyle(.secondary)
                        Menu {
                            Button("대체 운동 찾기", systemImage: "arrow.triangle.swap") {
                                swapTarget = exerciseIndex
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                        }
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("이전") { step(-1) }
                    .disabled(focused.flatMap { fieldOrder.firstIndex(of: $0) } == 0)
                Button("다음") { step(1) }
                    .disabled(focused.flatMap { fieldOrder.firstIndex(of: $0) }
                        == fieldOrder.count - 1)
                Spacer()
                Button("완료") { focused = nil }.fontWeight(.semibold)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("삭제", role: .destructive) { confirmDiscard = true }
                .buttonStyle(.bordered)

            Button("운동 끝내기", action: onFinish)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(store.isOrphaned)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }
}


private struct SwapTarget: Identifiable {
    let index: Int
    var id: Int { index }
}
