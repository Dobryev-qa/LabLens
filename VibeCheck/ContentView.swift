import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SwiftData
import OSLog

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scanViewModel = ScanViewModel()
    @State private var selectedTab: Int = AppTab.history.rawValue
    @State private var showImageSourceDialog = false
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var showProfilePromptAlert = false
    @State private var showConsentAlert = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var showPaywall = false
    @State private var activeScanTask: Task<Void, Never>?
    @State private var profile: UserProfile = .init(gender: .notSet, birthDate: nil, weightKg: nil)
    @State private var hasProcessingConsent = false
    @State private var didPromptBeforeScan = false

    private let profileRepository = ProfileRepository()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VibeCheck", category: "ContentView")

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground()
                    .ignoresSafeArea()

                TabView(selection: $selectedTab) {
                    HistoryView()
                        .tabItem {
                            Label(AppTab.history.title, systemImage: AppTab.history.icon)
                        }
                        .tag(AppTab.history.rawValue)

                    ScanView(
                        result: scanViewModel.analysisResult,
                        isBusy: scanViewModel.isAnalyzing || scanViewModel.isPreparingDocument,
                        canRetryLastInput: scanViewModel.hasCachedRetryInput,
                        cachedRetryUses: scanViewModel.cachedRetryUses,
                        onStartScan: { handleScanTap() },
                        onRescan: { handleRescanTap() }
                    )
                        .tabItem {
                            Label(AppTab.scan.title, systemImage: AppTab.scan.icon)
                        }
                        .tag(AppTab.scan.rawValue)

                    ProfileView(
                        onOpenPaywall: {
                            showPaywall = true
                        },
                        onDeleteHealthData: {
                            deleteAllHealthData()
                        }
                    )
                    .tabItem {
                        Label(AppTab.profile.title, systemImage: AppTab.profile.icon)
                    }
                        .tag(AppTab.profile.rawValue)
                }
                .tint(AppDesign.accent)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)

                if scanViewModel.isAnalyzing || scanViewModel.isPreparingDocument {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.86)
                        .ignoresSafeArea()

                    AnalyzingScannerView(
                        previewImage: scanViewModel.analyzingPreviewImage,
                        loadingMessage: scanViewModel.loadingMessage,
                        onCancel: { cancelScanFlow() }
                    )
                    .frame(maxWidth: 380)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .animation(.easeInOut(duration: AppMotion.slow), value: scanViewModel.isAnalyzing)
        }
        .confirmationDialog("Start Scan", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
            Button("Take Photo") {
                imageSourceType = .camera
                showImagePicker = true
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            Button("Choose from Library") {
                imageSourceType = .photoLibrary
                showImagePicker = true
            }

            Button("Choose Document/PDF") {
                showDocumentPicker = true
            }

            Button("Cancel", role: .cancel) {}
        }
        .alert("Complete profile for better accuracy?", isPresented: $showProfilePromptAlert) {
            Button("Fill Profile") {
                selectedTab = AppTab.profile.rawValue
            }
            Button("Continue Anyway") {
                showImageSourceDialog = true
            }
        } message: {
            Text("Add gender and date of birth once so AI can use the right reference ranges.")
        }
        .alert("Allow health data processing?", isPresented: $showConsentAlert) {
            Button("Allow") {
                profileRepository.grantConsent()
                let consent = profileRepository.loadConsent()
                hasProcessingConsent = consent.isValidForCurrentAppVersion
                showImageSourceDialog = true
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To analyze reports, the app sends report images and selected profile context to AI processing. You can delete all health data anytime in Profile.")
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: imageSourceType) { image in
                guard let image else { return }
                startScanTask {
                    await scanViewModel.analyze(
                        images: [image],
                        profile: currentProfile.isComplete ? currentProfile : nil,
                        modelContext: modelContext,
                        reduceMotion: reduceMotion
                    )
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                startScanTask {
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if hasAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    await scanViewModel.preparePDFAndAnalyze(
                        url: url,
                        profile: currentProfile.isComplete ? currentProfile : nil,
                        modelContext: modelContext,
                        reduceMotion: reduceMotion
                    )
                }
            case .failure(let error):
                logger.error("pdf_picker_failed \(error.localizedDescription, privacy: .public)")
            }
        }
        .alert(item: $scanViewModel.userFacingAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView {
                showPaywall = false
            }
        }
        .onAppear {
            profileRepository.migrateLegacyProfileIfNeeded()
            refreshStateFromRepository()
        }
        .onChange(of: selectedTab) { _, _ in
            refreshStateFromRepository()
        }
        .onDisappear {
            activeScanTask?.cancel()
            activeScanTask = nil
            scanViewModel.stopTransientWork()
        }
    }

    private func handleScanTap() {
        beginScanFlow(clearExistingResult: false)
    }

    private func handleRescanTap() {
        if shouldRetryCachedInputSilently {
            AppHaptics.subtle()
            startScanTask {
                _ = await scanViewModel.retryLastAnalyze(
                    modelContext: modelContext,
                    reduceMotion: reduceMotion
                )
            }
            return
        }
        beginScanFlow(clearExistingResult: true)
    }

    private func beginScanFlow(clearExistingResult: Bool) {
        AppHaptics.subtle()
        if clearExistingResult {
            scanViewModel.clearResult()
            scanViewModel.clearCachedRetryInput()
        }
        refreshStateFromRepository()
        selectedTab = AppTab.scan.rawValue
        guard hasProcessingConsent else {
            showConsentAlert = true
            return
        }
        if !currentProfile.isComplete && !didPromptBeforeScan {
            didPromptBeforeScan = true
            profileRepository.setDidPromptBeforeScan(true)
            showProfilePromptAlert = true
        } else {
            showImageSourceDialog = true
        }
    }

    private func startScanTask(_ operation: @escaping @Sendable () async -> Void) {
        activeScanTask?.cancel()
        activeScanTask = Task {
            await operation()
            await MainActor.run {
                activeScanTask = nil
            }
        }
    }

    private func cancelScanFlow() {
        activeScanTask?.cancel()
        activeScanTask = nil
        scanViewModel.cancelCurrentOperation()
    }

    private var currentProfile: UserProfile { profile }

    private func refreshStateFromRepository() {
        profile = profileRepository.loadProfile()
        let consent = profileRepository.loadConsent()
        hasProcessingConsent = consent.isValidForCurrentAppVersion
        didPromptBeforeScan = profileRepository.didPromptBeforeScan()
    }

    private func deleteAllHealthData() {
        SecureProfileStore.clearProfile()
        profile = .init(gender: .notSet, birthDate: nil, weightKg: nil)
        scanViewModel.clearResult()
        scanViewModel.clearCachedRetryInput()
        didPromptBeforeScan = false
        hasProcessingConsent = false
        profileRepository.clearAllHealthDataFlags()

        do {
            let scans = try modelContext.fetch(FetchDescriptor<ScanResult>())
            scans.forEach(modelContext.delete)
            try modelContext.save()
        } catch {
            logger.error("data_wipe_failed \(error.localizedDescription, privacy: .public)")
        }
    }

    private var shouldRetryCachedInputSilently: Bool {
        guard let result = scanViewModel.analysisResult else { return false }
        guard scanViewModel.hasCachedRetryInput else { return false }
        guard scanViewModel.cachedRetryUses == 0 else { return false }
        let summary = result.summary.lowercased()
        return summary.contains("could not be completed")
            || summary.contains("backend is unreachable")
            || summary.contains("could not connect to the server")
            || summary.contains("timed out")
            || summary.contains("network is unavailable")
            || summary.contains("unauthorized")
            || summary.contains("forbidden")
            || summary.contains("not configured")
    }

}
