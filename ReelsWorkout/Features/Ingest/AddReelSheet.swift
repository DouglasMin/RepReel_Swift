import SwiftUI

/// Manual fallback for the share extension — handy in the simulator, where
/// Instagram is not installed.
struct AddReelSheet: View {
    let store: LibraryStore

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var isSubmitting = false

    private var isValid: Bool {
        url.contains("instagram.com") && URL(string: url) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("릴스 URL") {
                    TextField("https://www.instagram.com/reel/…", text: $url, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("릴스 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("분석 시작") {
                        isSubmitting = true
                        Task {
                            await store.ingest(url: url)
                            dismiss()
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
