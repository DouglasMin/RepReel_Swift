import ReelsKit
import SwiftUI

struct EditProgramSheet: View {
    let program: WorkoutProgramResponse
    var onSaved: ((WorkoutProgramResponse) -> Void)? = nil

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var splitType: SplitType?
    @State private var overview: String
    @State private var cycleFrequency: String
    @State private var days: [WorkoutDay]
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(program: WorkoutProgramResponse, onSaved: ((WorkoutProgramResponse) -> Void)? = nil) {
        self.program = program
        self.onSaved = onSaved
        _title = State(initialValue: program.title)
        _splitType = State(initialValue: program.splitType)
        _overview = State(initialValue: program.overview ?? "")
        _cycleFrequency = State(initialValue: program.cycleFrequency ?? "")
        _days = State(initialValue: program.programData.days)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("기본 정보") {
                    TextField("루틴 제목", text: $title)

                    Picker("분할 유형", selection: $splitType) {
                        Text("선택 안 함").tag(nil as SplitType?)
                        ForEach(SplitType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type as SplitType?)
                        }
                    }

                    TextField("주기 / 빈도 (예: 주 3회)", text: $cycleFrequency)
                }

                Section("루틴 설명") {
                    TextField("루틴에 대한 간단한 설명이나 목표를 입력하세요", text: $overview, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("일차별 제목") {
                    ForEach(days.indices, id: \.self) { idx in
                        HStack {
                            Text("Day \(days[idx].dayNumber)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 45, alignment: .leading)
                            TextField("Day 제목", text: $days[idx].dayTitle)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("루틴 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        Task { await save() }
                    }
                    .font(.body.weight(.bold))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("저장 중…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func save() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        var updatedProgramData = program.programData
        updatedProgramData.title = title
        updatedProgramData.splitType = splitType
        updatedProgramData.overview = overview.isEmpty ? nil : overview
        updatedProgramData.cycleFrequency = cycleFrequency.isEmpty ? nil : cycleFrequency
        updatedProgramData.days = days

        do {
            let updated = try await environment.client.updateProgram(
                id: program.programId,
                program: updatedProgramData
            )
            onSaved?(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
