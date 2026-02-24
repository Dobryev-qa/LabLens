import SwiftUI
import UIKit

struct ScanView: View {
    let result: AIAnalysisResult?
    let isBusy: Bool
    let canRetryLastInput: Bool
    let cachedRetryUses: Int
    let onStartScan: () -> Void
    let onRescan: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAllRecommendations = false

    private var hasResult: Bool { result != nil }

    private var hasUsableResult: Bool {
        guard let result else { return false }
        return !result.biomarkers.isEmpty || !result.recommendations.isEmpty
    }

    private var isFailureState: Bool {
        guard let result else { return false }
        let summary = result.summary.lowercased()
        return summary.contains("could not be completed")
            || summary.contains("backend is unreachable")
            || summary.contains("unauthorized")
            || summary.contains("forbidden")
            || summary.contains("not configured")
            || summary.contains("network is unavailable")
    }

    private var primaryButtonTitle: String {
        if isFailureState {
            if canRetryLastInput && cachedRetryUses == 0 {
                return "Retry Scan"
            }
            return "Retry Another Scan"
        }
        if hasUsableResult { return "Scan Another Report" }
        return "Scan Report"
    }

    private var primaryButtonIcon: String {
        if isFailureState { return "arrow.clockwise.circle" }
        if hasUsableResult { return "doc.viewfinder" }
        return "camera.viewfinder"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                ScanHeroCard(
                    isBusy: isBusy,
                    hasResult: hasResult,
                    isFailureState: isFailureState,
                    resultSummary: result?.summary,
                    primaryButtonTitle: primaryButtonTitle,
                    primaryButtonIcon: primaryButtonIcon,
                    action: { hasResult ? onRescan() : onStartScan() }
                )

                if let result {
                    if isFailureState {
                        ScanResultOverviewCard(
                            result: result,
                            isBusy: isBusy
                        )
                    } else {
                        ScanResultOverviewCard(
                            result: result,
                            isBusy: isBusy
                        )

                        ScanSummaryCard(summary: result.summary)

                        if result.biomarkers.isEmpty && result.recommendations.isEmpty {
                            ScanNoDataCard(
                                summary: result.summary,
                                isBusy: isBusy,
                                onRetry: onRescan
                            )
                        } else {
                            if !result.recommendations.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    sectionHeader("Recommendations", subtitle: "\(result.recommendations.count) actions")
                                    ForEach(Array(result.recommendations.prefix(showAllRecommendations ? result.recommendations.count : 2))) { recommendation in
                                        ProductRecommendationCard(item: recommendation)
                                    }

                                    if result.recommendations.count > 2 {
                                        Button {
                                            showAllRecommendations.toggle()
                                        } label: {
                                            Label(
                                                showAllRecommendations ? "Show Less Recommendations" : "Show All Recommendations",
                                                systemImage: showAllRecommendations ? "chevron.up" : "chevron.down"
                                            )
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 14)
                                            .frame(height: 44)
                                            .frame(maxWidth: .infinity)
                                            .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(.white.opacity(0.35), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .appSectionCard()
                            }

                            if !result.biomarkers.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    sectionHeader("Biomarkers", subtitle: "\(result.biomarkers.count) extracted")
                                    ForEach(result.biomarkers) { biomarker in
                                        BiomarkerTile(item: biomarker)
                                    }
                                }
                                .appSectionCard()
                            }
                        }

                        Text(result.disclaimer)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                            .padding(.top, 2)
                    }
                } else {
                    ScanHowItWorksCard()
                }
            }
            .padding(AppDesign.contentPadding)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 4)
        .animation(reduceMotion ? .easeInOut(duration: AppMotion.fast) : AppMotion.spring, value: result?.summary ?? "")
        .onChange(of: result?.summary ?? "") { _, _ in
            showAllRecommendations = false
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScanSummaryCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppDesign.accent)
                Text("Summary")
                    .font(.headline.weight(.semibold))
            }

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSectionCard()
    }
}

private struct ScanHeroCard: View {
    let isBusy: Bool
    let hasResult: Bool
    let isFailureState: Bool
    let resultSummary: String?
    let primaryButtonTitle: String
    let primaryButtonIcon: String
    let action: () -> Void

    private var badgeTitle: String {
        if isBusy && hasResult { return "Processing" }
        if isFailureState { return "Needs Retry" }
        if hasResult { return "Result Ready" }
        return "Ready to Scan"
    }

    private var badgeColor: Color {
        if isBusy && hasResult { return AppDesign.accent }
        if isFailureState { return AppDesign.warning }
        if hasResult { return AppDesign.success }
        return .blue
    }

    private var headline: String {
        if isBusy && hasResult { return "Scanning in progress" }
        if isFailureState { return "Scan needs retry" }
        if hasResult { return "Result ready" }
        return "Scan your lab report"
    }

    private var bodyText: String {
        if isBusy && hasResult {
            return "Keep the app open while pages are rendered and analyzed."
        }
        if isFailureState {
            return resultSummary ?? "The report was rendered, but analysis did not complete. Retry when backend is available."
        }
        if hasResult {
            return "Review extracted biomarkers and recommendations below, or run another scan."
        }
        return "Import a PDF or take a photo. The app extracts biomarkers and returns a structured summary."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(badgeColor.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: isFailureState ? "exclamationmark.triangle" : (hasResult ? "checkmark.seal" : "doc.viewfinder"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(badgeColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.title3.weight(.bold))
                    Text(bodyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(hasResult ? 3 : nil)
                }
                Spacer(minLength: 0)
            }

            Label(badgeTitle, systemImage: isBusy ? "hourglass" : "sparkles")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(badgeColor.opacity(0.14), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(badgeColor.opacity(0.22), lineWidth: 1)
                )

            Button(action: action) {
                Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                    .font(.headline.weight(.semibold))
                    .appPrimaryButtonSurface(disabled: isBusy)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy ? 0.7 : 1)

            if !hasResult {
                HStack(spacing: 8) {
                    QuickPill(icon: "camera", text: "Photo")
                    QuickPill(icon: "doc.text", text: "PDF")
                    QuickPill(icon: "cpu", text: "AI analysis")
                }
            }
        }
        .appSectionCard()
    }
}

private struct ScanResultOverviewCard: View {
    let result: AIAnalysisResult
    let isBusy: Bool

    private var isFailure: Bool {
        let summary = result.summary.lowercased()
        return summary.contains("could not be completed")
            || summary.contains("backend is unreachable")
            || summary.contains("could not connect to the server")
            || summary.contains("timed out")
            || summary.contains("network is unavailable")
            || summary.contains("unauthorized")
            || summary.contains("forbidden")
            || summary.contains("not configured")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(isFailure ? AppDesign.warning : AppDesign.success)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isFailure ? "Scan Failed / Incomplete" : "Scan Completed")
                        .font(.headline.weight(.semibold))
                    if isFailure {
                        Text(result.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(compactStatusLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                StatTile(label: "Biomarkers", value: "\(result.biomarkers.count)", tint: .blue)
                StatTile(label: "Recommendations", value: "\(result.recommendations.count)", tint: AppDesign.accent)
                StatTile(label: "Status", value: isFailure ? "Retry" : "OK", tint: isFailure ? AppDesign.warning : AppDesign.success)
            }

        }
        .appSectionCard()
    }

    private var compactStatusLine: String {
        let biomarkerCount = result.biomarkers.count
        let recoCount = result.recommendations.count
        if biomarkerCount == 0 && recoCount == 0 {
            return "Analysis finished, but no structured items were extracted."
        }
        return "\(biomarkerCount) biomarkers • \(recoCount) recommendations"
    }
}

private struct ScanNoDataCard: View {
    let summary: String
    let isBusy: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Structured Result")
                .font(.headline.weight(.semibold))
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                onRetry()
            } label: {
                Label("Try Another Scan", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .appPrimaryButtonSurface(disabled: isBusy)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .appSectionCard()
    }
}

private struct ScanHowItWorksCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before You Start")
                .font(.headline.weight(.semibold))
            FlowRow(step: "1", title: "Pick source", detail: "Camera, photo library, or PDF.")
            FlowRow(step: "2", title: "Wait for processing", detail: "PDF pages are rendered, then sent to backend AI.")
            FlowRow(step: "3", title: "Review output", detail: "Biomarkers, recommendations, summary, disclaimer.")
            Text("If analysis fails after PDF render, the most common cause is backend not running on 127.0.0.1:8080.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSectionCard()
    }
}

private struct FlowRow: View {
    let step: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(AppDesign.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct QuickPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    Capsule().fill(.white.opacity(0.5))
                } else {
                    Capsule().fill(.white.opacity(0.72))
                }
            }
        )
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.34), lineWidth: 1)
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.subheadline.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }
}

struct AnalyzingScannerView: View {
    let previewImage: UIImage?
    let loadingMessage: String
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("AI Analysis", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    ScanningDotsView()
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.14), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                ProcessingOrbitalView()
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppDesign.accent.opacity(pulse ? 0.55 : 0.18), lineWidth: 1.25)
                    .blur(radius: pulse ? 0.2 : 0)
            )

            Text(loadingMessage)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .lineLimit(2)
                .animation(.easeInOut(duration: AppMotion.medium), value: loadingMessage)

            Button {
                onCancel()
            } label: {
                Label("Stop Scan", systemImage: "xmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard(cornerRadius: 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyzing report. \(loadingMessage)")
    }
}

private struct ProcessingOrbitalView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                let orbit = orbitRadius(for: index)
                let baseDot = baseDotSize(for: index)
                Circle()
                    .fill(index.isMultiple(of: 2) ? AppDesign.accent.opacity(0.96) : Color.blue.opacity(0.9))
                    .frame(width: baseDot, height: baseDot)
                    .scaleEffect(dotScale(for: index))
                    .shadow(color: .white.opacity(index.isMultiple(of: 2) ? 0.25 : 0.18), radius: 7)
                    .offset(x: orbit)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(
                        reduceMotion ? nil :
                            .linear(duration: 2.1 + Double(index % 4) * 0.38)
                            .repeatForever(autoreverses: false),
                        value: spin
                    )
                    .overlay {
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: baseDot * 0.36, height: baseDot * 0.36)
                            .offset(x: -baseDot * 0.12, y: -baseDot * 0.12)
                            .opacity(0.7)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            spin = true
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }

    private func orbitRadius(for index: Int) -> CGFloat {
        let bands: [CGFloat] = [28, 42, 56, 72]
        return bands[index % bands.count]
    }

    private func baseDotSize(for index: Int) -> CGFloat {
        let sizes: [CGFloat] = [14, 10, 12, 9, 13, 11, 10, 12, 9, 11]
        return sizes[index % sizes.count]
    }

    private func dotScale(for index: Int) -> CGFloat {
        let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
        let amplitude: CGFloat = 0.22 + CGFloat(index % 3) * 0.04
        return pulse ? (1 + amplitude * direction) : (1 - amplitude * direction * 0.55)
    }
}

private struct ScanGridOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            Path { path in
                let columns = 4
                let rows = 5
                for col in 1..<columns {
                    let x = width * CGFloat(col) / CGFloat(columns)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                for row in 1..<rows {
                    let y = height * CGFloat(row) / CGFloat(rows)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.6, dash: [4, 6]))
        }
        .allowsHitTesting(false)
    }
}

private struct ScanningDotsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppDesign.accent.opacity(animate ? 1 : 0.35))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1 : 0.7)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.6)
                            .delay(Double(index) * 0.12)
                            .repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .onAppear { animate = !reduceMotion }
        .accessibilityHidden(true)
    }
}

struct ScannerBeamView: View {
    @State private var travelDown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let travel = proxy.size.height * 0.44
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.cyan.opacity(0.18),
                    Color.green.opacity(0.72),
                    Color.cyan.opacity(0.18),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 54)
            .blur(radius: 0.3)
            .offset(y: travelDown ? travel : -travel)
            .onAppear {
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: AppMotion.slow).repeatForever(autoreverses: true)) {
                        travelDown = true
                    }
                } else {
                    travelDown = true
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct BiomarkerTile: View {
    let item: AIAnalysisResult.Biomarker

    private var isOptimal: Bool {
        if item.status.localizedCaseInsensitiveContains("optimal") ||
            item.status.localizedCaseInsensitiveContains("normal") {
            return true
        }
        return false
    }

    private var statusColor: Color {
        isOptimal ? AppDesign.success : AppDesign.error
    }

    private var cardTint: Color {
        if #available(iOS 26.0, *) {
            if item.status.localizedCaseInsensitiveContains("high") {
                return Color.orange.opacity(0.12)
            }
            if isOptimal {
                return Color.blue.opacity(0.10)
            }
        }
        return Color.white
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(statusColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "scalemass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(item.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(item.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(item.value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(item.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardTint)
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.cardRadius, style: .continuous)
                .stroke(.white.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.status), value \(item.value)")
    }
}

struct ProductRecommendationCard: View {
    let item: AIAnalysisResult.Recommendation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.max")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(item.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(item.protocolText, systemImage: "capsule.portrait")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.82))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassCard(cornerRadius: AppDesign.cardRadius)
        .accessibilityLabel("\(item.name). \(item.reason). Protocol: \(item.protocolText)")
    }
}

@available(iOS 26.0, *)
struct MiniSparklineView: View {
    let values: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private var bars: [CGFloat] {
        values.map { status in
            if status.localizedCaseInsensitiveContains("optimal") || status.localizedCaseInsensitiveContains("normal") {
                return 0.4
            }
            if status.localizedCaseInsensitiveContains("high") {
                return 0.9
            }
            return 0.7
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(index % 2 == 0 ? AppDesign.accent.opacity(0.95) : Color.blue.opacity(0.8))
                    .frame(width: 8, height: animate ? (14 + bar * 30) : 8)
                    .animation(.easeInOut(duration: AppMotion.slow).delay(Double(index) * 0.04).repeatForever(autoreverses: true), value: animate)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { animate = !reduceMotion }
    }
}
