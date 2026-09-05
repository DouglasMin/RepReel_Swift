import ActivityKit
import ReelsKit
import SwiftUI
import WidgetKit

public struct WorkoutLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock Screen Live Activity Banner View
            lockScreenBanner(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI (When long-pressed on Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.isResting ? "timer.circle.fill" : "flame.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(context.state.isResting ? Color.orange : Color(red: 1.0, green: 0.27, blue: 0.23))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.exerciseName)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(context.state.statusBadge)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(context.state.isResting ? Color.orange : Color(red: 1.0, green: 0.45, blue: 0.4))
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if context.state.isResting, let endsAt = context.state.restEndsAt {
                            Text("휴식 타이머")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)

                            Text(endsAt, style: .timer)
                                .font(.title3.monospacedDigit().weight(.black))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } else {
                            Text("운동 시간")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(context.state.startedAt, style: .timer)
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.nextSetDescription)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)

                        ProgressView(
                            value: Double(context.state.totalCompletedSets),
                            total: max(1, Double(context.state.totalSetsInWorkout))
                        )
                        .tint(context.state.isResting ? Color.orange : Color(red: 1.0, green: 0.27, blue: 0.23))
                    }
                    .padding(.horizontal, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("총 \(context.state.totalCompletedSets) / \(context.state.totalSetsInWorkout) 세트 완료")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Text(context.state.dayTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Shows cumulative completed sets starting from 0 (e.g. 0세트 -> 1세트 -> 2세트...)
                HStack(spacing: 2) {
                    Image(systemName: context.state.isResting ? "checkmark.circle.fill" : "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(context.state.isResting ? Color.orange : Color(red: 1.0, green: 0.27, blue: 0.23))

                    Text("\(context.state.totalCompletedSets)세트")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } compactTrailing: {
                if context.state.isResting, let endsAt = context.state.restEndsAt {
                    Text(endsAt, style: .timer)
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(context.state.startedAt, style: .timer)
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.trailing)
                }
            } minimal: {
                if context.state.isResting {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                } else {
                    HStack(spacing: 1) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))

                        Text("\(context.state.totalCompletedSets)")
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func lockScreenBanner(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(context.state.isResting ? Color.orange.opacity(0.2) : Color(red: 1.0, green: 0.27, blue: 0.23).opacity(0.2))
                            .frame(width: 40, height: 40)

                        Image(systemName: context.state.isResting ? "timer" : "flame.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(context.state.isResting ? Color.orange : Color(red: 1.0, green: 0.27, blue: 0.23))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.exerciseName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(context.state.statusBadge)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(context.state.isResting ? Color.orange : Color(red: 1.0, green: 0.45, blue: 0.4))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if context.state.isResting, let endsAt = context.state.restEndsAt {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("휴식 타이머")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)

                        Text(endsAt, style: .timer)
                            .font(.title2.monospacedDigit().weight(.black))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("운동 시간")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(context.state.startedAt, style: .timer)
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }

            HStack {
                Text(context.state.nextSetDescription)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer()

                Text("총 \(context.state.totalCompletedSets)/\(context.state.totalSetsInWorkout) 완료")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(context.state.isResting ? Color.orange : Color(red: 1.0, green: 0.27, blue: 0.23))
                    .lineLimit(1)
            }

            ProgressView(
                value: Double(context.state.totalCompletedSets),
                total: max(1, Double(context.state.totalSetsInWorkout))
            )
            .tint(context.state.isResting ? Color.orange : Color(red: 1.0, green: 0.27, blue: 0.23))
        }
        .padding(16)
        .background(Color.black.opacity(0.88))
    }
}
