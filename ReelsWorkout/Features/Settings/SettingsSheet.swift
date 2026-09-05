import AuthenticationServices
import ReelsKit
import SwiftUI

/// Profile & Settings sheet providing Apple account status, Health Disclaimer, and Sign Out.
struct SettingsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // User Profile Section
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Theme.brandPrimary.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Theme.brandPrimary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let name = environment.userFullName, !name.isEmpty {
                                Text(name)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.primary)
                            }

                            Text(environment.userEmail ?? "Apple ID 계정")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("내 계정")
                }

                // Health & Fitness Disclaimer (Guideline 1.4.1)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(.red)
                            Text("건강 및 안전 유의사항")
                                .font(.subheadline.weight(.bold))
                        }

                        Text("RepReel에서 제공하는 운동 가이드 및 추천 루틴은 일반적인 피트니스 참고 정보입니다. 개인의 건강 및 신체 상태에 맞추어 적절한 중량과 강도로 진행하시기 바라며, 통증이나 부상 위험이 있을 경우 즉시 중단하고 전문의와 상담하세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("안전 안내")
                }

                // Legal & Policy (Guideline 5.1.1)
                Section {
                    Link(destination: URL(string: "https://repreel.app/privacy")!) {
                        HStack {
                            Label("개인정보 처리방침", systemImage: "hand.raised.fill")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Link(destination: URL(string: "https://repreel.app/terms")!) {
                        HStack {
                            Label("서비스 이용약관", systemImage: "doc.text.fill")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("약관 및 정책")
                }

                // App Info & Sign Out
                Section {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("로그아웃")
                                .font(.body.weight(.semibold))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .confirmationDialog(
                "로그아웃",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("로그아웃", role: .destructive) {
                    environment.signOut()
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("로그아웃 시 현재 진행 중인 운동 상태가 초기화됩니다.")
            }
        }
    }
}

#if DEBUG
#Preview("Settings Sheet") {
    SettingsSheet()
        .environment(PreviewFixtures.environment())
}
#endif
