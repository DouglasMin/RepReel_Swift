import SwiftUI

/// Collapsed bar ↔ full screen, driven by one continuous `progress` value so the
/// content inside tracks the drag 1:1 rather than switching at a threshold.
struct WorkoutContainer<Bar: View, Expanded: View>: View {
    @Binding var isPresented: Bool
    var initiallyExpanded: Bool = false
    @ViewBuilder let bar: () -> Bar
    @ViewBuilder let expanded: () -> Expanded

    /// 0 = collapsed bar, 1 = full screen. Everything is a function of this.
    @State private var progress: Double
    @State private var dragStartProgress: Double?
    @State private var animation: SpringRun?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight: CGFloat = 60
    private let tabBarHeight: CGFloat = 49
    private let spring = Spring(duration: 0.35, bounce: 0.15)

    init(
        isPresented: Binding<Bool> = .constant(true),
        initiallyExpanded: Bool = false,
        @ViewBuilder bar: @escaping () -> Bar,
        @ViewBuilder expanded: @escaping () -> Expanded
    ) {
        self._isPresented = isPresented
        self.initiallyExpanded = initiallyExpanded
        self._progress = State(initialValue: initiallyExpanded ? 1.0 : 0.0)
        self.bar = bar
        self.expanded = expanded
    }

    /// An in-flight spring, evaluated per frame so velocity can be handed off and
    /// sampled again on interruption.
    private struct SpringRun {
        let from: Double, to: Double, velocity: Double, start: Date
    }

    var body: some View {
        GeometryReader { geo in
            let bottomSafe = geo.safeAreaInsets.bottom
            let tabOffset = (tabBarHeight + bottomSafe) * CGFloat(1.0 - progress)
            let horizontalInset = CGFloat(10.0 * (1.0 - progress))
            let cornerRadius = CGFloat(16.0 * (1.0 - progress) + 24.0 * progress)

            let travel = max(1, geo.size.height - barHeight)
            let height = barHeight + CGFloat(progress) * travel

            ZStack(alignment: .top) {
                bar()
                    .opacity(1 - min(1, progress * 2))
                    .allowsHitTesting(progress < 0.5)
                    .accessibilityHidden(progress > 0.5)
                expanded()
                    .opacity(max(0, progress * 2 - 1))
                    .allowsHitTesting(progress >= 0.5)
                    .accessibilityHidden(progress < 0.5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.08 * (1.0 - progress)), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(0.08 + progress * 0.16),
                radius: 8 + progress * 16,
                y: -2
            )
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, tabOffset)
            .contentShape(Rectangle())
            .gesture(drag(travel: travel))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay { springDriver }
        }
        .ignoresSafeArea(edges: .bottom)
        .opacity(isPresented ? 1 : 0)
    }

    /// Evaluates the spring per frame so release velocity flows straight into the
    /// animation. `withAnimation` cannot inject initial velocity, which would
    /// leave a visible seam the instant the finger lifts.
    @ViewBuilder
    private var springDriver: some View {
        if let run = animation {
            TimelineView(.animation) { timeline in
                Color.clear
                    .onChange(of: timeline.date, initial: true) { _, now in
                        let t = now.timeIntervalSince(run.start)
                        let settling = spring.settlingDuration(
                            fromValue: run.from, toValue: run.to,
                            initialVelocity: run.velocity, epsilon: 0.001
                        )
                        if t >= settling {
                            progress = run.to
                            animation = nil
                        } else {
                            progress = spring.value(fromValue: run.from, toValue: run.to,
                                                    initialVelocity: run.velocity, time: t)
                        }
                    }
            }
            .allowsHitTesting(false)
        }
    }

    private func animateTo(target: Double, velocity: Double = 0) {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { progress = target }
        } else {
            animation = SpringRun(from: progress, to: target,
                                  velocity: velocity, start: .now)
        }
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: progress < 0.5 ? 0 : 20)
            .onChanged { value in
                if dragStartProgress == nil {
                    // Interruption: adopt the in-flight position, kill the spring.
                    if let run = animation {
                        let t = Date().timeIntervalSince(run.start)
                        let currentP = spring.value(fromValue: run.from, toValue: run.to,
                                                    initialVelocity: run.velocity, time: t)
                        progress = currentP
                        dragStartProgress = currentP
                        animation = nil
                    } else {
                        dragStartProgress = progress
                    }
                }
                let raw = (dragStartProgress ?? 0) - value.translation.height / travel
                progress = clampWithRubberband(raw)
            }
            .onEnded { value in
                let start = dragStartProgress ?? progress
                dragStartProgress = nil

                let translation = value.translation.height
                if abs(translation) < 4 {
                    // Tap on collapsed bar expands it. When expanded, taps belong to child content.
                    if progress < 0.5 {
                        animateTo(target: 1, velocity: 0)
                    }
                } else {
                    // Project where the flick was going, then snap to the nearer end.
                    let projected = start - value.predictedEndTranslation.height / travel
                    let target: Double = projected > 0.5 ? 1 : 0
                    let velocity = -value.velocity.height / travel
                    animateTo(target: target, velocity: velocity)
                }
            }
    }

    /// Progressive resistance past either end instead of a hard stop.
    private func clampWithRubberband(_ value: Double) -> Double {
        if value > 1 { return 1 + rubberband(value - 1) }
        if value < 0 { return -rubberband(-value) }
        return value
    }

    private func rubberband(_ overshoot: Double, constant: Double = 0.55) -> Double {
        (overshoot * constant) / (1 + constant * abs(overshoot))
    }
}

#if DEBUG
private struct ContainerDemo: View {
    @State private var presented = true
    var body: some View {
        ZStack {
            List(1..<20) { Text("라이브러리 항목 \($0)") }
            WorkoutContainer(isPresented: $presented, initiallyExpanded: false) {
                HStack {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("Day 1 푸쉬").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("32:14").font(.subheadline.monospacedDigit())
                }
                .padding(.horizontal, 20).padding(.top, 18)
            } expanded: {
                VStack(spacing: 12) {
                    Capsule().fill(.secondary).frame(width: 36, height: 5).padding(.top, 8)
                    Text("확장된 운동 화면").font(.title2.bold())
                    ForEach(1..<6) { Text("세트 \($0)") }
                    Spacer()
                }
            }
        }
    }
}

#Preview("Container") { ContainerDemo() }
#endif
