import SwiftUI

struct ProfileView: View {
    let onOpenPaywall: () -> Void
    let onDeleteHealthData: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedGender: UserGender = .female
    @State private var birthDate: Date = .now
    @State private var weightText: String = ""
    @State private var premiumFill = false
    @State private var displayedAge: Int = 0
    @State private var showDataPolicy = false
    @State private var showDeleteAlert = false
    @State private var consentStatus = ConsentStatus(isGranted: false, version: 0, timestamp: nil)

    private let profileRepository = ProfileRepository()

    private var profile: UserProfile {
        UserProfile(
            gender: selectedGender,
            birthDate: birthDate,
            weightKg: parseWeightKg(weightText)
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                profileDataCard
                actionsCard
                privacyCard
            }
            .padding(AppDesign.contentPadding)
        }
        .padding(.horizontal, 4)
        .tint(AppDesign.accent)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let stored = profileRepository.loadProfile()
            selectedGender = stored.gender == .notSet ? .female : stored.gender
            if let storedBirthDate = stored.birthDate {
                birthDate = storedBirthDate
            }
            if let storedWeight = stored.weightKg {
                weightText = String(format: "%.1f", storedWeight)
            }
            if let age = stored.age {
                displayedAge = age
            }
            consentStatus = profileRepository.loadConsent()
        }
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showDataPolicy) {
            DataPolicyView()
        }
        .alert("Delete all health data?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                onDeleteHealthData()
                selectedGender = .female
                birthDate = .now
                weightText = ""
                displayedAge = 0
                consentStatus = profileRepository.loadConsent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes profile data and all saved scan history from this device.")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppDesign.accent.opacity(0.18), Color.blue.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(AppDesign.accent)
                }
                .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile")
                        .font(.title2.weight(.semibold))
                    Text("Personalized health context")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        statusPill(icon: "lock.shield", text: consentStatus.isValidForCurrentAppVersion ? "Consent Active" : "Consent Needed", tint: consentStatus.isValidForCurrentAppVersion ? AppDesign.success : AppDesign.warning)
                        if profile.age != nil {
                            statusPill(icon: "calendar", text: "Age \(displayedAge)", tint: AppDesign.accent)
                                .contentTransition(.numericText(value: Double(displayedAge)))
                        }
                    }
                }
                Spacer()
            }

            Text("These values help AI choose the correct reference ranges.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appSectionCard()
        .onAppear {
            if let age = profile.age { displayedAge = age }
        }
        .onChange(of: profile.age) { _, newAge in
            guard let newAge else { return }
            withAnimation(.easeInOut(duration: AppMotion.medium)) {
                displayedAge = newAge
            }
        }
    }

    private var profileDataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Health Data")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("Used for AI ranges")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ProfileFieldShell(icon: "person.text.rectangle", title: "Gender") {
                    Menu {
                        ForEach(UserGender.allCases.filter { $0 != .notSet }) { gender in
                            Button(gender.title) { selectedGender = gender }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedGender.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(selectedGender == .notSet ? .secondary : AppDesign.accent)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AppDesign.accent.opacity(0.08), in: Capsule())
                    }
                }

                ProfileFieldShell(icon: "calendar", title: "Date of birth") {
                    DatePicker(
                        "Date of birth",
                        selection: $birthDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.38), in: Capsule())
                }

                ProfileFieldShell(icon: "scalemass", title: "Weight") {
                    HStack(spacing: 8) {
                        TextField("Optional", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 86)
                        Text("kg")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.38), in: Capsule())
                }
            }
        }
        .appSectionCard()
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button {
                profileRepository.saveProfile(profile)
                AppHaptics.subtle()
            } label: {
                Label("Save Profile", systemImage: "checkmark.circle")
                    .font(.headline.weight(.semibold))
                    .appPrimaryButtonSurface(disabled: selectedGender == .notSet)
            }
            .disabled(selectedGender == .notSet)
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: AppMotion.medium)) {
                    premiumFill = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + AppMotion.fast) {
                    AppHaptics.subtle()
                    onOpenPaywall()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + AppMotion.slow) {
                    withAnimation(.easeInOut(duration: AppMotion.medium)) {
                        premiumFill = false
                    }
                }
            } label: {
                PremiumOutlineButton(fillProgress: premiumFill ? 1 : 0)
            }
            .buttonStyle(.plain)
        }
        .appSectionCard(title: "Actions")
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Privacy")
                    .font(.headline.weight(.semibold))
                Spacer()
                statusPill(
                    icon: consentStatus.isValidForCurrentAppVersion ? "checkmark.shield" : "exclamationmark.shield",
                    text: consentStatus.isValidForCurrentAppVersion ? "Protected" : "Attention",
                    tint: consentStatus.isValidForCurrentAppVersion ? AppDesign.success : AppDesign.warning
                )
            }

            Text("Health data is stored locally on this device. You can review the policy or delete all saved data at any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(consentBadgeText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 8) {
                Button {
                    showDataPolicy = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(AppDesign.accent)
                        Text("View Data Policy")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete All Health Data")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .appSectionCard()
    }

    private func parseWeightKg(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var consentBadgeText: String {
        if consentStatus.isValidForCurrentAppVersion {
            if let ts = consentStatus.timestamp {
                return "Consent v\(consentStatus.version) on \(ts.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Consent v\(consentStatus.version)"
        }
        return "Consent required before next scan"
    }

    @ViewBuilder
    private func statusPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1), in: Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ProfileFieldShell<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    init(icon: String, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill({
                        if #available(iOS 26.0, *) { return Color.white.opacity(0.28) }
                        return Color.white.opacity(0.52)
                    }())
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ({
                if #available(iOS 26.0, *) { return Color.white.opacity(0.48) }
                return Color.white.opacity(0.70)
            })(),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.3), lineWidth: 1)
        )
    }
}

private struct DataPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Data Policy")
                        .font(.title2.weight(.semibold))
                    Text("We process report images and selected profile context (gender, age group, optional weight band) to generate analysis.")
                    Text("Saved history remains on your device in local storage.")
                    Text("Consent version: v\(UserProfileStorage.currentConsentVersion).")
                    Text("You can delete all health data at any time from Profile.")
                    Text("This app does not replace professional medical advice.")
                }
                .font(.body)
                .padding(20)
            }
            .navigationTitle("Privacy & Retention")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct PremiumOutlineButton: View {
    let fillProgress: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        Label("Premium", systemImage: "sparkles")
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(fillProgress > 0.92 ? .white : AppDesign.accent)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: AppDesign.buttonRadius, style: .continuous)
                        .fill(.white.opacity(0.18))

                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: AppDesign.buttonRadius, style: .continuous)
                            .fill(AppDesign.accent)
                            .frame(width: proxy.size.width * fillProgress)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: AppDesign.buttonRadius, style: .continuous))
                    .animation(.easeInOut(duration: AppMotion.medium), value: fillProgress)

                    if #available(iOS 26.0, *) {
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.22), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .offset(x: shimmer ? 180 : -180)
                        .animation(.linear(duration: 2.8).repeatForever(autoreverses: false), value: shimmer)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.buttonRadius, style: .continuous)
                    .stroke(AppDesign.accent.opacity(0.9), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppDesign.buttonRadius, style: .continuous))
            .onAppear {
                shimmer = !reduceMotion
            }
    }
}

struct ProfileCardHighlight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.14), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .offset(x: phase ? 140 : -140)
        .animation(.linear(duration: 5.8).repeatForever(autoreverses: false), value: phase)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
        .onAppear { phase = !reduceMotion }
    }
}
