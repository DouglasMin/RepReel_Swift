import ReelsKit
import SwiftUI

/// Collapsed state of the workout container: what is running, for how long, and
/// how much has been moved. Tonnage comes from the server, never recomputed here.
struct WorkoutBar: View {
    let store: WorkoutSessionStore

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.isOrphaned ? .orange : .red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                // An orphaned draft cannot be continued, only discarded — say so
                // rather than inviting a tap that leads nowhere.
                Text(store.isOrphaned ? "\(store.draft.dayTitle) · 루틴 없음"
                                      : store.draft.dayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let analytics = store.analytics {
                    Text(analytics.volumeSummaryString)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(elapsed(at: timeline.date))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.up").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func elapsed(at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince1970) - store.draft.startedAt)
        let hours = seconds / 3600
        guard hours > 0 else {
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        return String(format: "%d:%02d:%02d", hours, (seconds % 3600) / 60, seconds % 60)
    }
}
