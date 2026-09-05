import ReelsKit
import SwiftUI

/// Collapsed state of the workout container: what is running, for how long, and
/// how much has been moved. Tonnage comes from the server, never recomputed here.
struct WorkoutBar: View {
    let store: WorkoutSessionStore

    var body: some View {
        let isFinished: Bool = {
            if case .finished = store.finishState { return true }
            return false
        }()

        HStack(spacing: 12) {
            // Indicator: Green checkmark if finished, else live pulsing indicator
            if isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(hex: "#34C759"))
            } else {
                ZStack {
                    Circle()
                        .fill(store.isOrphaned ? Color.orange.opacity(0.3) : Theme.brandPrimary.opacity(0.3))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(store.isOrphaned ? Color.orange : Theme.brandPrimary)
                        .frame(width: 10, height: 10)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isFinished ? "\(store.draft.dayTitle) · 운동 완료" : (store.isOrphaned ? "\(store.draft.dayTitle) · 루틴 없음" : store.draft.dayTitle))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isFinished {
                    Text("탭하여 요약 리포트 보기")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else if let analytics = store.analytics {
                    Text(analytics.volumeSummaryString)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isFinished {
                HStack(spacing: 4) {
                    Text("리포트")
                        .font(.caption.weight(.bold))
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Color(hex: "#34C759"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "#34C759").opacity(0.12), in: .capsule)
            } else {
                // Live Timer & Expand hint
                HStack(spacing: 8) {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        if let restEndsAt = store.restEndsAt, restEndsAt > timeline.date {
                            let remaining = max(0, Int(restEndsAt.timeIntervalSince(timeline.date)))
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                            }
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.orange, in: .capsule)
                        } else {
                            Text(elapsed(at: timeline.date))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.brandPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Theme.brandPrimary.opacity(0.12), in: .capsule)
                        }
                    }

                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(store.isOrphaned ? "\(store.draft.dayTitle), 루틴 없음. 탭하여 열기" : "\(store.draft.dayTitle), 운동 진행 중. 탭하여 열기")
        .accessibilityAddTraits(.isButton)
        .padding(.horizontal, 16)
        .frame(height: 60)
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
