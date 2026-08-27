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

    private var isFailed: Bool {
        if case .failed = store.finishState { return true }
        return false
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
                RestTimerBar(
                    endsAt: endsAt,
                    onAdjust: { store.adjustRest(by: $0) },
                    onDismiss: { store.dismissRest() }
                )
                .id(endsAt)
                .padding(.horizontal, 16)
                .padding(.bottom, 84)
                .zIndex(100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: Binding(get: { swapTarget.map(SwapTarget.init) },
                             set: { swapTarget = $0?.index })) { target in
            ExerciseSwapSheet(store: store, exerciseIndex: target.index) { item in
                store.swap(exercise: target.index, to: item)
            }
        }
        .alert("저장하지 못했습니다", isPresented: .constant(isFailed)) {
            Button("다시 시도") { onFinish() }
            Button("취소", role: .cancel) { store.finishState = .idle }
        } message: {
            if case .failed(let message) = store.finishState { Text(message) }
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
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.draft.dayTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)

                    if let analytics = store.analytics {
                        Text(analytics.volumeSummaryString)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Progress ratio chip
                HStack(spacing: 4) {
                    Text("\(store.draft.completedSetCount)")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.brandPrimary)
                        .contentTransition(.numericText())

                    Text("/ \(store.draft.totalSetCount) 세트")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.brandPrimary.opacity(0.10), in: .capsule)
            }

            // Animated Gradient Progress Bar
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 6)

                    Capsule()
                        .fill(Theme.brandGradient)
                        .frame(width: max(0, proxy.size.width * CGFloat(store.draft.progressFraction)), height: 6)
                        .animation(.spring(duration: 0.4, bounce: 0.1), value: store.draft.progressFraction)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var list: some View {
        List {
            ForEach(Array(store.draft.exercises.enumerated()), id: \.offset) { exerciseIndex, exercise in
                Section {
                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { setIndex, set in
                        SetRow(
                            set: set,
                            exerciseIndex: exerciseIndex,
                            setIndex: setIndex,
                            isRPEExpanded: expandedRPE == "\(exerciseIndex)-\(set.setNumber)",
                            focused: $focused,
                            onToggle: { store.completeSet(exercise: exerciseIndex, set: setIndex) },
                            onWeight: { store.setWeight($0, exercise: exerciseIndex, set: setIndex) },
                            onCommitWeight: { store.commitWeight($0, exercise: exerciseIndex, set: setIndex) },
                            onReps: { store.setReps($0, exercise: exerciseIndex, set: setIndex) },
                            onRPE: { store.setRPE($0, exercise: exerciseIndex, set: setIndex) },
                            onToggleRPE: {
                                let key = "\(exerciseIndex)-\(set.setNumber)"
                                expandedRPE = expandedRPE == key ? nil : key
                            }
                        )
                        .listRowInsets(.init(top: 2, leading: 12, bottom: 2, trailing: 12))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if exercise.sets.count > 1 {
                                Button(role: .destructive) {
                                    store.removeSet(exercise: exerciseIndex, set: setIndex)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        store.addSet(exercise: exerciseIndex)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("세트 추가")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.brandPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                } header: {
                    HStack(spacing: 8) {
                        Image(systemName: exercise.equipment.iconName)
                            .foregroundStyle(Theme.brandPrimary)
                        Text(exercise.exerciseName)
                            .font(.subheadline.weight(.semibold))

                        let completedInThis = exercise.sets.count(where: \.completed)
                        let totalInThis = exercise.sets.count
                        if completedInThis == totalInThis && totalInThis > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("완료")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#34C759"), in: .capsule)
                            .transition(.scale.combined(with: .opacity))
                        } else if completedInThis > 0 {
                            Text("\(completedInThis)/\(totalInThis)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.brandPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.brandPrimary.opacity(0.10), in: .capsule)
                        }

                        Spacer()

                        Text(exercise.prescription).font(.caption).foregroundStyle(.secondary)

                        Menu {
                            Button("세트 추가", systemImage: "plus") {
                                store.addSet(exercise: exerciseIndex)
                            }
                            Button("대체 운동 찾기", systemImage: "arrow.triangle.swap") {
                                swapTarget = exerciseIndex
                            }
                            Menu("휴식 시간 변경 (\(exercise.effectiveRestSeconds)초)", systemImage: "timer") {
                                Button("30초") { store.setRestSeconds(30, exercise: exerciseIndex) }
                                Button("60초 (1분)") { store.setRestSeconds(60, exercise: exerciseIndex) }
                                Button("90초 (1분 30초)") { store.setRestSeconds(90, exercise: exerciseIndex) }
                                Button("120초 (2분)") { store.setRestSeconds(120, exercise: exerciseIndex) }
                                Button("180초 (3분)") { store.setRestSeconds(180, exercise: exerciseIndex) }
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
        let isSaving: Bool = {
            if case .saving = store.finishState { return true }
            return false
        }()

        return HStack(spacing: 12) {
            Button("삭제", role: .destructive) { confirmDiscard = true }
                .buttonStyle(.bordered)

            Button(action: onFinish) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("운동 끝내기")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isOrphaned || isSaving)
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
