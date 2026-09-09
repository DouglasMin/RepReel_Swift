import ReelsKit
import SwiftUI

/// A pixel-perfect, 9:16 ratio workout milestone card designed to be rendered as an image
/// and shared directly to Instagram Stories, Messages, or saved to Photos.
struct WorkoutShareCardView: View {
    let log: WorkoutSessionLog
    var programTitle: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 16)
            heroMetric
            Spacer(minLength: 20)
            metricsGrid
            Spacer(minLength: 20)
            if let breakdown = log.volumeAnalytics?.exerciseBreakdown, !breakdown.isEmpty {
                exerciseList(breakdown.prefix(4))
            }
            Spacer(minLength: 16)
            footer
        }
        .padding(28)
        .frame(width: 360, height: 640)
        .background(
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.08)

                // Ambient gradient glows
                Circle()
                    .fill(Theme.brandPrimary.opacity(0.35))
                    .frame(width: 240, height: 240)
                    .blur(radius: 60)
                    .offset(x: -90, y: -180)

                Circle()
                    .fill(Theme.brandSecondary.opacity(0.25))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: 110, y: 160)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
        )
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.brandGradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                }

                Text("RepReel")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            Text(formattedDate)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: .capsule)
        }
    }

    private var heroMetric: some View {
        VStack(spacing: 6) {
            let title = programTitle ?? (log.programId.isEmpty ? nil : log.programId)
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.brandPrimary)
                    .textCase(.uppercase)
                    .tracking(1.0)
                    .lineLimit(1)
            }

            Text("총 볼륨 (Tonnage)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            Text(totalVolumeText)
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(white: 0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }

    private var metricsGrid: some View {
        HStack(spacing: 12) {
            statCell(
                title: "소요 시간",
                value: durationText,
                icon: "clock.fill",
                tint: Theme.brandPrimary
            )
            statCell(
                title: "완료 세트",
                value: "\(log.volumeAnalytics?.totalSetsCompleted ?? 0)세트",
                icon: "checkmark.circle.fill",
                tint: Color(red: 0.1, green: 0.8, blue: 0.5)
            )
            statCell(
                title: "총 반복수",
                value: "\(log.volumeAnalytics?.totalRepsCompleted ?? 0)회",
                icon: "flame.fill",
                tint: Color.orange
            )
        }
    }

    private func statCell(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)

            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func exerciseList(_ exercises: ArraySlice<ExerciseVolumeAnalytics>) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(exercises)) { item in
                HStack {
                    Text(item.exerciseName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    if let top = item.topSetWeightKg {
                        Text("\(top.formatted(.number.precision(.fractionLength(0...1))))kg 최고")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Text("\(item.volumeKg.formatted(.number.precision(.fractionLength(0...1)))) kg")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.brandPrimary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Theme.brandPrimary)
                Text("AI Workout from Reels & Shorts")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            Text("repreel.app")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var totalVolumeText: String {
        guard let total = log.volumeAnalytics?.totalVolumeKg else { return "0 kg" }
        return "\(total.formatted(.number.precision(.fractionLength(0...1)))) kg"
    }

    private var durationText: String {
        guard let seconds = log.durationSeconds else { return "—" }
        let mins = max(1, seconds / 60)
        return "\(mins)분"
    }

    private var formattedDate: String {
        let timestamp = TimeInterval(log.loggedAt ?? Int(Date().timeIntervalSince1970))
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }
}

#if DEBUG
#Preview("Story Card") {
    ZStack {
        Color.black.ignoresSafeArea()
        WorkoutShareCardView(
            log: WorkoutSessionLog(
                sessionId: "s1",
                programId: "체단실 3분할 루틴",
                dayNumber: 1,
                loggedAt: 1_771_982_600,
                durationSeconds: 3720,
                completedExercises: [],
                volumeAnalytics: WorkoutVolumeAnalytics(
                    totalVolumeKg: 3555.0,
                    totalSetsCompleted: 14,
                    totalRepsCompleted: 112,
                    exerciseBreakdown: [
                        ExerciseVolumeAnalytics(
                            exerciseId: "e1",
                            exerciseName: "인클라인 덤벨 프레스",
                            volumeKg: 1420.0,
                            completedSets: 4,
                            completedReps: 36,
                            topSetWeightKg: 34.0,
                            estimated1rmKg: 43.5
                        ),
                        ExerciseVolumeAnalytics(
                            exerciseId: "e2",
                            exerciseName: "딥스 (체중 + 중량)",
                            volumeKg: 1180.0,
                            completedSets: 4,
                            completedReps: 40,
                            topSetWeightKg: 20.0,
                            estimated1rmKg: 32.0
                        ),
                        ExerciseVolumeAnalytics(
                            exerciseId: "e3",
                            exerciseName: "케이블 사이드 레터럴 레이즈",
                            volumeKg: 955.0,
                            completedSets: 6,
                            completedReps: 36,
                            topSetWeightKg: 15.0,
                            estimated1rmKg: 19.5
                        )
                    ]
                )
            ),
            programTitle: "🔥 체단실 PPL 루틴 • Day 1: 푸쉬"
        )
    }
}
#endif
