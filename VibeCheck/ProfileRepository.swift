import Foundation

struct ConsentStatus {
    let isGranted: Bool
    let version: Int
    let timestamp: Date?

    var isValidForCurrentAppVersion: Bool {
        isGranted && version == UserProfileStorage.currentConsentVersion
    }
}

struct ProfileRepository {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func migrateLegacyProfileIfNeeded() {
        SecureProfileStore.migrateFromLegacyAppStorageIfNeeded(defaults: defaults)
    }

    func loadProfile() -> UserProfile {
        SecureProfileStore.loadProfile()
    }

    func saveProfile(_ profile: UserProfile) {
        SecureProfileStore.saveProfile(profile)
    }

    func loadConsent() -> ConsentStatus {
        let granted = defaults.bool(forKey: UserProfileStorage.hasProcessingConsentKey)
        let version = defaults.integer(forKey: UserProfileStorage.consentVersionKey)
        let ts = defaults.double(forKey: UserProfileStorage.consentTimestampKey)
        let date = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        return ConsentStatus(isGranted: granted, version: version, timestamp: date)
    }

    func grantConsent(now: Date = .now) {
        defaults.set(true, forKey: UserProfileStorage.hasProcessingConsentKey)
        defaults.set(UserProfileStorage.currentConsentVersion, forKey: UserProfileStorage.consentVersionKey)
        defaults.set(now.timeIntervalSince1970, forKey: UserProfileStorage.consentTimestampKey)
    }

    func revokeConsent() {
        defaults.set(false, forKey: UserProfileStorage.hasProcessingConsentKey)
        defaults.removeObject(forKey: UserProfileStorage.consentVersionKey)
        defaults.removeObject(forKey: UserProfileStorage.consentTimestampKey)
    }

    func didPromptBeforeScan() -> Bool {
        defaults.bool(forKey: UserProfileStorage.didPromptBeforeScanKey)
    }

    func setDidPromptBeforeScan(_ value: Bool) {
        defaults.set(value, forKey: UserProfileStorage.didPromptBeforeScanKey)
    }

    func hasCompletedSetup() -> Bool {
        defaults.bool(forKey: UserProfileStorage.hasCompletedSetupKey)
    }

    func setHasCompletedSetup(_ value: Bool) {
        defaults.set(value, forKey: UserProfileStorage.hasCompletedSetupKey)
    }

    func clearAllHealthDataFlags() {
        defaults.removeObject(forKey: UserProfileStorage.didPromptBeforeScanKey)
        defaults.removeObject(forKey: UserProfileStorage.hasCompletedSetupKey)
        defaults.removeObject(forKey: UserProfileStorage.genderKey)
        defaults.removeObject(forKey: UserProfileStorage.birthDateTimestampKey)
        defaults.removeObject(forKey: UserProfileStorage.weightKgKey)
        revokeConsent()
    }
}
