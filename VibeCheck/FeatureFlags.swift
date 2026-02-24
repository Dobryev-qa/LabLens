import Foundation
import CoreGraphics

enum FeatureFlags {
    static var apiBaseURL: String {
        stringValue(for: "API_BASE_URL") ?? "http://127.0.0.1:8080"
    }

    static var apiAuthToken: String? {
        stringValue(for: "API_AUTH_TOKEN")
    }

    static var aiImageCompressionQuality: CGFloat {
        let value = doubleValue(for: "AI_IMAGE_COMPRESSION_QUALITY") ?? 0.38
        return CGFloat(min(max(value, 0.2), 0.95))
    }

    static var aiImageMaxDimension: CGFloat {
        let value = doubleValue(for: "AI_IMAGE_MAX_DIMENSION") ?? 900
        return CGFloat(max(300, value))
    }

    private static func stringValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") {
            // Treat unresolved Xcode build setting placeholders as missing values.
            return nil
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func doubleValue(for key: String) -> Double? {
        if let number = Bundle.main.object(forInfoDictionaryKey: key) as? NSNumber {
            return number.doubleValue
        }
        if let text = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            return Double(text)
        }
        return nil
    }
}
