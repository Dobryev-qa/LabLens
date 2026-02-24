import SwiftUI
import UIKit

enum AppDesign {
    static let accent = Color(hex: "#1FD1B0")
    static let accentDeep = Color(hex: "#11B89A")
    static let bgTop = Color(hex: "#CDEEE7")
    static let bgBottom = Color(hex: "#BFD9FF")
    static let error = Color.red
    static let warning = Color(hex: "#F59E0B")
    static let success = Color.green

    static let cardRadius: CGFloat = 24
    static let buttonRadius: CGFloat = 18
    static let bottomBarRadius: CGFloat = 32
    static let contentPadding: CGFloat = 20
}

enum AppMotion {
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let fast = 0.15
    static let medium = 0.25
    static let slow = 0.4
}

enum AppHaptics {
    static func subtle() {
        #if targetEnvironment(simulator)
        return
        #else
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        #endif
    }
}

struct AppBackgroundView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatePhase = false

    var body: some View {
        ZStack {
            if #available(iOS 26.0, *), !reduceMotion {
                ZStack {
                    RadialGradient(
                        colors: [AppDesign.bgTop, AppDesign.bgBottom],
                        center: animatePhase ? .bottomTrailing : .topLeading,
                        startRadius: 40,
                        endRadius: 980
                    )
                    .animation(.linear(duration: 15).repeatForever(autoreverses: true), value: animatePhase)
                    .allowsHitTesting(false)

                    RadialGradient(
                        colors: [
                            AppDesign.accent.opacity(0.12),
                            .clear
                        ],
                        center: animatePhase ? .topLeading : .bottomTrailing,
                        startRadius: 20,
                        endRadius: 600
                    )
                    .blendMode(.plusLighter)
                    .animation(.linear(duration: 15).repeatForever(autoreverses: true), value: animatePhase)
                    .allowsHitTesting(false)
                }
                .onAppear { animatePhase = true }
            } else {
                RadialGradient(
                    colors: [AppDesign.bgTop, AppDesign.bgBottom],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 980
                )
                .allowsHitTesting(false)
            }

            NoiseOverlayView()
                .blendMode(.overlay)
                .opacity(0.03)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

struct NoiseOverlayView: View {
    var body: some View {
        Canvas { context, size in
            let count = 1400
            for i in 0..<count {
                let x = pseudoRandom(i, prime: 73856093) * size.width
                let y = pseudoRandom(i, prime: 19349663) * size.height
                let rect = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(0.65))
                )
            }
        }
    }

    private func pseudoRandom(_ value: Int, prime: Int) -> CGFloat {
        let n = (value &* prime) ^ (value << 13)
        let hash = (n &* (n &* n &* 15731 &+ 789221) &+ 1376312589) & 0x7fffffff
        return CGFloat(hash % 10_000) / 10_000
    }
}

extension View {
    @ViewBuilder
    func appLayeredShadow() -> some View {
        if #available(iOS 26.0, *) {
            shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        } else {
            shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 5)
                .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
    }

    func appGlassCard(cornerRadius: CGFloat = AppDesign.cardRadius) -> some View {
        self
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.80))
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(.ultraThinMaterial.opacity(0.35))
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(({
                        if #available(iOS 26.0, *) { return Color.white.opacity(0.2) }
                        return Color.white.opacity(0.42)
                    })(), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .overlay(
                Group {
                    if #available(iOS 26.0, *) {
                        LinearGradient(
                            colors: [.white.opacity(0.16), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .allowsHitTesting(false)
                    }
                }
            )
            .modifier(PlatformCardSheen(cornerRadius: cornerRadius))
            .appLayeredShadow()
    }

    func glassCard(cornerRadius: CGFloat = AppDesign.cardRadius) -> some View {
        appGlassCard(cornerRadius: cornerRadius)
    }

    func appPrimaryButtonSurface(disabled: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppDesign.buttonRadius, style: .continuous)
        return self
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        AppDesign.accent.opacity(disabled ? 0.45 : 0.95),
                        AppDesign.accentDeep.opacity(disabled ? 0.35 : 0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: shape
            )
            // Shine/highlight animation intentionally disabled for the disclaimer CTA.
            .clipShape(shape)
            .foregroundStyle(.white)
            .animation(nil, value: disabled)
    }

    func appSectionCard(title: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            self
        }
        .padding({
            if #available(iOS 26.0, *) { return 16.0 }
            return 14.0
        }())
        .glassCard(cornerRadius: 20)
    }

    @ViewBuilder
    private func `if`<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    private func ifAvailableiOS26<Transformed: View>(transform: (Self) -> Transformed) -> some View {
        if #available(iOS 26.0, *) {
            transform(self)
        } else {
            self
        }
    }
}

private struct PlatformCardSheen: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                if #available(iOS 26.0, *), !reduceMotion {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.14), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .offset(x: phase ? 170 : -170)
                    .animation(.linear(duration: 5.5).repeatForever(autoreverses: false), value: phase)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                    .onAppear { phase = true }
                }
            }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
