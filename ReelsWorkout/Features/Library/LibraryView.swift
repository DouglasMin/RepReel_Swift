import ReelsKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: LibraryStore?
    @State private var isAddingReel = false
    @State private var path: [String] = []

    var body: some View {
        ZStack {
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
                ToolbarItem(placement: .primaryAction) {
                    Button("릴스 추가", systemImage: "plus") { isAddingReel = true }
                }
            }
            .sheet(isPresented: $isAddingReel) {
                if let store { AddReelSheet(store: store) }
            }
        }
            if let workout = environment.workout {
                WorkoutContainer(isPresented: .constant(true)) {
                    WorkoutBar(store: workout)
                } expanded: {
                    WorkoutSessionView(
                        store: workout,
                        onFinish: { Task { await finish(workout) } },
                        onDiscard: {
                            Task {
                                await workout.discard()
                                environment.endWorkout()
                            }
                        }
                    )
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0), value: environment.workout == nil)
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
            // The share extension writes while the app is backgrounded.
            if phase == .active {
                store?.reloadPendingJobs()
                Task { await environment.restoreWorkoutIfNeeded() }
            }
        }
    }

    private func finish(_ workout: WorkoutSessionStore) async {
        await workout.flushPendingSave()
        await workout.finish(notes: nil)
    }

    #if DEBUG
    /// `-demo-detail <program_id>` opens straight into that program, so deep
    /// screens can be screenshotted from the command line.
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
            if !store.pending.isEmpty {
                Section("분석 중인 릴스") {
                    ForEach(store.pending) { job in
                        PendingJobRow(job: job) { store.dismissPendingJob(job) }
                    }
                }
            }

            Section("저장된 운동 프로그램") {
                if store.programs.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "아직 루틴이 없습니다",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("인스타그램 릴스에서 공유 → 릴스 루틴을 눌러 시작하세요.")
                    )
                }
                ForEach(store.programs) { program in
                    NavigationLink(value: program.programId) {
                        ProgramSummaryRow(program: program)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.refresh() }
        .navigationDestination(for: String.self) { programId in
            ProgramDetailView(programId: programId)
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

private struct PendingJobRow: View {
    let job: PendingJob
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("AI가 운동 루틴을 분석하고 있습니다…")
                    .font(.subheadline)
                Text(job.reelURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .swipeActions {
            Button("취소", role: .destructive, action: onDismiss)
        }
    }
}

private struct ProgramSummaryRow: View {
    let program: ProgramSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(program.title)
                .font(.headline)
            HStack(spacing: 8) {
                if let splitType = program.splitType {
                    Text(splitType.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.15), in: .capsule)
                }
                if let creator = program.creator {
                    Text(creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview("라이브러리") {
    LibraryView()
        .environment(PreviewFixtures.environment())
}

#Preview("빈 상태") {
    LibraryView()
        .environment(PreviewFixtures.environment(withPendingJob: false))
}
#endif
