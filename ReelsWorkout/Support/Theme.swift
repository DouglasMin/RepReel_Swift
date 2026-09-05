import SwiftUI

public enum Theme {
    // MARK: - Brand Colors
    public static let brandPrimary = Color(hex: "#FF5A36") // Vibrant Coral Flame
    public static let brandSecondary = Color(hex: "#FF2A6D") // Neon Crimson
    public static let brandPurple = Color(hex: "#7C3AED") // Electric Violet
    public static let brandTeal = Color(hex: "#06B6D4") // Cyan Accent
    public static let brandGreen = Color(hex: "#10B981") // Success / Completed Set Green
    public static let brandAmber = Color(hex: "#F59E0B") // Radiant Gold / Amber
    public static let brandBlue = Color(hex: "#2563EB") // Royal Cobalt

    // MARK: - Social Platform Accents
    public static let instagramGradient = LinearGradient(
        colors: [Color(hex: "#F58529"), Color(hex: "#DD2A7B"), Color(hex: "#8134AF"), Color(hex: "#515BD4")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let youtubeRed = Color(hex: "#FF0000")

    // MARK: - Muscle & Category Accents
    public static let chestColor = Color(hex: "#FF5A36")
    public static let backColor = Color(hex: "#06B6D4")
    public static let legsColor = Color(hex: "#F59E0B")
    public static let shouldersColor = Color(hex: "#8B5CF6")
    public static let armsColor = Color(hex: "#EC4899")
    public static let coreColor = Color(hex: "#10B981")

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
        colors: [brandPrimary.opacity(0.15), Color.clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static func splitGradient(for split: String?) -> LinearGradient {
        guard let split = split?.lowercased() else {
            return LinearGradient(colors: [brandPrimary, brandSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if split.contains("ppl") || split.contains("3분할") {
            return LinearGradient(colors: [Color(hex: "#FF5A36"), Color(hex: "#FF2A6D")], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if split.contains("upper") || split.contains("상하체") || split.contains("2분할") {
            return LinearGradient(colors: [Color(hex: "#8B5CF6"), Color(hex: "#3B82F6")], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if split.contains("bro") || split.contains("5분할") || split.contains("부위별") {
            return LinearGradient(colors: [Color(hex: "#EC4899"), Color(hex: "#7C3AED")], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if split.contains("full") || split.contains("무분할") {
            return LinearGradient(colors: [Color(hex: "#10B981"), Color(hex: "#06B6D4")], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [Color(hex: "#06B6D4"), Color(hex: "#3B82F6")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: - Semantic Card Backgrounds
    public static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    public static let subcardBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    public static let listBackground = Color(uiColor: .systemGroupedBackground)
}

// MARK: - View Modifiers for Native & Premium Cards

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

public struct PremiumCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var glowColor: Color = Theme.brandPrimary

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [glowColor.opacity(0.35), glowColor.opacity(0.08), Color.primary.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: glowColor.opacity(0.06), radius: 10, y: 4)
                    .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
            )
    }
}

public extension View {
    func nativeCard(cornerRadius: CGFloat = 16, highlight: Bool = false) -> some View {
        modifier(NativeCardModifier(cornerRadius: cornerRadius, highlight: highlight))
    }

    func premiumCard(cornerRadius: CGFloat = 18, glowColor: Color = Theme.brandPrimary) -> some View {
        modifier(PremiumCardModifier(cornerRadius: cornerRadius, glowColor: glowColor))
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
