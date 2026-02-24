//
//  VibeCheckTests.swift
//  VibeCheckTests
//
//  Created by Dmitrii on 17.02.2026.
//

import Testing
@testable import VibeCheck

struct VibeCheckTests {
    @Test func userProfileIsCompleteOnlyWithGenderAndBirthDate() async throws {
        let incompleteA = UserProfile(gender: .notSet, birthDate: .now, weightKg: nil)
        let incompleteB = UserProfile(gender: .male, birthDate: nil, weightKg: nil)
        let complete = UserProfile(gender: .female, birthDate: .now, weightKg: nil)

        #expect(incompleteA.isComplete == false)
        #expect(incompleteB.isComplete == false)
        #expect(complete.isComplete == true)
    }

    @Test func userProfilePromptUsesBandsInsteadOfExactValues() async throws {
        let birthDate = Calendar.current.date(byAdding: .year, value: -35, to: .now)!
        let profile = UserProfile(gender: .male, birthDate: birthDate, weightKg: 76.4)

        #expect(profile.promptLine.contains("age group"))
        #expect(profile.promptLine.contains("30-39"))
        #expect(profile.promptLine.contains("weight band 70-79 kg"))
        #expect(profile.promptLine.contains("man"))
    }

    @Test func userProfilePromptHandlesUnknownAge() async throws {
        let profile = UserProfile(gender: .female, birthDate: nil, weightKg: nil)
        #expect(profile.promptLine.contains("unknown age"))
    }

    @Test func genderPromptTextMappings() async throws {
        #expect(UserGender.male.promptText == "man")
        #expect(UserGender.female.promptText == "woman")
        #expect(UserGender.nonBinary.promptText == "non-binary adult")
        #expect(UserGender.preferNotToSay.promptText == "adult")
    }

    @Test func consentIsVersionedAndValidForCurrentVersion() async throws {
        let suiteName = "VibeCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let repo = ProfileRepository(defaults: defaults)
        let before = repo.loadConsent()
        #expect(before.isValidForCurrentAppVersion == false)

        repo.grantConsent(now: Date(timeIntervalSince1970: 1_700_000_000))
        let after = repo.loadConsent()

        #expect(after.isGranted == true)
        #expect(after.version == UserProfileStorage.currentConsentVersion)
        #expect(after.timestamp != nil)
        #expect(after.isValidForCurrentAppVersion == true)
    }

    @Test func clearingHealthFlagsResetsConsentAndPromptState() async throws {
        let suiteName = "VibeCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let repo = ProfileRepository(defaults: defaults)
        repo.setDidPromptBeforeScan(true)
        repo.setHasCompletedSetup(true)
        repo.grantConsent()

        repo.clearAllHealthDataFlags()

        #expect(repo.didPromptBeforeScan() == false)
        #expect(repo.hasCompletedSetup() == false)
        #expect(repo.loadConsent().isGranted == false)
    }

    @Test func repositoryStoresCompletedSetupFlag() async throws {
        let suiteName = "VibeCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let repo = ProfileRepository(defaults: defaults)
        #expect(repo.hasCompletedSetup() == false)
        repo.setHasCompletedSetup(true)
        #expect(repo.hasCompletedSetup() == true)
    }
}
