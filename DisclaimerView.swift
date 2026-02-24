import SwiftUI

struct DisclaimerView: View {
    @AppStorage("hasAcceptedDisclaimer") var hasAcceptedDisclaimer: Bool = false
    @State private var isAccepted = false
    @State private var isCompleting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                StaticDisclaimerBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppDesign.accent.opacity(0.95), Color.blue.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 6)

                            ZStack {
                                Circle()
                                    .fill(AppDesign.accent.opacity(0.12))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "cross.case.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(AppDesign.accent)
                            }

                            Text("Medical Disclaimer")
                                .font(.largeTitle.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("AI wellness insights, not medical diagnosis.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 8) {
                                disclaimerPoint("Not a substitute for doctor advice")
                                disclaimerPoint("Recommendations are informational only")
                                disclaimerPoint("Consult a physician before supplements")
                            }
                        }

                        DisclaimerConsentRow(isOn: $isAccepted)
                            .onChange(of: isAccepted) { _, _ in
                                AppHaptics.subtle()
                            }

                        Button {
                            withAnimation(reduceMotion ? .easeInOut(duration: AppMotion.fast) : AppMotion.spring) {
                                isCompleting = true
                            }
                            let delay = reduceMotion ? AppMotion.fast : AppMotion.medium
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                hasAcceptedDisclaimer = true
                            }
                            AppHaptics.subtle()
                        } label: {
                            Text("Get Started")
                                .font(.headline.weight(.semibold))
                                .appPrimaryButtonSurface(disabled: !isAccepted)
                        }
                        .disabled(!isAccepted)
                        .accessibilityLabel("Get Started")
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppDesign.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppDesign.cardRadius, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                            .allowsHitTesting(false)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                    .padding(.horizontal, AppDesign.contentPadding)
                    .padding(.top, 18)
                }

                if isCompleting {
                    Color.white.opacity(0.18)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .blur(radius: 12)
                        .opacity(0.22)
                        .transition(.opacity)
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.large)
        }
        .interactiveDismissDisabled(true)
    }

    private func disclaimerPoint(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppDesign.accent)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary.opacity(0.9))
        }
    }
}

private struct DisclaimerConsentRow: View {
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? AppDesign.accent : .secondary)
                Text("Consent")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(isOn ? "Accepted" : "Required")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOn ? AppDesign.accent : .secondary)
            }

            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I accept the Terms and Privacy Policy")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Required to continue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(AppDesign.accent)
        }
        .accessibilityLabel("Accept disclaimer")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint("Double tap to toggle")
    }
}

private struct StaticDisclaimerBackground: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [AppDesign.bgTop, AppDesign.bgBottom],
                center: .topLeading,
                startRadius: 60,
                endRadius: 1000
            )
            .ignoresSafeArea()

            NoiseOverlayView()
                .blendMode(.overlay)
                .opacity(0.03)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}
