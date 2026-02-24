import SwiftUI
import SwiftData
import Foundation

struct HistoryView: View {
    @Query(sort: \ScanResult.timestamp, order: .reverse)
    private var scans: [ScanResult]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                timelineBody
            } else {
                ios18Body
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: AppMotion.slow).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private var groupedScansByDay: [(date: Date, scans: [ScanResult])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: scans) { scan in
            calendar.startOfDay(for: scan.timestamp)
        }
        return grouped
            .map { ($0.key, $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.0 > $1.0 }
    }

    private var ios18Body: some View {
        List {
            if scans.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.03 : 0.97))

                        Text("No scans yet. Your history will appear here.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                if scans.count > 1 {
                    Section {
                        TrendsDashboardView(scans: scans)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }

                ForEach(groupedScansByDay, id: \.date) { bucket in
                    Section(bucket.date.formatted(date: .abbreviated, time: .omitted)) {
                        ForEach(bucket.scans) { scan in
                            NavigationLink {
                                ScanResultDetailView(scan: scan)
                                    .transition(.opacity)
                            } label: {
                                HistoryCard(scan: scan, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.clear)
        .listStyle(.insetGrouped)
    }

    @available(iOS 26.0, *)
    private var timelineBody: some View {
        ScrollView(showsIndicators: false) {
            if scans.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .scaleEffect(reduceMotion ? 1 : (pulse ? 1.03 : 0.97))

                    Text("No scans yet. Your history will appear here.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
                .padding(.horizontal, 20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if scans.count > 1 {
                        TrendsDashboardView(scans: scans)
                            .padding(.horizontal, 20)
                    }

                    ForEach(groupedScansByDay, id: \.date) { bucket in
                        Text(bucket.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        ForEach(Array(bucket.scans.enumerated()), id: \.element.id) { index, scan in
                            NavigationLink {
                                ScanResultDetailView(scan: scan)
                                    .transition(.opacity)
                            } label: {
                                HistoryTimelineRow(scan: scan, isLast: index == bucket.scans.count - 1)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

struct HistoryCard: View {
    let scan: ScanResult
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.timestamp.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(scan.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan from \(scan.timestamp.formatted(date: .abbreviated, time: .shortened))")
    }
}

@available(iOS 26.0, *)
struct HistoryTimelineRow: View {
    let scan: ScanResult
    let isLast: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nodePulse = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(AppDesign.accent.opacity(0.95))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(AppDesign.accent.opacity(0.24), lineWidth: 8)
                            .scaleEffect(nodePulse ? 1.14 : 0.9)
                            .opacity(nodePulse ? 0.35 : 0.15)
                    )
                    .onAppear {
                        if !reduceMotion {
                            withAnimation(.easeInOut(duration: AppMotion.slow).repeatForever(autoreverses: true)) {
                                nodePulse = true
                            }
                        }
                    }

                if !isLast {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 2)
                }
            }
            .frame(width: 16)

            GeometryReader { proxy in
                let minY = proxy.frame(in: .global).minY
                let parallax = reduceMotion ? 0 : minY * -0.03
                HistoryCard(scan: scan, showsChevron: true)
                    .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .offset(y: parallax)
            }
            .frame(height: 74)
        }
    }
}

struct ScanResultDetailView: View {
    let scan: ScanResult

    var body: some View {
        ZStack {
            MeshGradientBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(scan.timestamp.formatted(date: .complete, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.headline)
                        Text(scan.summary)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.9))
                    }
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.mint.opacity(0.26),
                                Color.blue.opacity(0.16),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 0.8)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Biomarkers")
                            .font(.title3.weight(.semibold))
                        ForEach(scan.biomarkers) { biomarker in
                            BiomarkerTile(
                                item: .init(
                                    name: biomarker.name,
                                    value: biomarker.value,
                                    status: biomarker.status,
                                    explanation: biomarker.explanation
                                )
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recommendations")
                            .font(.title3.weight(.semibold))
                        ForEach(scan.recommendations) { recommendation in
                            ProductRecommendationCard(
                                item: .init(
                                    name: recommendation.name,
                                    protocolText: recommendation.protocolText,
                                    reason: recommendation.reason
                                )
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Scan Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TrendsDashboardView: View {
    let scans: [ScanResult]

    private var allSeries: [TrendSeries] {
        TrendAnalytics.makeSeries(from: scans)
    }

    private var trendItems: [TrendSeries] {
        Array(allSeries.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trends")
                .font(.headline.weight(.semibold))
            Text("Track repeated biomarkers over time")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if trendItems.isEmpty {
                Text("Trend graphs will appear after repeated scans with numeric values.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                ForEach(trendItems) { item in
                    TrendMetricCard(item: item)
                }

                NavigationLink {
                    TrendsDetailView(series: allSeries)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                        Text("Open Detailed Trends")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AppDesign.accent)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }
}

private struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let status: TrendStatus
    let unit: String?
}

private enum TrendStatus: String {
    case optimal
    case high
    case low
    case unknown

    var color: Color {
        switch self {
        case .optimal:
            return AppDesign.success
        case .high:
            return AppDesign.warning
        case .low:
            return AppDesign.error
        case .unknown:
            return .secondary
        }
    }

    static func from(_ raw: String) -> TrendStatus {
        let value = raw.lowercased()
        if value.contains("optimal") || value.contains("normal") { return .optimal }
        if value.contains("high") { return .high }
        if value.contains("low") { return .low }
        return .unknown
    }
}

private struct TrendSeries: Identifiable {
    var id: String { name }
    let name: String
    let points: [TrendPoint]
    let unitLabel: String?

    var values: [Double] { points.map(\.value) }
    var latest: Double { values.last ?? 0 }
    var previous: Double { values.dropLast().last ?? latest }
    var delta: Double { latest - previous }
}

private enum TrendAnalytics {
    static func makeSeries(from scans: [ScanResult]) -> [TrendSeries] {
        let sorted = scans.sorted { $0.timestamp < $1.timestamp }
        var grouped: [String: [TrendPoint]] = [:]

        for scan in sorted {
            for biomarker in scan.biomarkers {
                guard let measurement = measurement(from: biomarker.value) else { continue }
                grouped[biomarker.name, default: []].append(
                    TrendPoint(
                        date: scan.timestamp,
                        value: measurement.value,
                        status: TrendStatus.from(biomarker.status),
                        unit: measurement.unit
                    )
                )
            }
        }

        return grouped
            .map { key, points in
                let dominantUnit = dominantUnit(in: points)
                let normalizedPoints = points
                    .filter { point in
                        guard let dominantUnit else { return true }
                        return point.unit?.lowercased() == dominantUnit.lowercased()
                    }
                    .sorted { $0.date < $1.date }

                return TrendSeries(name: key, points: normalizedPoints, unitLabel: dominantUnit)
            }
            .filter { $0.points.count >= 2 }
            .sorted { $0.points.count > $1.points.count }
    }

    static func measurement(from text: String) -> (value: Double, unit: String?)? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let pattern = #"[-+]?\d*\.?\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: range),
              let swiftRange = Range(match.range, in: normalized),
              let value = Double(String(normalized[swiftRange])) else { return nil }

        let unitStart = swiftRange.upperBound
        let tail = normalized[unitStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedUnit = tail
            .components(separatedBy: CharacterSet(charactersIn: "0123456789"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "(),:;"))

        if let cleanedUnit, !cleanedUnit.isEmpty {
            return (value, cleanedUnit)
        }
        return (value, nil)
    }

    private static func dominantUnit(in points: [TrendPoint]) -> String? {
        let counts = Dictionary(grouping: points.compactMap(\.unit)) { $0.lowercased() }
            .mapValues(\.count)
        guard let best = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return best
    }
}

private struct TrendMetricCard: View {
    let item: TrendSeries

    private var deltaColor: Color {
        if item.delta > 0 { return AppDesign.warning }
        if item.delta < 0 { return AppDesign.success }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if let unit = item.unitLabel {
                    Text(unit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.65), in: Capsule())
                }
                Text(item.latest.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.subheadline.weight(.bold))
                Text(deltaText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(deltaColor)
            }

            TrendSparkline(points: item.points)
                .frame(height: 28)
        }
        .padding(10)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var deltaText: String {
        let sign = item.delta > 0 ? "+" : ""
        return "\(sign)\(item.delta.formatted(.number.precision(.fractionLength(0...2))))"
    }
}

private struct TrendSparkline: View {
    let points: [TrendPoint]

    private var normalizedValues: [CGFloat] {
        let values = points.map(\.value)
        guard let min = values.min(), let max = values.max(), max > min else {
            return Array(repeating: 0.5, count: values.count)
        }
        return values.map { CGFloat(($0 - min) / (max - min)) }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let chartPoints = normalizedValues.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * (width / max(CGFloat(points.count - 1), 1)),
                    y: height - (value * height)
                )
            }

            ZStack {
                Path { path in
                    guard let first = chartPoints.first else { return }
                    path.move(to: first)
                    for point in chartPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(AppDesign.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                ForEach(Array(chartPoints.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(points[index].status.color.opacity(0.9))
                        .frame(width: 4, height: 4)
                        .position(point)
                }
            }
        }
    }
}

private enum TrendRange: String, CaseIterable, Identifiable {
    case days30 = "30D"
    case days90 = "90D"
    case all = "All"

    var id: String { rawValue }
}

private struct TrendsDetailView: View {
    let series: [TrendSeries]
    @State private var selectedSeriesID: String = ""
    @State private var selectedRange: TrendRange = .all

    private var selectedSeries: TrendSeries? {
        if let exact = series.first(where: { $0.id == selectedSeriesID }) {
            return exact
        }
        return series.first
    }

    private var filteredSeries: TrendSeries? {
        guard let selectedSeries else { return nil }
        guard selectedRange != .all else { return selectedSeries }

        let days = selectedRange == .days30 ? 30 : 90
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) else {
            return selectedSeries
        }

        let filteredPoints = selectedSeries.points.filter { $0.date >= start }
        return TrendSeries(
            name: selectedSeries.name,
            points: filteredPoints,
            unitLabel: selectedSeries.unitLabel
        )
    }

    var body: some View {
        ZStack {
            MeshGradientBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Biomarker Trends")
                        .font(.title2.weight(.semibold))
                    Text("Review how repeated markers change over time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if series.isEmpty {
                        Text("Not enough repeated numeric biomarkers yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .glassCard(cornerRadius: 16)
                    } else {
                        Menu {
                            ForEach(series) { item in
                                Button(item.name) {
                                    selectedSeriesID = item.id
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedSeries?.name ?? "Biomarker")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .glassCard(cornerRadius: 16)
                        }

                        Picker("Period", selection: $selectedRange) {
                            ForEach(TrendRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(12)
                        .glassCard(cornerRadius: 16)

                        if let filteredSeries {
                            if filteredSeries.points.count >= 2 {
                                TrendDetailChartCard(series: filteredSeries)
                                TrendReadingsList(series: filteredSeries)
                            } else {
                                Text("Not enough points in this period. Try a wider range.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(14)
                                    .glassCard(cornerRadius: 16)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedSeriesID.isEmpty {
                selectedSeriesID = series.first?.id ?? ""
            }
        }
    }
}

private struct TrendDetailChartCard: View {
    let series: TrendSeries

    private var deltaColor: Color {
        if series.delta > 0 { return AppDesign.warning }
        if series.delta < 0 { return AppDesign.success }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(series.name)
                    .font(.headline.weight(.semibold))
                Spacer()
                if let unit = series.unitLabel {
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("Latest \(series.latest.formatted(.number.precision(.fractionLength(0...2))))")
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 6) {
                Text("Change:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(deltaText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(deltaColor)
            }

            TrendSparkline(points: series.points)
                .frame(height: 120)
                .padding(.top, 4)

            TrendStatusLegend()

            HStack {
                Text(series.points.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                Spacer()
                Text(series.points.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    private var deltaText: String {
        let sign = series.delta > 0 ? "+" : ""
        return "\(sign)\(series.delta.formatted(.number.precision(.fractionLength(0...2))))"
    }
}

private struct TrendStatusLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            legendItem(color: TrendStatus.optimal.color, text: "Optimal")
            legendItem(color: TrendStatus.high.color, text: "High")
            legendItem(color: TrendStatus.low.color, text: "Low")
            legendItem(color: TrendStatus.unknown.color.opacity(0.8), text: "Unknown")
            Spacer()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: Optimal green, High orange, Low red, Unknown gray")
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
        }
    }
}

private struct TrendReadingsList: View {
    let series: TrendSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Readings")
                .font(.headline.weight(.semibold))

            ForEach(Array(series.points.reversed())) { point in
                HStack {
                    Text(point.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(point.value.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.subheadline.weight(.bold))
                }
                .padding(10)
                .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }
}
