import SwiftUI
import SwiftData
import UIKit

@main
struct VibeCheckApp: App {
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer: Bool = false
    @AppStorage(UserProfileStorage.hasCompletedSetupKey) private var hasCompletedPersonalization: Bool = false
    private let sharedModelContainer: ModelContainer = {
        do {
            let schema = Schema([ScanResult.self])
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            try FileManager.default.createDirectory(
                at: appSupportURL,
                withIntermediateDirectories: true
            )

            let storeURL = appSupportURL.appendingPathComponent("default.store")
            let configuration = ModelConfiguration(url: storeURL)
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            assertionFailure("Failed to create persistent ModelContainer: \(error)")
            do {
                return try ModelContainer(
                    for: ScanResult.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                fatalError("Unable to create in-memory ModelContainer fallback: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .fullScreenCover(
                    isPresented: Binding(
                        get: { !hasAcceptedDisclaimer },
                        set: { _ in }
                    )
                ) {
                    DisclaimerView()
                }
                .fullScreenCover(
                    isPresented: Binding(
                        get: {
                            hasAcceptedDisclaimer &&
                            !hasCompletedPersonalization
                        },
                        set: { _ in }
                    )
                ) {
                    PersonalizationView()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

private struct PersonalizationView: View {
    @State private var selectedGender: UserGender = .notSet
    @State private var birthDate: Date = .now
    @State private var weightText: String = ""
    @FocusState private var focusedField: Field?
    private let profileRepository = ProfileRepository()

    private enum Field {
        case weight
    }

    private var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
    }

    private var ageIsValid: Bool {
        (0...120).contains(age)
    }

    private var canContinue: Bool {
        selectedGender != .notSet && ageIsValid
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("About You")
                                .font(.largeTitle.weight(.semibold))
                            Text("Add your basics once so AI uses accurate reference ranges.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 4)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Gender")
                                .font(.subheadline.weight(.semibold))

                            Menu {
                                Button("Select") {
                                    selectedGender = .notSet
                                }
                                ForEach(UserGender.allCases.filter { $0 != .notSet }) { gender in
                                    Button(gender.title) {
                                        selectedGender = gender
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedGender == .notSet ? "Select" : selectedGender.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 52)
                                .padding(.horizontal, 12)
                                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .appSectionCard(title: "Basics")

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Date of birth")
                                .font(.subheadline.weight(.semibold))

                            DatePicker(
                                "Date of birth",
                                selection: $birthDate,
                                in: ...Date.now,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 52)
                            .padding(.horizontal, 12)
                            .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .appSectionCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Weight (optional)")
                                .font(.subheadline.weight(.semibold))
                            TextField("e.g. 70.5", text: $weightText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .weight)
                                .textFieldStyle(.plain)
                                .frame(minHeight: 52)
                                .padding(.horizontal, 12)
                                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .appSectionCard()

                        if !ageIsValid {
                            Text("Age must be between 0 and 120.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, AppDesign.contentPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .navigationTitle("About You")
                .navigationBarTitleDisplayMode(.large)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                saveAndContinue()
            } label: {
                Text("Continue")
                    .font(.headline.weight(.semibold))
                    .appPrimaryButtonSurface(disabled: !canContinue)
                    .padding(.horizontal, AppDesign.contentPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
            .background(.ultraThinMaterial)
        }
        .tint(AppDesign.accent)
        .interactiveDismissDisabled(true)
        .onAppear {
            SecureProfileStore.migrateFromLegacyAppStorageIfNeeded()
            let stored = SecureProfileStore.loadProfile()
            selectedGender = stored.gender
            if let storedBirthDate = stored.birthDate {
                birthDate = storedBirthDate
            }
            if let storedWeight = stored.weightKg {
                weightText = String(format: "%.1f", storedWeight)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
    }

    private func saveAndContinue() {
        SecureProfileStore.saveProfile(
            UserProfile(
                gender: selectedGender,
                birthDate: birthDate,
                weightKg: parseWeightKg(weightText)
            )
        )
        AppHaptics.subtle()
        profileRepository.setHasCompletedSetup(true)
    }

    private func parseWeightKg(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }
}
