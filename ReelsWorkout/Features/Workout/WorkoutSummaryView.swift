import ReelsKit
import SwiftUI

/// Replaces the workout's content in place, so the session becomes the report
/// rather than a new screen appearing over it.
struct WorkoutSummaryView: View {
    let log: WorkoutSessionLog
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.secondary.opacity(0.5))
                .frame(width: 36, height: 5).padding(.top, 8)

            ScrollView {
                VStack(spacing: 24) {
                    headline
                    if let breakdown = log.volumeAnalytics?.exerciseBreakdown, !breakdown.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(breakdown) { ExerciseVolumeCard(item: $0) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 32)
            }

            Button("확인", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
        }
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text("운동 완료").font(.subheadline).foregroundStyle(.secondary)

            Text(volumeText)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
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
            parts.append("\(duration / 60)분")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ExerciseVolumeCard: View {
    let item: ExerciseVolumeAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.exerciseName).font(.subheadline.weight(.semibold))

            HStack(spacing: 14) {
                stat("볼륨", "\(item.volumeKg.formatted(.number.precision(.fractionLength(0...1)))) kg")
                if let top = item.topSetWeightKg {
                    stat("최고", "\(top.formatted(.number.precision(.fractionLength(0...1)))) kg")
                }
                if let orm = item.estimated1rmKg {
                    stat("추정 1RM", "\(orm.formatted(.number.precision(.fractionLength(0...1)))) kg")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit().weight(.medium))
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
