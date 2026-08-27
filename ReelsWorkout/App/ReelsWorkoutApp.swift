import SwiftUI

@main
struct ReelsWorkoutApp: App {
    private let bootstrap: Result<AppEnvironment, any Error>

    init() {
        #if DEBUG
        // `-demo` runs the whole app against canned responses — no backend needed.
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            bootstrap = .success(PreviewFixtures.environment())
            return
        }
        #endif
        bootstrap = AppEnvironment.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let environment):
                AppRootView()
                    .environment(environment)
            case .failure(let error):
                ConfigurationErrorView(error: error)
            }
        }
    }
}

/// Shown when Config/Secrets.xcconfig has not been filled in. Failing here beats
/// shipping a build that 403s on every request.
struct ConfigurationErrorView: View {
    let error: any Error

    var body: some View {
        ContentUnavailableView {
            Label("설정이 필요합니다", systemImage: "gearshape.badge.checkmark")
        } description: {
            Text(String(describing: error))
        } actions: {
            Text("Config/Secrets.example.xcconfig → Config/Secrets.xcconfig")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
