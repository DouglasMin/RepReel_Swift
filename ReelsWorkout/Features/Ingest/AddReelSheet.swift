import SwiftUI

/// Manual fallback for the share extension — handy in the simulator, where
/// Instagram is not installed.
struct AddReelSheet: View {
    let store: LibraryStore

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var isSubmitting = false

    private var isValid: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isInstagram = trimmed.contains("instagram.com")
        let isYouTube = trimmed.contains("youtube.com") || trimmed.contains("youtu.be")
        return (isInstagram || isYouTube) && URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("영상 링크 (Instagram 릴스 또는 YouTube 쇼츠)") {
                    TextField("https://www.instagram.com/reel/… 또는 https://youtube.com/shorts/…", text: $url, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("영상 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("분석 시작") {
                        isSubmitting = true
                        let targetURL = url
                        dismiss()
                        Task {
                            await store.ingest(url: targetURL)
                        }
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
        }
    }
}

#if DEBUG
#Preview("릴스 추가") {
    let environment = PreviewFixtures.environment()
    return AddReelSheet(
        store: LibraryStore(client: environment.client, jobStore: environment.pendingJobs)
    )
}
#endif
