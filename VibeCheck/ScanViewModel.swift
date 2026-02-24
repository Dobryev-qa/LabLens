import SwiftUI
import SwiftData
import PDFKit
import UIKit
import Combine
import OSLog
import Vision

@MainActor
final class ScanViewModel: ObservableObject {
    struct UserFacingAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published var isAnalyzing = false
    @Published var isPreparingDocument = false
    @Published var analysisResult: AIAnalysisResult?
    @Published var analyzingPreviewImage: UIImage?
    @Published var loadingMessage = "Reading lab results..."
    @Published var userFacingAlert: UserFacingAlert?
    @Published private(set) var cachedRetryUses = 0
    @Published private(set) var hasCachedRetryInput = false

    private let aiService: AIService
    private var loadingMessageTask: Task<Void, Never>?
    private var cachedRetryImages: [UIImage] = []
    private var cachedRetryProfile: UserProfile?
    private var cachedRetryOCRContext: AIService.OCRContext?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VibeCheck", category: "ScanViewModel")

    init(aiService: AIService? = nil) {
        self.aiService = aiService ?? AIService()
    }

    deinit {
        loadingMessageTask?.cancel()
    }

    func stopTransientWork() {
        loadingMessageTask?.cancel()
        loadingMessageTask = nil
    }

    func clearResult() {
        analysisResult = nil
        analyzingPreviewImage = nil
        userFacingAlert = nil
    }

    func clearCachedRetryInput() {
        cachedRetryImages = []
        cachedRetryProfile = nil
        cachedRetryOCRContext = nil
        cachedRetryUses = 0
        hasCachedRetryInput = false
    }

    func cancelCurrentOperation() {
        stopLoadingMessageLoop()
        loadingMessage = "Reading lab results..."
        analyzingPreviewImage = nil
        userFacingAlert = nil

        withAnimation(.easeInOut(duration: AppMotion.fast)) {
            isAnalyzing = false
            isPreparingDocument = false
        }
    }

    func analyze(
        images: [UIImage],
        profile: UserProfile?,
        modelContext: ModelContext,
        reduceMotion: Bool,
        isRetryingCachedInput: Bool = false,
        ocrContext: AIService.OCRContext? = nil
    ) async {
        guard !images.isEmpty else { return }
        guard !Task.isCancelled else {
            cancelCurrentOperation()
            return
        }
        userFacingAlert = nil

        if isRetryingCachedInput {
            cachedRetryUses += 1
        } else {
            cachedRetryImages = images
            cachedRetryProfile = profile
            cachedRetryOCRContext = ocrContext
            cachedRetryUses = 0
            hasCachedRetryInput = true
        }

        analyzingPreviewImage = images.first
        loadingMessage = loadingMessages(for: profile).first ?? "Reading lab results..."
        startLoadingMessageLoop(profile: profile)

        withAnimation(.easeInOut(duration: reduceMotion ? AppMotion.fast : AppMotion.medium)) {
            isAnalyzing = true
        }

        analysisResult = nil
        let effectiveOCRContext: AIService.OCRContext?
        if let ocrContext {
            effectiveOCRContext = ocrContext
        } else if images.count == 1 {
            loadingMessage = "Reading text with OCR..."
            effectiveOCRContext = await extractOCRContextForStandaloneImages(images)
        } else {
            effectiveOCRContext = nil
        }

        let result = await aiService.analyzeImages(images: images, profile: profile, ocrContext: effectiveOCRContext)
        guard !Task.isCancelled else {
            cancelCurrentOperation()
            return
        }

        withAnimation(reduceMotion ? .easeInOut(duration: AppMotion.fast) : AppMotion.spring) {
            analysisResult = result
        }
        userFacingAlert = buildUserFacingAlert(from: result)

        persistScanResult(result, modelContext: modelContext)
        stopLoadingMessageLoop()

        withAnimation(.easeInOut(duration: reduceMotion ? AppMotion.fast : AppMotion.slow)) {
            isAnalyzing = false
        }

        analyzingPreviewImage = nil
    }

    func preparePDFAndAnalyze(
        url: URL,
        profile: UserProfile?,
        modelContext: ModelContext,
        reduceMotion: Bool
    ) async {
        guard !Task.isCancelled else {
            cancelCurrentOperation()
            return
        }
        userFacingAlert = nil
        withAnimation(.easeInOut(duration: AppMotion.medium)) {
            isPreparingDocument = true
        }

        let images = await drawPDFPagesToImages(url: url) { [weak self] rendered, total in
            self?.loadingMessage = "Rendering PDF pages \(rendered)/\(total)..."
        }
        guard !Task.isCancelled else {
            cancelCurrentOperation()
            return
        }
        logger.log("pdf_render_complete pagesAsImages=\(images.count, privacy: .public)")
        exportRenderedPDFImagesForDebug(images, sourceURL: url)

        guard !images.isEmpty else {
            withAnimation(.easeInOut(duration: AppMotion.fast)) {
                isPreparingDocument = false
            }
            userFacingAlert = .init(
                title: "PDF unavailable",
                message: "Could not read pages from this PDF. Try another file or export it again from your lab app."
            )
            return
        }

        loadingMessage = "Preparing page groups for AI..."
        // Stitch more pages per image to reduce vision payload count while keeping overlap
        // for cross-page continuity (e.g. title on one page, values on the next).
        let imagesForAI = stitchPDFPagesForAI(images, pagesPerImage: 3, overlapPages: 1)
        logger.log(
            "pdf_stitch_complete rawPages=\(images.count, privacy: .public) stitchedImages=\(imagesForAI.count, privacy: .public)"
        )
        exportStitchedPDFImagesForDebug(imagesForAI, sourceURL: url)

        loadingMessage = "Extracting text with OCR..."
        let pageOCR = await extractOCRPerPage(images)
        let stitchedGroups = stitchedPageGroups(totalPages: images.count, pagesPerImage: 3, overlapPages: 1)
        let ocrContext = buildPDFOCRContext(pageOCR: pageOCR, stitchedGroups: stitchedGroups)

        analyzingPreviewImage = imagesForAI.first ?? images.first
        withAnimation(.easeInOut(duration: AppMotion.fast)) {
            isPreparingDocument = false
        }

        await analyze(
            images: imagesForAI,
            profile: profile,
            modelContext: modelContext,
            reduceMotion: reduceMotion,
            ocrContext: ocrContext
        )
    }

    func retryLastAnalyze(
        modelContext: ModelContext,
        reduceMotion: Bool
    ) async -> Bool {
        guard !cachedRetryImages.isEmpty else { return false }
        await analyze(
            images: cachedRetryImages,
            profile: cachedRetryProfile,
            modelContext: modelContext,
            reduceMotion: reduceMotion,
            isRetryingCachedInput: true,
            ocrContext: cachedRetryOCRContext
        )
        return true
    }

    private func startLoadingMessageLoop(profile: UserProfile?) {
        loadingMessageTask?.cancel()
        let messages = loadingMessages(for: profile)
        loadingMessageTask = Task {
            var index = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                index = (index + 1) % messages.count
                loadingMessage = messages[index]
            }
        }
    }

    private func stopLoadingMessageLoop() {
        loadingMessageTask?.cancel()
        loadingMessageTask = nil
    }

    private func loadingMessages(for profile: UserProfile?) -> [String] {
        let gender = profile?.gender == .notSet || profile == nil ? "user" : (profile?.gender.title.lowercased() ?? "user")
        return [
            "Reading lab results...",
            "Comparing with norms for \(gender)...",
            "Synthesizing supplement protocol...",
            "Finalizing your health report..."
        ]
    }

    private func buildUserFacingAlert(from result: AIAnalysisResult) -> UserFacingAlert? {
        let summary = result.summary.lowercased()
        if summary.contains("401") || summary.contains("unauthorized") {
            return .init(
                title: "Authorization required",
                message: "Backend token is invalid or missing. Check API_AUTH_TOKEN configuration."
            )
        }
        if summary.contains("403") || summary.contains("forbidden") {
            return .init(
                title: "Access denied",
                message: "Backend rejected this request. Check backend auth policy."
            )
        }
        if summary.contains("base url") || summary.contains("not configured") {
            return .init(
                title: "Backend not configured",
                message: "Set API_BASE_URL and try again."
            )
        }
        if summary.contains("backend is unreachable") || summary.contains("could not connect to the server") {
            return .init(
                title: "Backend is offline",
                message: "The app rendered your PDF successfully, but the backend is not running. Start the backend on 127.0.0.1:8080 and retry."
            )
        }
        if summary.contains("timed out") {
            return .init(
                title: "Analysis timed out",
                message: "PDF rendering completed, but the backend/AI response took too long. Retry, or test with fewer pages first."
            )
        }
        if summary.contains("network is unavailable") {
            return .init(
                title: "No network",
                message: "Check your connection (or local backend) and try again."
            )
        }
        if summary.contains("could not be completed") {
            return .init(
                title: "Analysis failed",
                message: "The report could not be analyzed right now. Please retry in a moment."
            )
        }
        return nil
    }

    private func persistScanResult(_ result: AIAnalysisResult, modelContext: ModelContext) {
        guard !result.biomarkers.isEmpty else { return }
        if result.summary == "Analysis could not be completed." {
            return
        }

        let item = ScanResult(
            summary: result.summary,
            biomarkers: result.biomarkers.map {
                SavedBiomarker(
                    name: $0.name,
                    value: $0.value,
                    status: $0.status,
                    explanation: $0.explanation
                )
            },
            recommendations: result.recommendations.map {
                SavedRecommendation(
                    name: $0.name,
                    protocolText: $0.protocolText,
                    reason: $0.reason
                )
            }
        )

        modelContext.insert(item)
        do {
            try modelContext.save()
        } catch {
            logger.error("swiftdata_save_failed \(error.localizedDescription, privacy: .public)")
        }
    }

    private func drawPDFPagesToImages(
        url: URL,
        progress: @escaping @MainActor (_ rendered: Int, _ total: Int) -> Void
    ) async -> [UIImage] {
        await Task(priority: .userInitiated) {
            guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                return [UIImage]()
            }

            var images: [UIImage] = []
            let total = document.pageCount
            await progress(0, total)

            for pageIndex in 0..<total {
                if Task.isCancelled { break }
                guard let page = document.page(at: pageIndex) else { continue }
                let pageRect = page.bounds(for: .mediaBox)
                guard pageRect.width > 0, pageRect.height > 0 else { continue }

                let maxSide: CGFloat = 1200
                let scale = min(maxSide / pageRect.width, maxSide / pageRect.height, 1.0)
                let targetSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
                images.append(page.thumbnail(of: targetSize, for: .mediaBox))
                await progress(pageIndex + 1, total)
            }
            return images
        }.value
    }

    private func exportRenderedPDFImagesForDebug(_ images: [UIImage], sourceURL: URL) {
        exportPDFImagesForDebug(images, sourceURL: sourceURL, folderPrefix: "PDFRenderDebug", pagePrefix: "page")
    }

    private func exportStitchedPDFImagesForDebug(_ images: [UIImage], sourceURL: URL) {
        exportPDFImagesForDebug(images, sourceURL: sourceURL, folderPrefix: "PDFStitchedDebug", pagePrefix: "group")
    }

    private func exportPDFImagesForDebug(
        _ images: [UIImage],
        sourceURL: URL,
        folderPrefix: String,
        pagePrefix: String
    ) {
        guard !images.isEmpty else { return }

        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("pdf_debug_export_failed missing_documents_directory")
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let safeSourceName = sourceName.isEmpty ? "report" : sourceName.replacingOccurrences(of: "/", with: "_")
        let exportFolder = documentsURL
            .appendingPathComponent(folderPrefix, isDirectory: true)
            .appendingPathComponent("\(timestamp)_\(safeSourceName)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: exportFolder, withIntermediateDirectories: true, attributes: nil)

            var metadataLines: [String] = [
                "source_pdf=\(sourceURL.lastPathComponent)",
                "pages=\(images.count)",
                "created_at=\(timestamp)"
            ]

            for (index, image) in images.enumerated() {
                let pageNumber = index + 1
                let pageName = String(format: "\(pagePrefix)_%03d", pageNumber)
                let outputURL = exportFolder.appendingPathComponent("\(pageName).png")

                if let png = image.pngData() {
                    try png.write(to: outputURL, options: .atomic)
                } else if let jpeg = image.jpegData(compressionQuality: 1.0) {
                    let jpgURL = exportFolder.appendingPathComponent("\(pageName).jpg")
                    try jpeg.write(to: jpgURL, options: .atomic)
                } else {
                    metadataLines.append("page_\(pageNumber)=failed_to_encode")
                    continue
                }

                let size = image.size
                metadataLines.append("page_\(pageNumber)=\(Int(size.width))x\(Int(size.height))")
            }

            let metadataURL = exportFolder.appendingPathComponent("metadata.txt")
            let metadata = metadataLines.joined(separator: "\n")
            if let metadataData = metadata.data(using: .utf8) {
                try metadataData.write(to: metadataURL, options: .atomic)
            }

            logger.log("pdf_debug_export_saved folder=\(exportFolder.path, privacy: .public)")
        } catch {
            logger.error("pdf_debug_export_failed \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stitchPDFPagesForAI(_ pages: [UIImage], pagesPerImage: Int, overlapPages: Int = 0) -> [UIImage] {
        guard pagesPerImage > 1, !pages.isEmpty else { return pages }
        let safeOverlap = min(max(overlapPages, 0), pagesPerImage - 1)
        let stride = max(1, pagesPerImage - safeOverlap)

        var stitched: [UIImage] = []
        var index = 0
        while index < pages.count {
            let chunk = Array(pages[index..<min(index + pagesPerImage, pages.count)])
            if let stitchedImage = stitchPagesChunkHorizontally(chunk, startPageIndex: index + 1, totalPages: pages.count) {
                stitched.append(stitchedImage)
            } else {
                stitched.append(contentsOf: chunk)
            }
            if index + pagesPerImage >= pages.count { break }
            index += stride
        }
        return stitched
    }

    private func stitchPagesChunkHorizontally(_ pages: [UIImage], startPageIndex: Int, totalPages: Int) -> UIImage? {
        guard !pages.isEmpty else { return nil }
        if pages.count == 1 { return pages[0] }

        let padding: CGFloat = 20
        let labelHeight: CGFloat = 34

        let targetHeight = pages.map(\.size.height).max() ?? 0
        guard targetHeight > 0 else { return nil }

        let scaledSizes: [CGSize] = pages.map { image in
            let scale = targetHeight / max(image.size.height, 1)
            return CGSize(width: floor(image.size.width * scale), height: targetHeight)
        }

        let totalWidth = scaledSizes.reduce(0) { $0 + $1.width } + (CGFloat(pages.count + 1) * padding)
        let canvasSize = CGSize(width: totalWidth, height: targetHeight + labelHeight + (padding * 2))

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: rendererFormat)

        return renderer.image { ctx in
            let bounds = CGRect(origin: .zero, size: canvasSize)
            UIColor.white.setFill()
            ctx.fill(bounds)

            var x = padding
            for (idx, page) in pages.enumerated() {
                let size = scaledSizes[idx]
                let pageFrame = CGRect(x: x, y: padding + labelHeight, width: size.width, height: size.height)

                UIColor(white: 0.93, alpha: 1).setFill()
                UIBezierPath(roundedRect: pageFrame.insetBy(dx: -2, dy: -2), cornerRadius: 8).fill()
                page.draw(in: pageFrame)

                let pageNumber = startPageIndex + idx
                let label = "Page \(pageNumber)/\(totalPages)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: UIColor.darkGray
                ]
                let labelRect = CGRect(x: x, y: padding + 4, width: size.width, height: labelHeight - 4)
                (label as NSString).draw(in: labelRect, withAttributes: attrs)

                x += size.width + padding
            }
        }
    }

    private func stitchedPageGroups(totalPages: Int, pagesPerImage: Int, overlapPages: Int = 0) -> [[Int]] {
        guard totalPages > 0 else { return [] }
        guard pagesPerImage > 1 else {
            return (1...totalPages).map { [$0] }
        }

        let safeOverlap = min(max(overlapPages, 0), pagesPerImage - 1)
        let stride = max(1, pagesPerImage - safeOverlap)
        var groups: [[Int]] = []
        var index = 0

        while index < totalPages {
            let start = index + 1
            let end = min(index + pagesPerImage, totalPages)
            groups.append(Array(start...end))
            if index + pagesPerImage >= totalPages { break }
            index += stride
        }
        return groups
    }

    private func buildPDFOCRContext(pageOCR: [String], stitchedGroups: [[Int]]) -> AIService.OCRContext? {
        let cleanedPageOCR = pageOCR.enumerated().compactMap { idx, text -> AIService.OCRContext.PageText? in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .init(page: idx + 1, text: trimmed)
        }

        guard !cleanedPageOCR.isEmpty else { return nil }

        let reportText = cleanedPageOCR
            .map { "[Page \($0.page)]\n\($0.text)" }
            .joined(separator: "\n\n")

        return AIService.OCRContext(
            reportText: reportText,
            reportTextByPage: cleanedPageOCR,
            stitchedPageGroups: stitchedGroups.isEmpty ? nil : stitchedGroups
        )
    }

    private func extractOCRContextForStandaloneImages(_ images: [UIImage]) async -> AIService.OCRContext? {
        let texts = await extractOCRPerPage(images)
        let pageText = texts.enumerated().compactMap { index, text -> AIService.OCRContext.PageText? in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .init(page: index + 1, text: trimmed)
        }
        guard !pageText.isEmpty else { return nil }
        return AIService.OCRContext(
            reportText: pageText.map { "[Page \($0.page)]\n\($0.text)" }.joined(separator: "\n\n"),
            reportTextByPage: pageText,
            stitchedPageGroups: images.count > 1 ? (1...images.count).map { [$0] } : nil
        )
    }

    private func extractOCRPerPage(_ images: [UIImage]) async -> [String] {
        guard !images.isEmpty else { return [] }
        return await Task(priority: .userInitiated) {
            images.map { image in
                if Task.isCancelled { return "" }
                return recognizeText(in: image)
            }
        }.value
    }

    private func recognizeText(in image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let observations = (request.results ?? [])
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        } catch {
            logger.error("ocr_failed \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }
}
