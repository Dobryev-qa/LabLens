import SwiftUI

struct PaywallView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Premium", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppDesign.accent)
                    Text("Unlock Your Full Health Potential")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Designed for long-term health tracking with deeper AI context.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .appSectionCard()

                VStack(alignment: .leading, spacing: 12) {
                    featureRow("Unlimited PDF Scans")
                    featureRow("Deep AI Interpretations")
                    featureRow("Lifetime History")
                }
                .appSectionCard()

                Button {
                    // Placeholder billing action
                } label: {
                    Text("Start First Free Scan")
                        .font(.headline.weight(.semibold))
                        .appPrimaryButtonSurface()
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(AppDesign.contentPadding)
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.mint)
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}
