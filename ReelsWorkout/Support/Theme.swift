import SwiftUI

public enum Theme {
    // MARK: - Brand Colors
    public static let brandPrimary = Color(hex: "#FF5A36") // Vibrant Coral Flame
    public static let brandSecondary = Color(hex: "#FF2A6D") // Neon Crimson
    public static let brandPurple = Color(hex: "#7C3AED") // Electric Violet
    public static let brandTeal = Color(hex: "#06B6D4") // Cyan Accent
    public static let brandGreen = Color(hex: "#10B981") // Success / Completed Set Green

    // MARK: - Gradients
    public static let brandGradient = LinearGradient(
        colors: [brandPrimary, brandSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let heroGradient = LinearGradient(
        colors: [brandPrimary.opacity(0.18), brandPurple.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let cardHighlightGradient = LinearGradient(
        colors: [brandPrimary.opacity(0.12), Color.clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic Card Backgrounds
    public static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    public static let subcardBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    public static let listBackground = Color(uiColor: .systemGroupedBackground)
}

// MARK: - View Modifiers for Native Cards

public struct NativeCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var highlight: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(highlight ? Theme.brandPrimary.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            )
    }
}

public extension View {
    func nativeCard(cornerRadius: CGFloat = 16, highlight: Bool = false) -> some View {
        modifier(NativeCardModifier(cornerRadius: cornerRadius, highlight: highlight))
    }
}

// MARK: - Shimmer Skeleton Loading

public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: Color.white.opacity(0.25), location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .scaleEffect(2.5)
                        .offset(x: (phase - 0.5) * geo.size.width * 2)
                    }
                )
                .mask(content)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

public extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

public struct ProgramCardSkeleton: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 80, height: 18)
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 50, height: 16)
            }

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 60, height: 20)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 70, height: 20)
                Spacer()
            }
        }
        .padding(16)
        .nativeCard()
        .shimmering()
    }
}
