import Foundation
import Security

struct SecureProfileStore {
    private static let service = "com.vibecheck.profile"
    private static let account = "user_profile_v1"

    private struct StoredProfile: Codable {
        let genderRawValue: String
        let birthDateTimestamp: Double
        let weightKg: Double
    }

    static func loadProfile() -> UserProfile {
        guard let data = readKeychainData() else {
            return .init(gender: .notSet, birthDate: nil, weightKg: nil)
        }

        guard let decoded = try? JSONDecoder().decode(StoredProfile.self, from: data) else {
            return .init(gender: .notSet, birthDate: nil, weightKg: nil)
        }

        let gender = UserGender(rawValue: decoded.genderRawValue) ?? .notSet
        let birthDate = decoded.birthDateTimestamp > 0 ? Date(timeIntervalSince1970: decoded.birthDateTimestamp) : nil
        let weight = decoded.weightKg > 0 ? decoded.weightKg : nil
        return .init(gender: gender, birthDate: birthDate, weightKg: weight)
    }

    static func saveProfile(_ profile: UserProfile) {
        let payload = StoredProfile(
            genderRawValue: profile.gender.rawValue,
            birthDateTimestamp: profile.birthDate?.timeIntervalSince1970 ?? 0,
            weightKg: profile.weightKg ?? 0
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        upsertKeychainData(data)
    }

    static func clearProfile() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func migrateFromLegacyAppStorageIfNeeded(defaults: UserDefaults = .standard) {
        guard readKeychainData() == nil else { return }

        let genderRaw = defaults.string(forKey: UserProfileStorage.genderKey) ?? UserGender.notSet.rawValue
        let birthTimestamp = defaults.double(forKey: UserProfileStorage.birthDateTimestampKey)
        let weight = defaults.double(forKey: UserProfileStorage.weightKgKey)

        let hasLegacyData = genderRaw != UserGender.notSet.rawValue || birthTimestamp > 0 || weight > 0
        guard hasLegacyData else { return }

        let migrated = UserProfile(
            gender: UserGender(rawValue: genderRaw) ?? .notSet,
            birthDate: birthTimestamp > 0 ? Date(timeIntervalSince1970: birthTimestamp) : nil,
            weightKg: weight > 0 ? weight : nil
        )
        saveProfile(migrated)

        defaults.removeObject(forKey: UserProfileStorage.genderKey)
        defaults.removeObject(forKey: UserProfileStorage.birthDateTimestampKey)
        defaults.removeObject(forKey: UserProfileStorage.weightKgKey)
    }

    private static func readKeychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func upsertKeychainData(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        SecItemAdd(insertQuery as CFDictionary, nil)
    }
}
