import ReelsKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: LibraryStore?
    @State private var isAddingReel = false
    @State private var isMergingPrograms = false
    @State private var programToDelete: ProgramSummary?
    @State private var path: [String] = []

    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let store {
                    content(store)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("내 릴스 루틴")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.medium))
                        }
                        .accessibilityLabel("설정 및 프로필")

                        if let store, store.programs.count >= 2 {
                            Button {
                                isMergingPrograms = true
                            } label: {
                                Image(systemName: "arrow.triangle.merge")
                                    .font(.body.weight(.medium))
                            }
                            .accessibilityLabel("시리즈 병합")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingReel = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("릴스 추가")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsSheet()
            }
            .sheet(isPresented: $isAddingReel) {
                if let store { AddReelSheet(store: store) }
            }
            .sheet(isPresented: $isMergingPrograms) {
                if let store {
                    MergeProgramsSheet(store: store) { mergedId in
                        path.append(mergedId)
                    }
                }
            }
        }
        .task {
            if store == nil {
                store = LibraryStore(client: environment.client, jobStore: environment.pendingJobs)
            }
            await store?.refresh()
            #if DEBUG
            if let programId = Self.demoDetailProgramId, path.isEmpty {
                path.append(programId)
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store?.reloadPendingJobs()
            }
        }
    }

    #if DEBUG
    private static var demoDetailProgramId: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demo-detail"),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    #endif

    @ViewBuilder
    private func content(_ store: LibraryStore) -> some View {
        List {
            // Header Stats Banner
            if !store.programs.isEmpty {
                Section {
                    HeroHeaderCard(programCount: store.programs.count)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            // Pending Jobs Section
            if !store.pending.isEmpty {
                Section {
                    ForEach(store.pending) { job in
                        PendingJobCard(job: job) { store.dismissPendingJob(job) }
                    }
                } header: {
                    Label("AI 분석 진행 중", systemImage: "sparkles")
                        .foregroundStyle(Theme.brandPrimary)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            // Saved Programs Section
            Section {
                if store.isLoading && store.programs.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        ProgramCardSkeleton()
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                } else if store.programs.isEmpty {
                    ContentUnavailableView {
                        Label("저장된 루틴이 없습니다", systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("인스타그램 릴스에서 공유 → 릴스 루틴을 선택하거나,\n상단 '+ 릴스 추가' 버튼을 눌러 시작하세요.")
                    } actions: {
                        Button {
                            isAddingReel = true
                        } label: {
                            Text("릴스 링크 추가하기")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.brandPrimary)
                    }
                    .padding(.vertical, 32)
                }

                ForEach(store.programs) { program in
                    NavigationLink(value: program.programId) {
                        ProgramCard(program: program)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("삭제", role: .destructive) {
                            programToDelete = program
                        }
                    }
                }
            } header: {
                if !store.programs.isEmpty {
                    Text("보관함 (\(store.programs.count))")
                }
            }
        }
        .listStyle(.plain)
        .background(Theme.listBackground)
        .safeAreaInset(edge: .bottom) {
            if environment.workout != nil {
                Color.clear.frame(height: 64)
            }
        }
        .refreshable { await store.refresh() }
        .navigationDestination(for: String.self) { programId in
            ProgramDetailView(
                programId: programId,
                onUpdated: { updated in
                    store.updateProgramSummary(from: updated)
                },
                onDeleted: {
                    store.removeProgram(id: programId)
                }
            )
        }
        .confirmationDialog(
            "루틴 삭제",
            isPresented: .init(
                get: { programToDelete != nil },
                set: { if !$0 { programToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("루틴 삭제", role: .destructive) {
                if let p = programToDelete {
                    Task { await store.deleteProgram(id: p.programId) }
                }
                programToDelete = nil
            }
            Button("취소", role: .cancel) { programToDelete = nil }
        } message: {
            Text("'\(programToDelete?.title ?? "루틴")'을(를) 삭제하시겠습니까?\n삭제된 루틴은 복구할 수 없습니다.")
        }
        .alert(
            "오류",
            isPresented: .init(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

// MARK: - Components

private struct HeroHeaderCard: View {
    let programCount: Int

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Ambient glow in corner
            Circle()
                .fill(Theme.brandGradient)
                .frame(width: 140, height: 140)
                .blur(radius: 40)
                .opacity(0.18)
                .offset(x: 30, y: 30)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.brandPrimary)
                        Text("AI REELS & SHORTS")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.brandPrimary)
                            .tracking(1.2)
                    }

                    Text("맞춤 릴스 워크아웃")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.primary)

                    Text("인스타그램과 유튜브에서 추출된 \(programCount)개의 루틴")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(spacing: 2) {
                    Text("\(programCount)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.brandPrimary)
                        .monospacedDigit()
                    Text("루틴 보관")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.subcardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.brandPrimary.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Theme.brandPrimary.opacity(0.4), Color.primary.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: Theme.brandPrimary.opacity(0.08), radius: 12, y: 4)
                .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
        )
    }
}

private struct PendingJobCard: View {
    let job: PendingJob
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 44, height: 44)
                    .shadow(color: Theme.brandPrimary.opacity(0.4), radius: 8, y: 2)

                Image(systemName: "sparkles")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            .shimmering()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("AI 운동 루틴 추출 중…")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.brandPrimary)
                }

                Text(job.reelURL)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary.opacity(0.6))
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.brandPrimary.opacity(0.35), lineWidth: 1.2)
                )
                .shadow(color: Theme.brandPrimary.opacity(0.10), radius: 10, y: 3)
        )
    }
}

private struct ProgramCard: View {
    let program: ProgramSummary

    private var splitColor: Color {
        guard let split = program.splitType else { return Theme.brandPrimary }
        switch split {
        case .ppl: return Theme.brandPrimary
        case .upperLower: return Color(hex: "#8B5CF6")
        case .broSplit: return Color(hex: "#EC4899")
        case .fullBody: return Color(hex: "#10B981")
        case .custom: return Color(hex: "#06B6D4")
        }
    }

    private var splitIcon: String {
        guard let split = program.splitType else { return "figure.strengthtraining.traditional" }
        switch split {
        case .ppl: return "flame.fill"
        case .upperLower: return "figure.cross.training"
        case .broSplit: return "figure.arms.open"
        case .fullBody: return "figure.strengthtraining.traditional"
        case .custom: return "bolt.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Media Cover Artwork Tile
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.splitGradient(for: program.splitType?.rawValue))
                    .frame(width: 52, height: 52)
                    .shadow(color: splitColor.opacity(0.3), radius: 6, y: 2)

                Image(systemName: splitIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(program.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if let split = program.splitType {
                        Text(split.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(splitColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(splitColor.opacity(0.12), in: .capsule)
                    }

                    if let creator = program.creator, !creator.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(creator)
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .padding(14)
        .premiumCard(glowColor: splitColor)
    }
}

#if DEBUG
#Preview("라이브러리") {
    LibraryView()
        .environment(PreviewFixtures.environment())
}
#endif
