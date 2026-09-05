import ReelsKit
import SwiftUI

/// One set row. Clean, high-contrast, minimalist design with clear touch targets.
struct WorkoutFieldID: Hashable {
    enum Kind { case weight, reps }
    let exercise: Int
    let set: Int
    let kind: Kind
}

struct SetRow: View {
    let set: DraftSet
    let exerciseIndex: Int
    let setIndex: Int
    let isRPEExpanded: Bool
    @FocusState.Binding var focused: WorkoutFieldID?
    let onToggle: () -> Void
    let onWeight: (Double?) -> Void
    let onCommitWeight: (Double?) -> Void
    let onReps: (Int) -> Void
    let onRPE: (Double?) -> Void
    let onToggleRPE: () -> Void

    @State private var isPressed = false
    @State private var weightText = ""
    @State private var repsText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var weightFieldID: WorkoutFieldID {
        WorkoutFieldID(exercise: exerciseIndex, set: setIndex, kind: .weight)
    }

    private var repsFieldID: WorkoutFieldID {
        WorkoutFieldID(exercise: exerciseIndex, set: setIndex, kind: .reps)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Set Number
                Text("\(set.setNumber)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(set.completed ? Theme.brandPrimary : .secondary)
                    .frame(width: 22, alignment: .leading)

                // Weight Input Field
                HStack(spacing: 3) {
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .focused($focused, equals: weightFieldID)
                        .frame(width: 52)
                        .onChange(of: weightText) { _, new in
                            if focused == weightFieldID {
                                onWeight(Double(new))
                            }
                        }
                        .onSubmit {
                            commitWeight()
                        }
                    Text("kg")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(focused == weightFieldID ? Theme.brandPrimary.opacity(0.10) : Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(focused == weightFieldID ? Theme.brandPrimary.opacity(0.6) : Color.clear, lineWidth: 1.5)
                        )
                )

                // Reps Input Field
                HStack(spacing: 3) {
                    TextField("0", text: $repsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .focused($focused, equals: repsFieldID)
                        .frame(width: 42)
                        .onChange(of: repsText) { _, new in
                            if focused == repsFieldID, let r = Int(new) {
                                onReps(r)
                            }
                        }
                    Text("회")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(focused == repsFieldID ? Theme.brandPrimary.opacity(0.10) : Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(focused == repsFieldID ? Theme.brandPrimary.opacity(0.6) : Color.clear, lineWidth: 1.5)
                        )
                )

                Spacer(minLength: 0)

                // RPE Toggle Button
                Button(action: onToggleRPE) {
                    Text(set.rpe.map { "RPE \($0.formatted(.number.precision(.fractionLength(0...1))))" } ?? "RPE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(set.rpe == nil ? .secondary : Theme.brandPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(set.rpe != nil ? Theme.brandPrimary.opacity(0.12) : Color.primary.opacity(0.04), in: .capsule)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Completion Circle
                completionCircle
            }

            if isRPEExpanded { rpeScale }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(set.completed ? Theme.brandPrimary.opacity(0.08) : Color.clear)
        )
        .sensoryFeedback(.success, trigger: set.completed)
        .sensoryFeedback(.selection, trigger: weightText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("세트 \(set.setNumber): \(set.weightKg.map { "\($0) 킬로그램" } ?? "체중") \(set.reps)회")
        .accessibilityValue(set.completed ? "완료됨" : "미완료")
        .accessibilityHint("두 번 탭하여 세트 완료 여부를 변경합니다.")
        .onAppear {
            weightText = set.weightKg.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            repsText = "\(set.reps)"
        }
        .onChange(of: set.weightKg) { _, new in
            let text = new.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            if text != weightText { weightText = text }
        }
        .onChange(of: focused) { old, new in
            if old == weightFieldID && new != weightFieldID {
                commitWeight()
            }
        }
    }

    private func commitWeight() {
        onCommitWeight(Double(weightText))
    }

    private var completionCircle: some View {
        ZStack {
            Circle()
                .strokeBorder(set.completed ? Theme.brandPrimary : .secondary.opacity(0.35),
                              lineWidth: 2)
                .background(Circle().fill(set.completed ? Theme.brandPrimary : .clear))
                .frame(width: 36, height: 36)
                .shadow(color: set.completed ? Theme.brandPrimary.opacity(0.35) : .clear, radius: 4, y: 1)

            Checkmark(progress: set.completed ? 1 : 0)
                .stroke(.white, style: .init(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                .frame(width: 15, height: 13)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.88 : (set.completed ? 1.05 : 1.0))
        .animation(reduceMotion ? .easeOut(duration: 0.15)
                                : .spring(duration: 0.35, bounce: 0.25), value: set.completed)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let inside = CGRect(x: 0, y: 0, width: 44, height: 44).contains(value.location)
                    if inside != isPressed {
                        isPressed = inside
                    }
                }
                .onEnded { value in
                    let inside = CGRect(x: 0, y: 0, width: 44, height: 44).contains(value.location)
                    isPressed = false
                    if inside {
                        onToggle()
                    }
                }
        )
    }

    private var rpeScale: some View {
        HStack(spacing: 4) {
            ForEach([6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0], id: \.self) { value in
                Button {
                    onRPE(set.rpe == value ? nil : value)
                } label: {
                    Text(value.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(set.rpe == value ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            set.rpe == value ? Theme.brandPrimary : Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Strokes on rather than popping in.
private struct Checkmark: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path.trimmedPath(from: 0, to: progress)
    }
}
