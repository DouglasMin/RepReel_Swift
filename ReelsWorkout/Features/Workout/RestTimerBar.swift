import AudioToolbox
import SwiftUI

/// Counts down from the program's prescribed rest with interactive adjustments and circular progress.
struct RestTimerBar: View {
    let endsAt: Date
    var onAdjust: ((TimeInterval) -> Void)? = nil
    let onDismiss: () -> Void

    @State private var didFire = false
    @State private var total: TimeInterval = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let remaining = max(0, endsAt.timeIntervalSince(timeline.date))
            let progress = total > 0 ? min(1.0, max(0.0, remaining / total)) : 0.0

            HStack(spacing: 12) {
                // Circular Countdown Ring
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            remaining <= 5 ? Color.orange : Theme.brandPrimary,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: progress)

                    Image(systemName: "timer")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(remaining <= 5 ? Color.orange : Theme.brandPrimary)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("휴식 중")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(format(remaining))
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .contentTransition(.numericText(countsDown: true))
                }

                Spacer(minLength: 4)

                if let onAdjust {
                    HStack(spacing: 6) {
                        Button("−15s") {
                            onAdjust(-15)
                        }
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: .capsule)
                        .buttonStyle(.plain)

                        Button("+30s") {
                            onAdjust(30)
                        }
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.brandPrimary.opacity(0.12), in: .capsule)
                        .foregroundStyle(Theme.brandPrimary)
                        .buttonStyle(.plain)
                    }
                }

                Button("건너뛰기", action: onDismiss)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.6), in: .capsule)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.brandPrimary.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            )
            .onAppear {
                if total == 0 { total = max(1, endsAt.timeIntervalSinceNow) }
            }
            .onChange(of: endsAt) { _, newEndsAt in
                let currentRemaining = newEndsAt.timeIntervalSinceNow
                if currentRemaining > total {
                    total = max(1, currentRemaining)
                }
                didFire = false
            }
            .onChange(of: remaining <= 0) { _, done in
                guard done, !didFire else { return }
                didFire = true
                AudioServicesPlaySystemSound(1007) // System chime
                UINotificationFeedbackGenerator().notificationOccurred(.success)

                // Auto-dismiss after a brief delay so the user sees the countdown finish
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(.spring(duration: 0.35)) {
                        onDismiss()
                    }
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
#if DEBUG
#Preview("RestTimerBar") {
    RestTimerBar(endsAt: .now.addingTimeInterval(45), onAdjust: { _ in }, onDismiss: {})
        .padding()
}
#endif
