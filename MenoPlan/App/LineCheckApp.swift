import SwiftData
import SwiftUI
import TipKit
import FirebaseAnalytics
import FirebaseCore
import RevenueCat
import StoreKit
import UserNotifications

final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

final class FirebaseAppDelegate: NSObject, UIApplicationDelegate {
    private let notificationPresentationDelegate = NotificationPresentationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Local notification previews are triggered while Settings is still
        // open. Without this delegate, iOS silently delivers them to the app
        // instead of showing the banner the developer is trying to inspect.
        UNUserNotificationCenter.current().delegate = notificationPresentationDelegate
        MetaAppEventsService.shared.prepare(launchOptions: launchOptions)
        Task { @MainActor in
            HealthKitBackgroundSyncCoordinator.shared.appDidFinishLaunching()
        }
        #if DEBUG
        // Debug builds never touch the production RevenueCat/Firebase projects,
        // so local testing and simulator runs stop polluting production stats.
        // Use PurchaseService.setDebugPremium(_:settings:) to simulate Pro locally.
        print("Debug build: RevenueCat and Firebase are not configured, so testing doesn't hit production analytics/revenue data.")
        #else
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
           apiKey.isEmpty == false,
           apiKey.contains("$(") == false {
            Purchases.configure(withAPIKey: apiKey)
        }
        // TODO: add MenoPlan's own GoogleService-Info.plist. Until then
        // Firebase stays unconfigured rather than crashing on launch.
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return true }
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        Analytics.logEvent("linecheck_app_launch", parameters: [
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        ])
        #endif
        return true
    }

}

/// Centralizes the DEBUG-guard for Firebase Analytics so call sites across
/// the app don't each need to repeat it - matches FirebaseAppDelegate's own
/// choice not to configure Firebase in Debug builds, so logging here would
/// otherwise hit an unconfigured SDK.
enum AppAnalytics {
    static func log(_ name: String, _ parameters: [String: Any]? = nil) {
        #if !DEBUG
        Analytics.logEvent(name, parameters: parameters)
        #endif
    }
}

@main
struct LineCheckApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var firebaseDelegate
    @State private var appState = AppState()

    private let storageFallbackMessage: String?
    var sharedModelContainer: ModelContainer

    init() {
        let store = Self.makeModelContainer()
        sharedModelContainer = store.container
        Task { @MainActor in
            HealthKitBackgroundSyncCoordinator.shared.configure(modelContainer: store.container)
        }
        // Scans saved before images were mirrored to iCloud only exist as local
        // files, so lift them into the store where CloudKit can carry them to
        // the user's other devices.
        let container = store.container
        Task.detached(priority: .utility) {
            let imageSync = ScanImageSyncService(modelContainer: container)
            await imageSync.backfill()
            await imageSync.pruneOrphanedFiles()
        }
        storageFallbackMessage = store.fallbackMessage
        TipService.configure()
        Self.applyAppFontToNavigationBars()
    }

    private static func applyAppFontToNavigationBars() {
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: AppFont.uiFont(size: 17, weight: .bold)]
        bar.largeTitleTextAttributes = [.font: AppFont.uiFont(size: 34, weight: .bold)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: AppFont.uiFont(size: 17, weight: .medium)], for: .normal)
    }

    /// Every synced model, in one place so the app's store and the Debug
    /// iCloud schema tool can't drift apart.
    nonisolated static let persistentModelTypes: [any PersistentModel.Type] = [
        Scan.self, ScanComparison.self, CycleRecord.self, PeriodEvent.self,
        DailyFertilityLog.self, DailyHealthMetrics.self, NoticedSignal.self, Reminder.self,
        UserSettings.self, AssistantConversation.self, WeeklyLunaUpdate.self
    ]
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.menocheck.app"

    private static func makeModelContainer() -> (container: ModelContainer, fallbackMessage: String?) {
        let schema = Schema(persistentModelTypes)
        // Preserve SwiftData's existing default store identity so an update opens
        // the user's current database and mirrors those records into private iCloud.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // Core Data's CloudKit exporter is an OS-managed background service.
        // It is not needed for local Debug work and has been crashing/quarantining
        // Debug launches while it repeatedly tries to register export tasks. Keep
        // the production configuration intact, where real iCloud sync matters.
        let configuration: ModelConfiguration
        #if DEBUG
        configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        #else
        configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: isRunningTests ? .none : .private(cloudKitContainerIdentifier)
        )
        #endif
        do {
            return (try ModelContainer(for: schema, configurations: [configuration]), nil)
        } catch {
            assertionFailure("Failed to load persistent SwiftData store: \(error)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: schema, configurations: [fallback])
            return (container, "MenoPlan could not open saved local storage, so history changes in this session may not persist.")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(.light)
                .environment(\.colorScheme, .light)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        MetaAppEventsService.shared.activateIfAuthorized()
                    } else if phase == .background {
                        MetaAppEventsService.shared.didEnterBackground()
                    }
                }
                .task {
                    guard let storageFallbackMessage else { return }
                    appState.storageWarning = storageFallbackMessage
                }
        }
    }
}

@Observable
@MainActor
final class AppState {
    var selectedTab: AppTab = .home
    var activeFlow: ScanFlow?
    var toast: String? {
        didSet {
            toastDismissalTask?.cancel()
            guard let toast else { return }
            toastDismissalTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, self?.toast == toast else { return }
                self?.toast = nil
            }
        }
    }
    @ObservationIgnored private var toastDismissalTask: Task<Void, Never>?
    var settings: UserSettings?
    var onboardingResetID = UUID()
    var isTabBarHidden = false
    var showPremium = false
    /// Set alongside `showPremium = true` so the paywall can report why it
    /// was shown; read once by PremiumView.task and cleared so a later open
    /// without an explicit source doesn't inherit a stale value.
    var paywallSource: String?
    var historyRoute: LunaHistoryRoute?
    var pendingLunaPrompt: String?
    var calendarSetupRequest: LunaCalendarSetupRequest?
    /// Set alongside `selectedTab = .calendar` to deep-link straight into
    /// Test Trends - CalendarView is recreated fresh on every tab switch, so
    /// this is the only way another tab can reach its trends sheet.
    var showTrendsRequested = false
    var storageWarning: String?
    var postScanPrompt: PostScanPrompt?
    let interstitialAds = InterstitialAdService()
    let adConsent = AdConsentService.shared

    func startScan(testType: TestType, mode: AnalysisMode? = nil, testDate: Date? = nil) {
        let resolvedMode = mode ?? settings?.preferredAnalysisMode ?? .aiQuickCheck
        let flow = ScanFlow(testType: testType, mode: resolvedMode)
        flow.format = .unspecified
        if let testDate {
            flow.testDate = testDate
            flow.usesCustomTestDate = true
        }
        activeFlow = flow
        AppAnalytics.log("linecheck_scan_started", [
            "test_type": testType.rawValue,
            "mode": resolvedMode.rawValue
        ])
    }
}

enum LunaHistoryRoute: Equatable {
    case recent, compare
}

enum LunaCalendarSetupRequest: Equatable {
    case ovulation
}

enum PostScanPrompt {
    case rating
    case notifications
    /// After a first scan by someone who skipped setup.
    case setupCycle
}

enum AppTab: String, CaseIterable, Identifiable {
    case home, history, calendar, assistant, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .assistant: "Luna"
        default: rawValue.capitalized
        }
    }
    var icon: String {
        switch self {
        case .home: "house"
        case .history: "clock"
        case .calendar: "calendar"
        case .assistant: "bubble.left.and.bubble.right"
        case .settings: "gearshape"
        }
    }
}

@Observable
final class ScanFlow: Identifiable {
    let id = UUID()
    var testType: TestType
    var format: TestFormat = .unspecified
    var testDate: Date = .now
    var usesCustomTestDate = false
    var capturedAt: Date?
    var brandName: String = ""
    var notes: String = ""
    var mode: AnalysisMode
    var image: UIImage?
    var imageWasImported = false
    var importedImageHasBeenCropped = false
    var adjustedImage: UIImage?
    var analysisResult: LineAnalysisResult?
    var localOvulationDiagnostics: LocalOvulationDiagnostics?
    var autoSummary = ""
    /// Short, text-only Luna guidance produced after a Pro or included free
    /// Luna Check. It is deliberately separate from the image analysis result:
    /// it never needs the photo and is safe to render as the explanation.
    var personalisedGuidance: String?
    var step: ScanStep = .mode
    var manualResetToken = 0
    var analysisRequestToken = UUID()
    var suppressCompletionInterstitial = false
    var completedFreeLunaCheck = false
    var pendingResultAction: ResultHeaderAction?
    var persistedScan: Scan?
    /// True when the current analysisResult came from the free on-device
    /// heuristic scan (LocalHeuristicCheckView), not a manual self-report -
    /// distinguishes the two .manualEnhance-mode paths so the result screen
    /// doesn't mislabel a real (if simple) scan as "you selected this
    /// yourself, this wasn't analysed".
    var wasLocallyScanned = false

    init(testType: TestType, mode: AnalysisMode) {
        self.testType = testType
        self.mode = mode
    }

    var effectiveTestDate: Date { usesCustomTestDate ? testDate : (capturedAt ?? .now) }

    /// The image to show/save/export on the result screen. Luna Check always
    /// shows the user's true original — never a processed version they never
    /// actually saw, regardless of what was sent to Luna as evidence.
    /// Manual/local-scan modes still show the user's own deliberate
    /// adjustment, since that's a product of their own work, not something
    /// done invisibly on their behalf.
    var displayImage: UIImage? {
        mode == .aiQuickCheck ? image : (adjustedImage ?? image)
    }

    func markImageCaptured() {
        capturedAt = .now
    }

    func resetForNewCapture(keepingStep step: ScanStep) {
        adjustedImage = nil
        analysisResult = nil
        autoSummary = ""
        personalisedGuidance = nil
        persistedScan = nil
        analysisRequestToken = UUID()
        manualResetToken += 1
        wasLocallyScanned = false
        completedFreeLunaCheck = false
        self.step = step
    }
}

enum ScanStep { case mode, guide, capture, crop, manual, analysing, result }

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Environment(AppState.self) private var appState
    @Query private var settingsQuery: [UserSettings]
    @Query(sort: \CycleRecord.startDate) private var cycleRecords: [CycleRecord]
    @Query(sort: \PeriodEvent.startDate) private var periodEvents: [PeriodEvent]
    @Query(sort: \Scan.createdAt) private var scans: [Scan]
    @Query private var dailyLogs: [DailyFertilityLog]
    @Query private var weeklyLunaUpdates: [WeeklyLunaUpdate]

    var body: some View {
        Group {
            if let settings = currentSettings {
                if settings.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView { action in
                        settings.hasCompletedOnboarding = true
                        if case .skipSetup = action { settings.skippedOnboardingSetupValue = true }
                        try? modelContext.save()
                        AppAnalytics.log(action.isSkipSetup ? "linecheck_onboarding_skipped" : "linecheck_onboarding_completed")
                        if case let .quickTest(testType, mode) = action {
                            appState.startScan(testType: testType, mode: mode)
                        }
                    }
                    .id(appState.onboardingResetID)
                }
            } else {
                BrandedLoadingScreen(title: "Opening MenoPlan")
            }
        }
        .fontDesign(.rounded)
        .tint(Color.lineBlue)
        .background(Color.lineBackground.ignoresSafeArea())
        // `LineType` scales the app's fixed point sizes, but the semantic fonts
        // (.headline, .subheadline, .caption) are driven by Dynamic Type and
        // would otherwise stay at phone size and fall out of proportion. This
        // raises the floor only — a range, not a fixed value — so anyone who has
        // chosen a larger accessibility size still gets it.
        .dynamicTypeSize(LineType.scale > 1 ? .xxLarge... : .xSmall...)
        // Window-level metrics, so the shell can pick a sidebar vs a tab bar.
        // Each shell then re-publishes for its own content area.
        .providesLineLayout()
        .font(.app(.body))
        .task {
            await ensureSettingsLoaded()
        }
        .task(id: reminderSyncKey) {
            guard scenePhase == .active, let settings = currentSettings else { return }
            await ReminderAutomationService.syncCurrentPredictions(settings: settings, context: modelContext)
        }
        .onChange(of: settingsQuery.count) { _, _ in
            mergeDuplicateSettings()
        }
        .task(id: widgetSnapshot) {
            WidgetSnapshotService.publish(widgetSnapshot)
        }
        .onOpenURL { url in
            handleWidgetLink(url)
        }
        .task(id: currentSettings?.id) {
            guard let settings = currentSettings else { return }
            settings.notificationsEnabled = await NotificationService().isAuthorized()
            let purchaseService = PurchaseService.shared
            _ = await purchaseService.syncEntitlements(settings: settings)
            try? modelContext.save()
            // Keep Health data fresh whenever LineCheck opens. This is deliberately silent;
            // Settings remains the place for a user-requested sync status message.
            if settings.healthKitSyncEnabled {
                Task {
                    _ = try? await HealthKitSyncService.sync(settings: settings, context: modelContext)
                }
                Task {
                    await HealthKitBackgroundSyncCoordinator.shared.activateIfPossible()
                }
            }
            await purchaseService.observeEntitlementUpdates(settings: settings) {
                try? modelContext.save()
            }
            // Detached so a slow OpenAI call never delays the rest of app launch - this is a
            // silent background check, not something the UI is waiting on.
            Task {
                await WeeklyLunaUpdateService.generateIfDue(
                    settings: settings,
                    scans: scans,
                    dailyLogs: dailyLogs,
                    cycles: cycleRecords,
                    periods: periodEvents,
                    existingUpdates: weeklyLunaUpdates,
                    context: modelContext
                )
            }
        }
        .overlay {
            if let flow = appState.activeFlow, flow.step == .mode {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { appState.activeFlow = nil }
                ModeSelectionView(flow: flow)
                    .padding(.horizontal, 18)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: appState.activeFlow?.step == .mode)
        .sheet(isPresented: Binding(
            get: { appState.showPremium },
            set: { appState.showPremium = $0 }
        )) {
            PremiumView()
        }
        .fullScreenCover(item: Binding(
            get: {
                guard let flow = appState.activeFlow, flow.step != .mode else { return nil }
                return flow
            },
            set: { appState.activeFlow = $0 }
        )) { flow in
            ScanFlowView(flow: flow)
        }
        .toast(message: Binding(get: { appState.toast }, set: { appState.toast = $0 }))
        .overlay {
            if let warning = appState.storageWarning {
                BrandedNoticeOverlay(
                    icon: "externaldrive.badge.exclamationmark",
                    title: "Storage unavailable",
                    message: warning,
                    primaryTitle: "OK",
                    primaryAction: { appState.storageWarning = nil }
                )
            }
        }
        .overlay {
            if let prompt = appState.postScanPrompt {
                postScanPromptOverlay(prompt)
            }
        }
    }

    private struct ReminderSyncKey: Hashable {
        let isActive: Bool
        let settingsID: UUID?
        let cycleID: UUID?
        let dates: [Date]
        let preferences: [Bool]
    }

    private var reminderSyncKey: ReminderSyncKey {
        let settings = currentSettings
        let cycle = CycleTrackingService.activeCycle(records: cycleRecords)
        let window = CycleTrackingService.window(records: cycleRecords, periods: periodEvents, settings: settings)
        return ReminderSyncKey(
            isActive: scenePhase == .active,
            settingsID: settings?.id,
            cycleID: cycle?.id,
            dates: window.map { [$0.cycleStart, $0.opkStartDate, $0.fertileStartDate, $0.fertileEndDate, $0.predictedOvulationDate, $0.nextPeriodDate] } ?? [],
            preferences: [
                settings?.autoRemindersEnabled ?? false,
                settings?.autoOvulationTestRemindersEnabled ?? false,
                settings?.autoFertileWindowRemindersEnabled ?? false,
                settings?.autoFertilePeakRemindersEnabled ?? false,
                settings?.autoPeriodExpectedRemindersEnabled ?? false,
                settings?.autoPeriodCheckInRemindersEnabled ?? false,
                settings?.autoPeriodLateRemindersEnabled ?? false,
                window?.isIrregular ?? false
            ]
        )
    }

    private var currentSettings: UserSettings? {
        UserSettings.canonical(from: settingsQuery) ?? appState.settings
    }

    /// Recomputed with the queries (and on scene-phase changes, which also
    /// re-evaluate this view), so widgets follow scans, periods and Pro status.
    private var widgetSnapshot: WidgetSnapshot {
        WidgetSnapshotService.snapshot(
            settings: currentSettings,
            cycleRecords: cycleRecords,
            periodEvents: periodEvents,
            scans: scans
        )
    }

    private func handleWidgetLink(_ url: URL) {
        guard let link = WidgetDeepLink(url: url),
              currentSettings?.hasCompletedOnboarding == true else { return }
        AppAnalytics.log("linecheck_widget_opened", ["link": link.rawValue])
        switch link {
        case .calendar:
            appState.selectedTab = .calendar
        case .setupCycle:
            appState.calendarSetupRequest = .ovulation
            appState.selectedTab = .calendar
        case .scanOvulation:
            appState.startScan(testType: .ovulation)
        }
    }

    /// A second device creates its own settings row before iCloud delivers the
    /// first, so duplicates can appear at any point after launch - not just on
    /// the pass that created one. Folding them down every time the row count
    /// changes keeps `currentSettings` from flipping between them.
    private func mergeDuplicateSettings() {
        guard settingsQuery.count > 1, let canonical = UserSettings.canonical(from: settingsQuery) else { return }
        for duplicate in settingsQuery where duplicate.id != canonical.id {
            canonical.absorb(duplicate)
            modelContext.delete(duplicate)
        }
        appState.settings = canonical
        try? modelContext.save()
    }

    private func ensureSettingsLoaded() async {
        mergeDuplicateSettings()
        if let existing = UserSettings.canonical(from: settingsQuery) {
            appState.settings = existing
            migrateLegacyCycleIfNeeded(existing)
            reconcileLongTermTracking()
            return
        }

        let settings = UserSettings()
        modelContext.insert(settings)
        appState.settings = settings
        migrateLegacyCycleIfNeeded(settings)
        reconcileLongTermTracking()
        try? modelContext.save()
    }

    private func migrateLegacyCycleIfNeeded(_ settings: UserSettings) {
        guard settings.hasMigratedCycleHistory == false else { return }
        if cycleRecords.isEmpty, let start = settings.lastPeriodStartDate {
            let window = FertilityWindowCalculator.window(
                lastPeriodStart: start,
                averageCycleLength: settings.averageCycleLength,
                lutealPhaseLength: settings.lutealPhaseLength
            )
            let cycle = CycleRecord(
                startDate: start,
                startSource: .migrated,
                predictedOvulationDate: window?.predictedOvulationDate,
                confirmedOvulationDate: settings.knownOvulationDate,
                ovulationSource: settings.knownOvulationDate == nil ? nil : .migrated,
                expectedPeriodDate: settings.expectedPeriodDate ?? window?.nextPeriodDate,
                averageCycleLengthAtStart: settings.averageCycleLength,
                lutealPhaseLengthAtStart: settings.lutealPhaseLength
            )
            modelContext.insert(cycle)
            for scan in scans {
                CycleTrackingService.attach(scan, to: [cycle])
            }
            CycleTrackingService.reconcileOvulationEstimates(records: [cycle], scans: scans)
            if periodEvents.isEmpty {
                modelContext.insert(PeriodEvent(startDate: start, source: .migrated, cycleRecordID: cycle.id))
            }
        }
        settings.hasMigratedCycleHistory = true
        try? modelContext.save()
    }

    private func reconcileLongTermTracking() {
        guard !cycleRecords.isEmpty else { return }
        for scan in scans {
            CycleTrackingService.attach(scan, to: cycleRecords)
        }
        CycleTrackingService.reconcileOvulationEstimates(records: cycleRecords, scans: scans)
        // Existing temperature logs can already show a post-ovulation rise;
        // apply it on launch rather than waiting for the next edit or sync.
        CycleTrackingService.reconcileTemperatureOvulation(records: cycleRecords, logs: dailyLogs)
        try? modelContext.save()
    }

    @ViewBuilder
    private func postScanPromptOverlay(_ prompt: PostScanPrompt) -> some View {
        switch prompt {
        case .rating:
            BrandedNoticeOverlay(
                icon: "star.bubble.fill",
                usesLunaArtwork: true,
                title: "Help our small team",
                message: "MenoPlan is built by a small team, and every rating makes a real difference. If the app has helped you, we’d love your honest feedback. It helps us improve and helps other people find us.",
                primaryTitle: "Rate MenoPlan",
                secondaryTitle: "Not now",
                primaryAction: {
                    appState.postScanPrompt = nil
                    requestReview()
                },
                secondaryAction: {
                    appState.postScanPrompt = nil
                }
            )
        case .setupCycle:
            BrandedNoticeOverlay(
                icon: "calendar.badge.plus",
                imageName: "CalendarReminderIcon",
                title: "Want predictions?",
                message: "Add your last period and MenoPlan can show your fertile days, when to test and when your period is due. It takes about a minute.",
                primaryTitle: "Set up my cycle",
                secondaryTitle: "Not now",
                primaryAction: {
                    appState.postScanPrompt = nil
                    appState.calendarSetupRequest = .ovulation
                    appState.selectedTab = .calendar
                },
                secondaryAction: {
                    appState.postScanPrompt = nil
                }
            )
        case .notifications:
            BrandedNoticeOverlay(
                icon: "bell.badge.fill",
                imageName: "CalendarReminderIcon",
                title: "Never miss a retest",
                message: "Get reminders for your check-ins and tests.",
                primaryTitle: "Enable notifications",
                secondaryTitle: "Not now",
                primaryAction: {
                    appState.postScanPrompt = nil
                    Task { await enablePostUseNotifications() }
                },
                secondaryAction: {
                    appState.postScanPrompt = nil
                }
            )
        }
    }

    @MainActor
    private func enablePostUseNotifications() async {
        guard let settings = currentSettings else { return }
        let granted = await NotificationService().requestPermission()
        settings.notificationsEnabled = granted
        try? modelContext.save()
        appState.toast = granted ? "Notifications enabled" : "Notifications remain off"
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lineLayout) private var layout
    @State private var bannerRefreshID = UUID()
    /// Height of the banner currently on screen. Anchored adaptive banners are
    /// 50pt on a phone but up to 90pt on iPad, so the inset the content leaves
    /// for the ad has to follow the measured height instead of a constant.
    @State private var bannerAdHeight = AppLayout.fallbackBannerAdHeight

    var body: some View {
        @Bindable var state = appState
        // Compare against `== false` rather than `!= true` - settings is nil
        // for a brief window at cold launch while ensureSettingsLoaded()
        // is still running, and `nil != true` reads as "not pro" (ads
        // allowed) during that gap even for a Debug Premium / Pro user.
        // `nil == false` is false, so ads stay suppressed until settings
        // has actually loaded and positively confirmed the user isn't Pro.
        let canUseAdPlacements = state.settings?.hasCompletedOnboarding == true
            && state.settings?.proUnlocked == false
            && state.activeFlow == nil
            && state.showPremium == false
        let showsBannerAd = FeatureFlags.enableBannerAds
            && state.settings?.proUnlocked == false
            && state.adConsent.canRequestAds
            && state.adConsent.adsStarted
            && state.isTabBarHidden == false

        shell(
            selection: $state.selectedTab,
            showsBannerAd: showsBannerAd,
            showsTabBar: state.isTabBarHidden == false
        )
        .task(id: canUseAdPlacements) {
            guard canUseAdPlacements else { return }
            await state.adConsent.requestTrackingAndConsentIfNeeded()
            if state.adConsent.canRequestAds, state.adConsent.adsStarted {
                state.interstitialAds.load()
            }
        }
        .onChange(of: state.adConsent.adsStarted) { _, adsStarted in
            guard adsStarted, canUseAdPlacements else { return }
            state.interstitialAds.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            bannerRefreshID = UUID()
        }
    }

    /// The app shell: a full-bleed screen with the floating capsule tab bar
    /// over it.
    ///
    /// One shell for both size classes. On iPad the only differences are that
    /// the tab bar stops short of the full width and the screen beside it caps
    /// its own content column — everything else is the layout the iPhone has
    /// always used.
    private func shell(
        selection: Binding<AppTab>,
        showsBannerAd: Bool,
        showsTabBar: Bool
    ) -> some View {
        ZStack(alignment: .bottom) {
            selectedScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, showsBannerAd ? AppLayout.bannerAdContentPadding(forBannerHeight: bannerAdHeight) : 0)

            if showsBannerAd {
                VStack(spacing: 0) {
                    BannerAdSlot(refreshID: bannerRefreshID, height: $bannerAdHeight)
                        .padding(.top, AppLayout.bannerAdTopPadding)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showsTabBar {
                LineTabBar(selection: selection)
                    // `.infinity` on compact, so the phone's tab bar still
                    // spans the width exactly as it always has.
                    .frame(maxWidth: layout.tabBarMaxWidth)
                    .padding(.horizontal, 20)
                    .padding(.bottom, AppLayout.floatingTabBarBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .providesLineLayout()
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch appState.selectedTab {
        case .home:
            HomeView()
        case .history:
            HistoryView()
        case .calendar:
            CalendarView()
        case .assistant:
            AssistantView()
        case .settings:
            SettingsView()
        }
    }
}

private struct BannerAdSlot: View {
    let refreshID: UUID
    @Binding var height: CGFloat
    @State private var width: CGFloat = 0

    var body: some View {
        // The banner can only be sized once the slot has been measured, so the
        // slot reserves the fallback height first and swaps in the real ad on
        // the next layout pass. The banner view is framed at exactly the size
        // being requested - that's what keeps the creative filling it rather
        // than letterboxing - and on iPad the 728pt leaderboard that picks
        // lands within a few points of the 720pt content column, so the ad
        // reads as the same width as the page beneath it.
        let adSize = BannerAdLayout.size(forWidth: width)

        Color.clear
            .frame(height: adSize.height)
            .overlay {
                if width > 0 {
                    BannerAdView(adUnitID: AdMobConstants.bannerAdUnitID, width: width)
                        .id(refreshID)
                        .frame(width: adSize.width, height: adSize.height)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onChange(of: adSize.height, initial: true) { _, newHeight in
                height = newHeight
            }
            .accessibilityIdentifier("admob-banner-slot")
    }
}

private struct LineTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: LineType.size(23), weight: .bold))
                            .symbolVariant(selection == tab ? .fill : .none)
                        Text(tab.title)
                            .font(.app(.caption, weight: .semibold))
                            // Five tabs share the width: at large text sizes
                            // shrink the label rather than cut it to "Calend…".
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(selection == tab ? Color.lineBlue : Color.black.opacity(0.88))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Color.black.opacity(0.08))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(5)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
    }
}
