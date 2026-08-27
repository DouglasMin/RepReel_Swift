import SwiftUI

/// Counts down from the program's prescribed rest. Time is derived from a
/// deadline rather than a ticking counter, so backgrounding does not desync it.
struct RestTimerBar: View {
    let endsAt: Date
    let onDismiss: () -> Void

    @State private var didFire = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let remaining = max(0, endsAt.timeIntervalSince(timeline.date))

            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)

                Text(format(remaining))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText(countsDown: true))

                ProgressView(value: remaining, total: max(1, total))
                    .tint(remaining <= 5 ? .orange : .accentColor)

                Button("건너뛰기", action: onDismiss)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .onAppear { if total == 0 { total = max(1, endsAt.timeIntervalSinceNow) } }
            .onChange(of: remaining <= 0) { _, done in
                guard done, !didFire else { return }
                didFire = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Captured once so the progress bar has a stable denominator.
    @State private var total: TimeInterval = 0

    private func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
#if DEBUG
#Preview("RestTimerBar") {
    RestTimerBar(endsAt: .now.addingTimeInterval(12), onDismiss: {})
        .padding()
}
#endif
