import Foundation
import UIKit
import OSLog

struct AIAnalysisResult {
    let biomarkers: [Biomarker]
    let recommendations: [Recommendation]
    let summary: String
    let disclaimer: String

    struct Biomarker: Identifiable {
        let id = UUID()
        let name: String
        let value: String
        let status: String
        let explanation: String
    }

    struct Recommendation: Identifiable {
        let id = UUID()
        let name: String
        let protocolText: String
        let reason: String
    }
}

final class AIService {
    struct OCRContext {
        struct PageText: Encodable {
            let page: Int
            let text: String
        }

        let reportText: String?
        let reportTextByPage: [PageText]?
        let stitchedPageGroups: [[Int]]?
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VibeCheck", category: "AIService")
    private let session: URLSession
    private let baseURL: URL?
    private let apiAuthToken: String?

    init() {
        let raw = FeatureFlags.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = Self.resolveBackendBaseURL(from: raw)
        apiAuthToken = FeatureFlags.apiAuthToken

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration)
    }

    func analyzeImage(image: UIImage, profile: UserProfile? = nil, ocrContext: OCRContext? = nil) async -> AIAnalysisResult {
        await analyzeImages(images: [image], profile: profile, ocrContext: ocrContext)
    }

    func analyzeImages(images: [UIImage], profile: UserProfile? = nil, ocrContext: OCRContext? = nil) async -> AIAnalysisResult {
        guard baseURL != nil else {
            return unconfiguredResult("Backend API base URL is not configured.")
        }

        do {
            guard !images.isEmpty else {
                throw AIServiceError.imageEncodingFailed
            }

            let base64Images = try images.map { try encodeImageToBase64($0) }
            let approxMB = Double(base64Images.reduce(0) { $0 + $1.count }) / 1_000_000
            logger.log("sending backend analyze images=\(base64Images.count, privacy: .public) payloadMB=\(approxMB, privacy: .public)")

            let request = try makeRequest(with: base64Images, profile: profile, ocrContext: ocrContext)
            let (data, response) = try await session.data(for: request)
            return try parseBackendResponse(data: data, response: response)
        } catch AIServiceError.unauthorized {
            AIServiceTelemetry.log(.backendUnauthorized)
            return accessDeniedResult("Backend unauthorized (401). Check API_AUTH_TOKEN.")
        } catch AIServiceError.forbidden {
            AIServiceTelemetry.log(.backendForbidden)
            return accessDeniedResult("Backend access forbidden (403). Check auth policy.")
        } catch let error as AIServiceError {
            AIServiceTelemetry.log(.analysisFailed(error.localizedDescription))
        } catch let urlError as URLError where urlError.code == .cannotFindHost || urlError.code == .unsupportedURL || urlError.code == .badURL {
            AIServiceTelemetry.log(.analysisFailed("Invalid backend URL: \(urlError.localizedDescription)"))
            return unconfiguredResult("Backend API base URL is invalid. Check API_BASE_URL (example: http://127.0.0.1:8080).")
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
            AIServiceTelemetry.log(.analysisFailed("Backend unreachable: \(urlError.localizedDescription)"))
            let endpointHost = baseURL?.host ?? "127.0.0.1"
            let endpointPort = baseURL?.port.map(String.init) ?? (baseURL?.scheme == "https" ? "443" : "80")
            return unconfiguredResult("Backend is unreachable at \(endpointHost):\(endpointPort). Start the local backend and try again.")
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet {
            AIServiceTelemetry.log(.analysisFailed("No internet / network unavailable"))
            return unconfiguredResult("Network is unavailable. Connect to the internet or local backend and retry.")
        } catch let nsError as NSError where nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            if code == .cannotConnectToHost || code == .cannotFindHost || code == .dnsLookupFailed {
                AIServiceTelemetry.log(.analysisFailed("Backend unreachable: \(nsError.localizedDescription)"))
                let endpointHost = baseURL?.host ?? "127.0.0.1"
                let endpointPort = baseURL?.port.map(String.init) ?? (baseURL?.scheme == "https" ? "443" : "80")
                return unconfiguredResult("Backend is unreachable at \(endpointHost):\(endpointPort). Start the local backend and try again.")
            }
            if code == .notConnectedToInternet || code == .networkConnectionLost {
                AIServiceTelemetry.log(.analysisFailed("Network unavailable: \(nsError.localizedDescription)"))
                return unconfiguredResult("Network is unavailable. Connect to the internet or local backend and retry.")
            }
            if code == .unsupportedURL || code == .badURL {
                AIServiceTelemetry.log(.analysisFailed("Invalid backend URL: \(nsError.localizedDescription)"))
                return unconfiguredResult("Backend API base URL is invalid. Check API_BASE_URL (example: http://127.0.0.1:8080).")
            }
            AIServiceTelemetry.log(.analysisFailed("NSURLError \(nsError.code): \(nsError.localizedDescription)"))
        } catch let urlError as URLError where urlError.code == .timedOut {
            AIServiceTelemetry.log(.networkTimeout)
            let endpointHost = baseURL?.host ?? "127.0.0.1"
            let endpointPort = baseURL?.port.map(String.init) ?? (baseURL?.scheme == "https" ? "443" : "80")
            return unconfiguredResult("Backend request timed out at \(endpointHost):\(endpointPort). The PDF was rendered, but AI analysis took too long. Retry or try fewer pages.")
        } catch {
            AIServiceTelemetry.log(.unexpectedError(error.localizedDescription))
        }

        return fallbackResult()
    }

    private func makeRequest(with base64Images: [String], profile: UserProfile?, ocrContext: OCRContext?) throws -> URLRequest {
        guard let baseURL else { throw AIServiceError.missingBaseURL }
        let endpoint = baseURL.appending(path: "/v1/analyze-report")
        logger.log("backend_endpoint \(endpoint.absoluteString, privacy: .public)")

        let payload = BackendAnalyzeRequest(
            images: base64Images,
            reportText: ocrContext?.reportText,
            reportTextByPage: ocrContext?.reportTextByPage,
            stitchedPageGroups: ocrContext?.stitchedPageGroups,
            profile: profile.map {
                BackendAnalyzeRequest.Profile(
                    gender: $0.gender.promptText,
                    ageBand: $0.ageBand,
                    weightBand: $0.weightBand
                )
            }
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = apiAuthToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            AIServiceTelemetry.log(.configMissingAuthToken)
        }
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func parseBackendResponse(data: Data, response: URLResponse) throws -> AIAnalysisResult {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw AIServiceError.unauthorized }
            if httpResponse.statusCode == 403 { throw AIServiceError.forbidden }
            throw AIServiceError.httpError(httpResponse.statusCode)
        }

        let parsed: BackendAnalyzeResponse
        do {
            parsed = try JSONDecoder().decode(BackendAnalyzeResponse.self, from: data)
        } catch {
            throw AIServiceError.invalidJSON
        }

        let biomarkers = parsed.biomarkers.map {
            AIAnalysisResult.Biomarker(
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines),
                status: normalizeStatus($0.status),
                explanation: $0.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let recommendations = parsed.recommendations.map {
            AIAnalysisResult.Recommendation(
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                protocolText: ($0.protocolText ?? $0.protocolValue ?? "No protocol provided.").trimmingCharacters(in: .whitespacesAndNewlines),
                reason: $0.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return AIAnalysisResult(
            biomarkers: biomarkers,
            recommendations: recommendations,
            summary: parsed.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            disclaimer: parsed.disclaimer ?? "DISCLAIMER: This is not medical advice. Consult a healthcare provider before use."
        )
    }

    private func encodeImageToBase64(_ image: UIImage) throws -> String {
        let normalized = resizedToFit(image: image, maxDimension: FeatureFlags.aiImageMaxDimension)
        guard let data = normalized.jpegData(compressionQuality: FeatureFlags.aiImageCompressionQuality) else {
            throw AIServiceError.imageEncodingFailed
        }
        return data.base64EncodedString()
    }

    private func resizedToFit(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }

        let scale = maxDimension / longest
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        return resize(image: image, to: target) ?? image
    }

    private func resize(image: UIImage, to targetSize: CGSize) -> UIImage? {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func normalizeStatus(_ raw: String) -> String {
        let value = raw.lowercased()
        if value.contains("optimal") || value.contains("normal") { return "Optimal" }
        if value.contains("high") { return "High" }
        if value.contains("low") { return "Low" }
        return "Unknown"
    }

    private func unconfiguredResult(_ message: String) -> AIAnalysisResult {
        AIAnalysisResult(
            biomarkers: [],
            recommendations: [],
            summary: message,
            disclaimer: "DISCLAIMER: This is not medical advice. Consult a healthcare provider before use."
        )
    }

    private func fallbackResult() -> AIAnalysisResult {
        AIAnalysisResult(
            biomarkers: [],
            recommendations: [],
            summary: "Analysis could not be completed.",
            disclaimer: "DISCLAIMER: This is not medical advice. Consult a healthcare provider before use."
        )
    }

    private func accessDeniedResult(_ message: String) -> AIAnalysisResult {
        AIAnalysisResult(
            biomarkers: [],
            recommendations: [],
            summary: message,
            disclaimer: "DISCLAIMER: This is not medical advice. Consult a healthcare provider before use."
        )
    }

    private static func resolveBackendBaseURL(from raw: String) -> URL? {
        guard let url = URL(string: raw), isValidBackendBaseURL(url) else {
            #if targetEnvironment(simulator)
            let fallback = URL(string: "http://127.0.0.1:8080")
            if raw.isEmpty {
                AIServiceTelemetry.log(.configMissingBaseURL)
            } else {
                AIServiceTelemetry.log(.analysisFailed("Invalid API_BASE_URL value; using simulator fallback"))
            }
            return fallback
            #else
            AIServiceTelemetry.log(.configMissingBaseURL)
            return nil
            #endif
        }
        return url
    }

    private static func isValidBackendBaseURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }
}

private struct BackendAnalyzeRequest: Encodable {
    let images: [String]
    let reportText: String?
    let reportTextByPage: [AIService.OCRContext.PageText]?
    let stitchedPageGroups: [[Int]]?
    let profile: Profile?

    struct Profile: Encodable {
        let gender: String
        let ageBand: String
        let weightBand: String?
    }
}

private struct BackendAnalyzeResponse: Decodable {
    let biomarkers: [Biomarker]
    let recommendations: [Recommendation]
    let summary: String
    let disclaimer: String?

    struct Biomarker: Decodable {
        let name: String
        let value: String
        let status: String
        let explanation: String
    }

    struct Recommendation: Decodable {
        let name: String
        let protocolValue: String?
        let protocolText: String?
        let reason: String

        private enum CodingKeys: String, CodingKey {
            case name
            case protocolValue = "protocol"
            case protocolText
            case reason
        }
    }
}

private enum AIServiceError: Error, LocalizedError {
    case missingBaseURL
    case imageEncodingFailed
    case invalidResponse
    case unauthorized
    case forbidden
    case httpError(Int)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "Missing API_BASE_URL."
        case .imageEncodingFailed:
            return "Image encoding failed."
        case .invalidResponse:
            return "Invalid network response."
        case .unauthorized:
            return "Unauthorized (401)."
        case .forbidden:
            return "Forbidden (403)."
        case .httpError(let status):
            return "Server returned status code \(status)."
        case .invalidJSON:
            return "The backend response was not valid JSON."
        }
    }
}

private enum AIServiceTelemetry {
    case configMissingBaseURL
    case configMissingAuthToken
    case backendUnauthorized
    case backendForbidden
    case networkTimeout
    case analysisFailed(String)
    case unexpectedError(String)

    static func log(_ event: AIServiceTelemetry) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VibeCheck", category: "AI")
        switch event {
        case .configMissingBaseURL:
            logger.error("ai.config.missing_base_url")
        case .configMissingAuthToken:
            logger.warning("ai.config.missing_auth_token")
        case .backendUnauthorized:
            logger.warning("ai.backend.unauthorized")
        case .backendForbidden:
            logger.warning("ai.backend.forbidden")
        case .networkTimeout:
            logger.warning("ai.network.timeout")
        case .analysisFailed(let reason):
            logger.error("ai.analysis.failed \(reason, privacy: .public)")
        case .unexpectedError(let reason):
            logger.error("ai.unexpected \(reason, privacy: .public)")
        }
    }
}
