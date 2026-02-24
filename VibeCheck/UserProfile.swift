import Foundation

enum UserGender: String, CaseIterable, Identifiable {
    case notSet = "not_set"
    case male
    case female
    case nonBinary = "non_binary"
    case preferNotToSay = "prefer_not_to_say"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notSet: return "Select"
        case .male: return "Male"
        case .female: return "Female"
        case .nonBinary: return "Non-binary"
        case .preferNotToSay: return "Prefer not to say"
        }
    }

    var promptText: String {
        switch self {
        case .male: return "man"
        case .female: return "woman"
        case .nonBinary: return "non-binary adult"
        case .preferNotToSay: return "adult"
        case .notSet: return "person"
        }
    }
}

struct UserProfile {
    var gender: UserGender
    var birthDate: Date?
    var weightKg: Double?

    var age: Int? {
        guard let birthDate else { return nil }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year
        guard let years, years >= 0 else { return nil }
        return years
    }

    var isComplete: Bool {
        gender != .notSet && birthDate != nil
    }

    var promptLine: String {
        let ageBandText = ageBand
        let weightBandText = weightBand.map { ", weight band \($0)" } ?? ""
        return "Analyze this report for a \(gender.promptText), age group \(ageBandText)\(weightBandText)."
    }

    var ageBand: String {
        guard let age else { return "unknown age" }
        switch age {
        case 0...17: return "under 18"
        case 18...29: return "18-29"
        case 30...39: return "30-39"
        case 40...49: return "40-49"
        case 50...59: return "50-59"
        case 60...69: return "60-69"
        case 70...120: return "70+"
        default: return "unknown age"
        }
    }

    var weightBand: String? {
        guard let weightKg else { return nil }
        let bucket = Int(weightKg / 10.0) * 10
        return "\(bucket)-\(bucket + 9) kg"
    }
}

enum UserProfileStorage {
    static let currentConsentVersion = 1

    static let hasCompletedSetupKey = "hasCompletedPersonalization"
    static let genderKey = "userGender"
    static let birthDateTimestampKey = "userBirthDateTimestamp"
    static let weightKgKey = "userWeightKg"
    static let didPromptBeforeScanKey = "didPromptProfileBeforeScan"
    static let hasProcessingConsentKey = "hasProcessingConsent"
    static let consentVersionKey = "processingConsentVersion"
    static let consentTimestampKey = "processingConsentTimestamp"
}
