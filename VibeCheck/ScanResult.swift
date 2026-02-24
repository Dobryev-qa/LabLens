import Foundation
import SwiftData

struct SavedBiomarker: Codable, Hashable, Identifiable {
    var id = UUID()
    let name: String
    let value: String
    let status: String
    let explanation: String
}

struct SavedRecommendation: Codable, Hashable, Identifiable {
    var id = UUID()
    let name: String
    let protocolText: String
    let reason: String
}

@Model
final class ScanResult {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var summary: String
    var biomarkers: [SavedBiomarker]
    var recommendations: [SavedRecommendation]

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        summary: String,
        biomarkers: [SavedBiomarker],
        recommendations: [SavedRecommendation]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.summary = summary
        self.biomarkers = biomarkers
        self.recommendations = recommendations
    }
}
