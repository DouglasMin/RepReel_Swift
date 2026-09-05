import AuthenticationServices
import ReelsKit
import SwiftUI

/// Apple HIG-compliant onboarding and Sign in with Apple screen.
struct SignInView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Brand Hero
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.brandPrimary, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: Theme.brandPrimary.opacity(0.35), radius: 16, y: 8)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text("RepReel")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("인스타그램 릴스로 완성하는 나만의 맞춤 운동")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 32)

            // Key Feature Bullets
            VStack(spacing: 20) {
                featureRow(
                    icon: "sparkles.rectangle.stack.fill",
                    color: .purple,
                    title: "릴스 루틴 원탭 변환",
                    description: "인스타그램 공유하기로 루틴을 추출해 내 보관함에 저장합니다."
                )

                featureRow(
                    icon: "timer",
                    color: .orange,
                    title: "스마트 세트 & 휴식 타이머",
                    description: "자동 중량 계승과 소리/진동 알림으로 운동에만 집중하세요."
                )

                featureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    color: .green,
                    title: "주간 볼륨 및 스트릭 분석",
                    description: "매주 총 톤수와 연속 운동 기록으로 성장을 시각화합니다."
                )
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 32)

            // Auth Buttons & Disclaimers
            VStack(spacing: 14) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

                #if DEBUG
                Button {
                    environment.signIn(
                        userIdentifier: "demo_user_123",
                        email: "demo@repreel.app",
                        fullName: "데모 사용자"
                    )
                } label: {
                    Text("데모 모드로 둘러보기")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                #endif

                // Health & Safety Disclaimer (Apple Guideline 1.4.1)
                Text("RepReel의 운동 가이드는 일반적인 피트니스 참고 정보입니다.\n본인의 신체 상태에 맞게 안전하게 운동하세요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Theme.listBackground.ignoresSafeArea())
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let userIdentifier = appleIDCredential.user
                let email = appleIDCredential.email
                let fullName = [
                    appleIDCredential.fullName?.familyName,
                    appleIDCredential.fullName?.givenName
                ].compactMap { $0 }.joined(separator: " ")

                environment.signIn(
                    userIdentifier: userIdentifier,
                    email: email,
                    fullName: fullName.isEmpty ? nil : fullName
                )
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            #if DEBUG
            if nsError.code == 1000 {
                errorMessage = "💡 시뮬레이터 환경에서는 Apple 계정/인증서 미설정으로 오류(1000)가 발생할 수 있습니다. 아래 [데모 모드로 둘러보기]를 탭하여 바로 체험해보세요!"
                return
            }
            #endif
            errorMessage = "로그인 중 오류가 발생했습니다: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
#Preview("Sign In View") {
    SignInView()
        .environment(PreviewFixtures.environment())
}
#endif
