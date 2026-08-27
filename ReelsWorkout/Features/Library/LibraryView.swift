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
                    if let store, store.programs.count >= 2 {
                        Button {
                            isMergingPrograms = true
                        } label: {
                            Label("시리즈 병합", systemImage: "arrow.triangle.merge")
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("맞춤 릴스 워크아웃")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Text("인스타그램에서 추출된 \(programCount)개의 루틴")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.brandGradient)
                Text("\(programCount)개 보관")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.brandPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.brandPrimary.opacity(0.12), in: .capsule)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.brandPrimary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        )
    }
}

private struct PendingJobCard: View {
    let job: PendingJob
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 42, height: 42)
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .shimmering()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("AI 루틴 추출 중…")
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.brandPrimary.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Theme.brandPrimary.opacity(0.06), radius: 8, y: 3)
        )
    }
}

private struct ProgramCard: View {
    let program: ProgramSummary

    private var splitColor: Color {
        guard let split = program.splitType else { return Theme.brandPrimary }
        switch split {
        case .ppl: return Theme.brandPrimary
        case .upperLower: return Color.blue
        case .broSplit: return Theme.brandPurple
        case .fullBody: return Theme.brandGreen
        case .custom: return Theme.brandTeal
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Instagram / Workout Avatar Badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.pink, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)

                Circle()
                    .fill(Theme.cardBackground)
                    .frame(width: 42, height: 42)

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(program.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let split = program.splitType {
                        Text(split.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(splitColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(splitColor.opacity(0.12), in: .capsule)
                    }

                    if let creator = program.creator, !creator.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 9))
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(14)
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
}

#if DEBUG
#Preview("라이브러리") {
    LibraryView()
        .environment(PreviewFixtures.environment())
}
#endif
