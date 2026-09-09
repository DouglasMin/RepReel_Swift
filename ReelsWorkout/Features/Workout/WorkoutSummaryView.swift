import ReelsKit
import SwiftUI
import UIKit

/// Enhanced Workout Summary View with:
/// 1. Metric HUD Bento grid (Tonnage, Duration, Sets & Reps)
/// 2. Celebratory spring animation & Particle Confetti burst
/// 3. Instagram Story Share Card modal using ImageRenderer
struct WorkoutSummaryView: View {
    let log: WorkoutSessionLog
    var programTitle: String? = nil
    let onDone: () -> Void

    @State private var celebrationTrigger = false
    @State private var badgeScale: CGFloat = 0.5
    @State private var showStoryCardSheet = false
    @ScaledMetric(relativeTo: .largeTitle) private var volumeFontSize: CGFloat = 44

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        celebrationHeader

                        // 1. Metric HUD Bento Grid
                        metricHUD

                        // 2. Social Share Action Banner
                        storyShareBanner

                        // 3. Exercise Volume Breakdown
                        if let breakdown = log.volumeAnalytics?.exerciseBreakdown, !breakdown.isEmpty {
                            exerciseReportSection(breakdown)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }

                // Done Button
                Button(action: onDone) {
                    Text("완료")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brandPrimary)
                .buttonBorderShape(.capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            // Confetti Overlay Burst
            if celebrationTrigger {
                ConfettiBurstOverlay()
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.success, trigger: celebrationTrigger)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) {
                badgeScale = 1.0
                celebrationTrigger = true
            }
        }
        .sheet(isPresented: $showStoryCardSheet) {
            StoryCardPreviewSheet(log: log, programTitle: programTitle)
        }
    }

    // MARK: - Celebration Header
    private var celebrationHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                // Ambient halo glow
                Circle()
                    .fill(Theme.brandPrimary.opacity(0.3))
                    .frame(width: 90, height: 90)
                    .blur(radius: 20)

                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: Theme.brandPrimary.opacity(0.45), radius: 16, y: 6)

                Image(systemName: "flame.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(badgeScale)

            VStack(spacing: 4) {
                Text("운동 완료!")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.primary)

                Text(volumeText)
                    .font(.system(size: volumeFontSize, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.brandPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                let title = programTitle ?? (log.programId.isEmpty ? nil : log.programId)
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Metric HUD (3-Column Bento Grid)
    private var metricHUD: some View {
        HStack(spacing: 10) {
            hudCell(
                title: "총 볼륨",
                value: volumeText,
                icon: "scalemass.fill",
                tint: Theme.brandPrimary
            )
            hudCell(
                title: "운동 시간",
                value: durationText,
                icon: "clock.fill",
                tint: Theme.brandSecondary
            )
            hudCell(
                title: "완료 세트",
                value: setsText,
                icon: "checkmark.seal.fill",
                tint: Color(hex: "#10B981")
            )
        }
        .padding(.horizontal, 16)
    }

    private func hudCell(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Instagram Story Share Banner
    private var storyShareBanner: some View {
        Button {
            showStoryCardSheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.instagramGradient)
                        .frame(width: 38, height: 38)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("인스타그램 스토리 공유 카드")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("오늘 달성한 톤수와 세트 기록을 이미지로 내보내기")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.brandPrimary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - Exercise Report Section
    private func exerciseReportSection(_ breakdown: [ExerciseVolumeAnalytics]) -> some View {
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

    private var volumeText: String {
        guard let total = log.volumeAnalytics?.totalVolumeKg else { return "—" }
        return "\(total.formatted(.number.precision(.fractionLength(0...1)))) kg"
    }

    private var durationText: String {
        guard let seconds = log.durationSeconds else { return "—" }
        let mins = max(1, seconds / 60)
        return "\(mins)분"
    }

    private var setsText: String {
        guard let analytics = log.volumeAnalytics else { return "—" }
        return "\(analytics.totalSetsCompleted)세트"
    }
}

// MARK: - Story Card Preview Sheet (With ImageRenderer)
private struct StoryCardPreviewSheet: View {
    let log: WorkoutSessionLog
    let programTitle: String?
    @Environment(\.dismiss) private var dismiss

    @State private var renderedImage: UIImage? = nil
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Scaled Preview
                WorkoutShareCardView(log: log, programTitle: programTitle)
                    .scaleEffect(0.72)
                    .frame(width: 360 * 0.72, height: 640 * 0.72)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                    .padding(.top, 10)

                Spacer()

                // Share Buttons
                VStack(spacing: 12) {
                    Button {
                        renderAndShare()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline.weight(.bold))
                            Text("스토리에 공유하기 / 사진 저장")
                                .font(.headline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brandPrimary)
                    .buttonBorderShape(.capsule)

                    Button("닫기") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea())
            .navigationTitle("스토리 카드 공유")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = renderedImage {
                    ShareActivityView(items: [image])
                }
            }
        }
    }

    @MainActor
    private func renderAndShare() {
        let card = WorkoutShareCardView(log: log, programTitle: programTitle)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0 // High-res retina scale for social stories
        if let uiImage = renderer.uiImage {
            self.renderedImage = uiImage
            self.showShareSheet = true
        }
    }
}

// MARK: - UIActivityViewController SwiftUI Bridge
private struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Confetti Particles Overlay
private struct ConfettiBurstOverlay: View {
    @State private var animate = false

    private let particles: [ConfettiItem] = (0..<40).map { _ in
        ConfettiItem(
            color: [Theme.brandPrimary, Theme.brandSecondary, Theme.brandAmber, Theme.brandGreen, Theme.brandTeal].randomElement()!,
            xOffset: Double.random(in: -160...160),
            yOffset: Double.random(in: -280...120),
            rotation: Double.random(in: 0...360),
            scale: Double.random(in: 0.6...1.2)
        )
    }

    var body: some View {
        ZStack {
            ForEach(0..<particles.count, id: \.self) { idx in
                let p = particles[idx]
                RoundedRectangle(cornerRadius: 2)
                    .fill(p.color)
                    .frame(width: 8, height: 14)
                    .scaleEffect(animate ? p.scale : 0.1)
                    .rotationEffect(.degrees(animate ? p.rotation : 0))
                    .offset(x: animate ? p.xOffset : 0, y: animate ? p.yOffset : -40)
                    .opacity(animate ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4)) {
                animate = true
            }
        }
    }
}

private struct ConfettiItem {
    let color: Color
    let xOffset: Double
    let yOffset: Double
    let rotation: Double
    let scale: Double
}

// MARK: - Exercise Volume Card
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
            sessionId: "s1", programId: "체단실 3분할", dayNumber: 1, loggedAt: 1_771_982_600,
            durationSeconds: 3720, completedExercises: [],
            volumeAnalytics: WorkoutVolumeAnalytics(
                totalVolumeKg: 3555.0,
                totalSetsCompleted: 14,
                totalRepsCompleted: 112,
                exerciseBreakdown: [
                    ExerciseVolumeAnalytics(
                        exerciseId: "e1", exerciseName: "인클라인 덤벨 프레스", volumeKg: 1420.0,
                        completedSets: 4, completedReps: 36, topSetWeightKg: 34.0, estimated1rmKg: 43.5
                    )
                ]
            )
        ),
        programTitle: "체단실 PPL 루틴 • Day 1",
        onDone: {}
    )
}
#endif
