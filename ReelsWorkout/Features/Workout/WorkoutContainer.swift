import SwiftUI

/// Collapsed bar ↔ full screen, driven by one continuous `progress` value so the
/// content inside tracks the drag 1:1 rather than switching at a threshold.
struct WorkoutContainer<Bar: View, Expanded: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let bar: () -> Bar
    @ViewBuilder let expanded: () -> Expanded

    /// 0 = collapsed bar, 1 = full screen. Everything is a function of this.
    @State private var progress: Double = 0
    @State private var dragStartProgress: Double?
    @State private var animation: SpringRun?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight: CGFloat = 76
    private let spring = Spring(duration: 0.3, bounce: 0.2)

    /// An in-flight spring, evaluated per frame so velocity can be handed off and
    /// sampled again on interruption.
    private struct SpringRun {
        let from: Double, to: Double, velocity: Double, start: Date
    }

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.height - barHeight
            let height = barHeight + progress * travel

            ZStack(alignment: .top) {
                bar().opacity(1 - min(1, progress * 2))
                expanded().opacity(max(0, progress * 2 - 1))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 16 + progress * 22))
            .shadow(color: .black.opacity(0.12 + progress * 0.18),
                    radius: 8 + progress * 20, y: -2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .gesture(drag(travel: travel))
            .overlay { springDriver }
        }
        .ignoresSafeArea(edges: .bottom)
        .opacity(isPresented ? 1 : 0)
        .allowsHitTesting(isPresented)
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
                        if t >= spring.settlingDuration {
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

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartProgress == nil {
                    // Interruption: adopt the in-flight position, kill the spring.
                    dragStartProgress = progress
                    animation = nil
                }
                let raw = (dragStartProgress ?? 0) - value.translation.height / travel
                progress = clampWithRubberband(raw)
            }
            .onEnded { value in
                let start = dragStartProgress ?? progress
                dragStartProgress = nil

                // Project where the flick was going, then snap to the nearer end.
                let projected = start - value.predictedEndTranslation.height / travel
                let target: Double = projected > 0.5 ? 1 : 0
                let velocity = -value.velocity.height / travel

                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2)) { progress = target }
                } else {
                    animation = SpringRun(from: progress, to: target,
                                          velocity: velocity, start: .now)
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
            WorkoutContainer(isPresented: $presented) {
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
