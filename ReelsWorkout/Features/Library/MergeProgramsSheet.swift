import ReelsKit
import SwiftUI

struct MergeProgramsSheet: View {
    let store: LibraryStore
    var onMerged: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<String> = []
    @State private var customTitle = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var defaultTitle: String {
        let selected = store.programs.filter { selectedIds.contains($0.programId) }
        if selected.isEmpty {
            return "통합 운동 루틴"
        }
        let creators = Set(selected.compactMap { $0.creator })
        if let creator = creators.first, creators.count == 1 {
            return "\(creator) 통합 시리즈 루틴"
        }
        return "\(selected.first?.title ?? "") 외 \(selected.count - 1)개 통합 루틴"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("여러 개의 릴스로 나누어 저장된 파트별 루틴을 하나의 완성된 다일차(Day 1, Day 2…) 루틴으로 합칩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("병합할 루틴 선택 (최소 2개)") {
                    if store.programs.isEmpty {
                        Text("저장된 루틴이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.programs) { program in
                            Button {
                                toggleSelection(program.programId)
                            } label: {
                                HStack {
                                    Image(systemName: selectedIds.contains(program.programId) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedIds.contains(program.programId) ? Color.accentColor : .secondary)
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(program.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 6) {
                                            if let split = program.splitType {
                                                Text(split.rawValue)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let creator = program.creator {
                                                Text("• \(creator)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("새 루틴 이름") {
                    TextField("통합 루틴 이름 입력", text: $customTitle, prompt: Text(defaultTitle))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("시리즈 루틴 병합")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("병합하기") {
                        Task { await merge() }
                    }
                    .font(.body.weight(.bold))
                    .disabled(selectedIds.count < 2 || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("루틴 병합 중…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func merge() async {
        guard selectedIds.count >= 2 else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let titleToUse = customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultTitle
            : customTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let mergedId = try await store.mergePrograms(
                programIds: Array(selectedIds),
                title: titleToUse
            )
            onMerged?(mergedId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("시리즈 루틴 병합") {
    MergeProgramsSheet(store: LibraryStore(
        client: PreviewFixtures.environment().client,
        jobStore: PreviewFixtures.environment().pendingJobs
    ))
}
#endif
