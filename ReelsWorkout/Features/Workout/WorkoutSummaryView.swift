import ReelsKit
import SwiftUI

/// Replaces the workout's content in place, so the session becomes the report
/// rather than a new screen appearing over it.
struct WorkoutSummaryView: View {
    let log: WorkoutSessionLog
    let onDone: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var volumeFontSize: CGFloat = 42

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 5).padding(.top, 8)

            ScrollView {
                VStack(spacing: 28) {
                    headline

                    if let breakdown = log.volumeAnalytics?.exerciseBreakdown, !breakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("종목별 볼륨 리포트")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(breakdown) { item in
                                ExerciseVolumeCard(item: item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            Button(action: onDone) {
                Text("완료")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brandPrimary)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .sensoryFeedback(.success, trigger: true)
    }

    private var headline: some View {
        VStack(spacing: 12) {
            // Celebration Badge
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 72, height: 72)
                    .shadow(color: Theme.brandPrimary.opacity(0.35), radius: 12, y: 6)

                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text("운동 완료!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text(volumeText)
                    .font(.system(size: volumeFontSize, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.brandPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var volumeText: String {
        guard let total = log.volumeAnalytics?.totalVolumeKg else { return "—" }
        return "\(total.formatted(.number.precision(.fractionLength(0...1)))) kg"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let analytics = log.volumeAnalytics {
            parts.append("\(analytics.totalSetsCompleted)세트")
            parts.append("\(analytics.totalRepsCompleted)회")
        }
        if let duration = log.durationSeconds {
            parts.append("\(duration / 60)분 소요")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ExerciseVolumeCard: View {
    let item: ExerciseVolumeAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.exerciseName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(item.volumeKg.formatted(.number.precision(.fractionLength(0...1)))) kg")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.brandPrimary)
            }

            HStack(spacing: 14) {
                if let top = item.topSetWeightKg {
                    stat("최고 중량", "\(top.formatted(.number.precision(.fractionLength(0...1)))) kg")
                }
                if let orm = item.estimated1rmKg {
                    stat("추정 1RM", "\(orm.formatted(.number.precision(.fractionLength(0...1)))) kg")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        )
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

#if DEBUG
#Preview("Summary") {
    WorkoutSummaryView(
        log: WorkoutSessionLog(
            sessionId: "s1", programId: "p1", dayNumber: 1, loggedAt: 1_771_982_600,
            durationSeconds: 3720, completedExercises: [], sessionNotes: nil
        ),
        onDone: {}
    )
}
#endif
