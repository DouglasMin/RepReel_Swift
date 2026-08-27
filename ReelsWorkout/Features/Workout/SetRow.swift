import ReelsKit
import SwiftUI

/// One set. Press feedback fires on touch-*down*; the haptic generator is primed
/// there too, so the tap and the tap-back land on the same frame.
/// Identifies one text field across the whole workout, so the keyboard toolbar
/// can step 이전/다음 between rows and exercises.
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

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private var weightFieldID: WorkoutFieldID {
        WorkoutFieldID(exercise: exerciseIndex, set: setIndex, kind: .weight)
    }

    private var repsFieldID: WorkoutFieldID {
        WorkoutFieldID(exercise: exerciseIndex, set: setIndex, kind: .reps)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("\(set.setNumber)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                stepper("−2.5") { adjustWeight(by: -2.5) }

                field($weightText, placeholder: "kg", width: 62)
                    .focused($focused, equals: weightFieldID)
                    .onChange(of: weightText) { _, new in
                        if focused == weightFieldID {
                            onWeight(Double(new))
                        }
                    }
                    .onSubmit {
                        commitWeight()
                    }

                stepper("+2.5") { adjustWeight(by: 2.5) }

                TextField("회", text: $repsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.body.monospacedDigit())
                    .frame(width: 48)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                    .focused($focused, equals: repsFieldID)
                    .onChange(of: repsText) { _, new in
                        if focused == repsFieldID, let r = Int(new) {
                            onReps(r)
                        }
                    }

                Spacer(minLength: 4)

                Button(action: onToggleRPE) {
                    Text(set.rpe.map { "RPE \($0.formatted(.number.precision(.fractionLength(0...1))))" } ?? "RPE")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(set.rpe == nil ? .secondary : Theme.brandPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(set.rpe != nil ? Theme.brandPrimary.opacity(0.12) : Color.clear, in: .capsule)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                completionCircle
            }

            if isRPEExpanded { rpeScale }
        }
        .padding(.vertical, 6)
        .background(
            // Fills outward from the circle, so the motion starts where the finger did.
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.brandPrimary.opacity(set.completed ? 0.08 : 0))
        )
        .sensoryFeedback(.success, trigger: set.completed)
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
            if text != weightText { weightText = text } // reflect carry-down
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
                .strokeBorder(set.completed ? Theme.brandPrimary : .secondary.opacity(0.4),
                              lineWidth: 2)
                .background(Circle().fill(set.completed ? Theme.brandPrimary : .clear))
                .frame(width: 32, height: 32)

            Checkmark(progress: set.completed ? 1 : 0)
                .stroke(.white, style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 12)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.92 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.15)
                                : .spring(duration: 0.3, bounce: 0.2), value: set.completed)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let inside = CGRect(x: 0, y: 0, width: 44, height: 44).contains(value.location)
                    if inside != isPressed {
                        isPressed = inside
                        if inside { haptic.prepare() }
                    }
                }
                .onEnded { _ in
                    if isPressed { haptic.impactOccurred(); onToggle() }
                    isPressed = false
                }
        )
    }

    private var rpeScale: some View {
        HStack(spacing: 4) {
            ForEach(Array(stride(from: 6.0, through: 10.0, by: 0.5)), id: \.self) { value in
                Button {
                    onRPE(set.rpe == value ? nil : value)
                } label: {
                    Text(value.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(set.rpe == value ? Theme.brandPrimary.opacity(0.20) : Color.primary.opacity(0.04),
                                    in: .rect(cornerRadius: 8))
                        .foregroundStyle(set.rpe == value ? Theme.brandPrimary : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
        .animation(.spring(duration: 0.3, bounce: 0), value: isRPEExpanded)
    }

    private func stepper(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.caption2.monospacedDigit().weight(.medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.mini)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private func field(_ text: Binding<String>, placeholder: String, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .frame(width: width, height: 34)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    private func adjustWeight(by delta: Double) {
        let current = Double(weightText) ?? 0
        let next = max(0, current + delta)
        weightText = next.formatted(.number.precision(.fractionLength(0...1)))
        onCommitWeight(next)
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
#if DEBUG
#Preview("SetRow") {
    @Previewable @State var set = DraftSet(setNumber: 1, weightKg: 80, reps: 10)
    @Previewable @State var rpeOpen = false
    @Previewable @FocusState var focused: WorkoutFieldID?

    List {
        SetRow(set: set, exerciseIndex: 0, setIndex: 0, isRPEExpanded: rpeOpen,
               focused: $focused,
               onToggle: { set.completed.toggle() },
               onWeight: { set.weightKg = $0 },
               onCommitWeight: { set.weightKg = $0 },
               onReps: { set.reps = $0 },
               onRPE: { set.rpe = $0 },
               onToggleRPE: { rpeOpen.toggle() })
    }
}
#endif
