import ReelsKit
import SwiftUI

/// Top-level container hosting the main TabView and the floating active workout container.
struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0

    var body: some View {
        Group {
            if environment.isSignedIn {
                mainContent
            } else {
                SignInView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: environment.isSignedIn)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await environment.checkAppleCredentialState()
                    await environment.restoreWorkoutIfNeeded()
                }
            }
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                LibraryView()
                    .tabItem {
                        Label("내 루틴", systemImage: "figure.strengthtraining.traditional")
                    }
                    .tag(0)

                HistoryView()
                    .tabItem {
                        Label("운동 기록", systemImage: "chart.bar.fill")
                    }
                    .tag(1)
            }
            .tint(Theme.brandPrimary)

            if let workout = environment.workout {
                WorkoutContainer(isPresented: .constant(true), initiallyExpanded: environment.isWorkoutExpanded) {
                    WorkoutBar(store: workout)
                } expanded: {
                    Group {
                        if case .finished(let log) = workout.finishState {
                            WorkoutSummaryView(log: log, programTitle: workout.draft.dayTitle) { environment.endWorkout() }
                        } else {
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
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: isFinished(workout))
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0), value: environment.workout == nil)
    }

    private func isFinished(_ workout: WorkoutSessionStore) -> Bool {
        if case .finished = workout.finishState { return true }
        return false
    }

    private func finish(_ workout: WorkoutSessionStore) async {
        await workout.flushPendingSave()
        await workout.finish(notes: nil)
    }
}

#if DEBUG
#Preview("앱 메인 루트") {
    AppRootView()
        .environment(PreviewFixtures.environment())
}
#endif
