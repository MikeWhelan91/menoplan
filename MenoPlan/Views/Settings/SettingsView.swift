import CloudKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.lineLayout) private var layout
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var appState
    @Query private var settingsQuery: [UserSettings]
    @Query(sort: \Reminder.scheduledDate) private var reminders: [Reminder]
    @Query private var scans: [Scan]
    @Query private var comparisons: [ScanComparison]
    @Query private var cycles: [CycleRecord]
    @Query private var periods: [PeriodEvent]
    @Query private var dailyLogs: [DailyFertilityLog]
    @Query private var conversations: [AssistantConversation]
    @State private var showPro = false
    @State private var showAbout = false
    @State private var showMedicalSources = false
    @State private var showReminderPreferences = false
    @State private var exportDocument: LineCheckExportDocument?
    @State private var showExporter = false
    @State private var confirmDeleteAllData = false
    @State private var showStartFresh = false
    @State private var deleteTestsWhenStartingFresh = false
    @State private var iCloudStatus: ICloudAvailability = .checking
    @State private var showPersonalization = false
    @State private var hasNewHealthPermissions = false
    @Namespace private var stageSelection
    #if DEBUG
    @State private var sendNotificationPreviews = false
    @State private var generateWeeklyReportPreview = false
    @State private var showDebugLoadingPreview = false
    @State private var showDebugSplashPreview = false
    @State private var seedSampleTrendsData = false
    @State private var isInitializingCloudKitSchema = false
    #endif

    var settings: UserSettings? { UserSettings.canonical(from: settingsQuery) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let settings {
                        proCard(settings: settings)
                        stageCard(settings: settings)
                        preferencesCard(settings: settings)
                        privacyCard
                        aboutCard
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 24)
                .lineBottomInset()
                .lineContentColumn()
            }
            .background { LineCheckBrandBackdrop() }
            .task(id: settings?.healthKitSyncEnabled) {
                guard settings?.healthKitSyncEnabled == true else { hasNewHealthPermissions = false; return }
                hasNewHealthPermissions = await HealthKitService.shared.hasUnrequestedTypes()
            }
            .sheet(isPresented: $showPro) { PremiumView() }
            .sheet(isPresented: $showAbout) {
                AboutLineCheckSheet()
            }
            .sheet(isPresented: $showMedicalSources) {
                MedicalSourcesSheet()
            }
            .sheet(isPresented: $showPersonalization) {
                if let settings {
                    PersonalizationQuizSheet(settings: settings)
                }
            }
            .sheet(isPresented: $showReminderPreferences) {
                if let settings {
                    ReminderPreferencesSheet(settings: settings)
                }
            }
            #if DEBUG
            .fullScreenCover(isPresented: $showDebugLoadingPreview) {
                DebugLoadingScreenPreview(onClose: { showDebugLoadingPreview = false })
            }
            .fullScreenCover(isPresented: $showDebugSplashPreview) {
                ZStack {
                    BrandedLoadingScreen(title: "Opening MenoPlan")
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { showDebugSplashPreview = false }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: LineType.size(15), weight: .bold))
                                    .foregroundStyle(Color.lineNavy)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.86), in: Circle())
                                    .contentShape(Circle())
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 16)
                            .accessibilityLabel("Close splash screen preview")
                        }
                        Spacer()
                    }
                }
            }
            #endif
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json, defaultFilename: "MenoPlan-Data") { result in
                appState.toast = (try? result.get()) != nil ? "Data exported" : "Export cancelled"
            }
            .alert("Delete All Local Data?", isPresented: $confirmDeleteAllData) {
                Button("Delete Everything", role: .destructive) { deleteAllLocalData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes saved tests, periods, symptoms and activities, reminders, comparisons, and Luna conversations from this device and your private iCloud database. Locally stored test photos are also deleted. This cannot be undone.")
            }
            .task { await refreshICloudStatus() }
        }
        .tint(Color.lineBlue)
        .overlay {
            if showStartFresh {
                ZStack {
                    Color.black.opacity(0.30)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismissStartFresh() }

                    StartFreshDialog(deleteTestHistory: $deleteTestsWhenStartingFresh) {
                        startFresh(deleteTestHistory: deleteTestsWhenStartingFresh)
                    } onCancel: {
                        dismissStartFresh()
                    }
                    .padding(.horizontal, 24)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showStartFresh)
    }

    private func proCard(settings: UserSettings) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 11) {
                    Image(systemName: settings.proUnlocked ? "checkmark.seal.fill" : "chart.line.uptrend.xyaxis")
                        .font(.system(size: LineType.size(17), weight: .bold))
                        .foregroundStyle(settings.proUnlocked ? Color.lineBlue : Color.linePurple)
                        .frame(width: 38, height: 38)
                        .background((settings.proUnlocked ? Color.lineBlue : Color.linePurple).opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("MenoPlan Pro")
                            .font(.lineHeadline())
                            .foregroundStyle(Color.lineNavy)
                        Text(settings.proUnlocked ? "Your Pro features are active" : "More clarity, less guesswork")
                            .font(.lineCaption(.semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.57))
                    }

                    Spacer(minLength: 8)

                    Text(settings.proUnlocked ? "PRO" : "FREE")
                        .font(.app(.caption2, weight: .heavy))
                        .foregroundStyle(settings.proUnlocked ? Color.white : Color.linePurple)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(settings.proUnlocked ? Color.lineBlue : Color.linePurple.opacity(0.10), in: Capsule())
                }

                Text(
                    settings.proUnlocked
                        ? "Unlimited Luna tools, doctor reports, full trends, and no ads."
                        : "Unlock Luna tools, doctor reports, full trends, and no ads."
                )
                    .font(.lineSubheadline())
                    .foregroundStyle(Color.lineNavy.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                // Side by side once there is room: stacked full-width buttons
                // read as two separate primary actions on a wide card, when
                // Restore is really a quiet secondary to Explore Pro.
                let proActions = HStack(spacing: 12) {
                    Button(settings.proUnlocked ? "Manage Pro" : "Explore Pro") {
                        showPro = true
                    }
                    .buttonStyle(.primaryLine)
                    .frame(maxWidth: layout.isRegular ? 300 : .infinity)

                    Button("Restore Purchases") {
                        showPro = true
                    }
                    .font(.lineCaption(.semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.58))
                    .frame(maxWidth: layout.isRegular ? nil : .infinity)
                    .buttonStyle(.plain)
                }

                if layout.isRegular {
                    proActions
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 13) {
                        Button(settings.proUnlocked ? "Manage Pro" : "Explore Pro") {
                            showPro = true
                        }
                        .buttonStyle(.primaryLine)
                        .frame(maxWidth: .infinity)

                        Button("Restore Purchases") {
                            showPro = true
                        }
                        .font(.lineCaption(.semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.58))
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                    }
                }

                #if DEBUG
                Divider()

                Toggle(isOn: Binding(
                    get: { PurchaseService.shared.debugPremiumEnabled },
                    set: { enabled in
                        PurchaseService.shared.setDebugPremium(enabled, settings: settings)
                        try? modelContext.save()
                    }
                )) {
                    Text("Developer: simulate Pro")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.48))
                }
                .tint(Color.linePurple)
                #endif
            }
        }
    }

    private func aboutYouSubtitle(_ settings: UserSettings) -> String {
        let detail = settings.hasCompletedPersonalization ? "Update your answers" : "Tailor predictions and results"
        return settings.userName.isEmpty ? detail : "\(settings.userName) · \(detail)"
    }

    /// Where the person is in the transition. Changing it only changes what
    /// MenoPlan leads with; nothing already logged is touched.
    private func stageCard(settings: UserSettings) -> some View {
        let current = settings.menopauseStage
        return AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Where are you now?")
                    .font(.lineHeadline())
                    .foregroundStyle(Color.lineNavy)

                HStack(spacing: 10) {
                    ForEach(MenopauseStage.allCases) { stage in
                        Button {
                            guard stage != current else { return }
                            settings.menopauseStage = stage
                            try? modelContext.save()
                        } label: {
                            VStack(spacing: 9) {
                                Image(systemName: stage.symbol)
                                    .font(.system(size: LineType.size(20), weight: .semibold))
                                    .foregroundStyle(current == stage ? Color.white : Color.linePurple)
                                    .frame(width: 46, height: 46)
                                    .background(current == stage ? AnyShapeStyle(Color.linePurple.gradient) : AnyShapeStyle(Color.linePurple.opacity(0.12)), in: Circle())
                                    .symbolEffect(.bounce, value: current == stage)
                                Text(stage.shortTitle)
                                    .font(.app(size: LineType.size(13), weight: .bold))
                                    .foregroundStyle(Color.lineNavy)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                            }
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 112)
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
                                if current == stage {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.linePurple, lineWidth: 2)
                                        .matchedGeometryEffect(id: "selectedStage", in: stageSelection)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if current == stage {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(Color.white, Color.linePurple)
                                        .padding(7)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .accessibilityLabel(stage.title)
                        .accessibilityAddTraits(current == stage ? .isSelected : [])
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)

                Text(current.detail)
                    .font(.app(.caption))
                    .foregroundStyle(Color.lineNavy.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func preferencesCard(settings: UserSettings) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Preferences")
                    .font(.lineHeadline())
                    .foregroundStyle(Color.lineNavy)

                HStack(alignment: .center, spacing: 12) {
                    // Name lives in About you now, alongside the other answers.
                    Button { showPersonalization = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: LineType.size(15), weight: .bold))
                                .foregroundStyle(Color.linePurple)
                                .frame(width: 34, height: 34)
                                .background(Color.linePurple.opacity(0.1), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("About you")
                                    .font(.lineSubheadline(.semibold))
                                    .foregroundStyle(Color.lineNavy)
                                Text(aboutYouSubtitle(settings))
                                    .font(.lineCaption())
                                    .foregroundStyle(Color.lineNavy.opacity(0.55))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.app(.caption, weight: .bold))
                                .foregroundStyle(Color.lineNavy.opacity(0.3))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                }

                Divider()

                Button { showStartFresh = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: LineType.size(15), weight: .bold))
                            .foregroundStyle(Color.linePurple)
                            .frame(width: 34, height: 34)
                            .background(Color.linePurple.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start Fresh")
                                .font(.lineSubheadline(.semibold))
                                .foregroundStyle(Color.lineNavy)
                            Text("Clear your cycle setup and run onboarding again")
                                .font(.lineCaption())
                                .foregroundStyle(Color.lineNavy.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(Color.lineNavy.opacity(0.3))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Clear cycle setup and run onboarding again")

                Divider()

                SettingsToggleRow(
                    title: "Notifications",
                    isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { isEnabled in
                            Task { await setNotifications(isEnabled, settings: settings) }
                        }
                    )
                )

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { settings.healthKitSyncEnabled },
                        set: { isEnabled in
                            Task { await setHealthKitSync(isEnabled, settings: settings) }
                        }
                    )) {
                        HStack(spacing: 7) {
                            Text("Sync with Apple Health")
                                .font(.lineSubheadline(.semibold))
                                .foregroundStyle(Color.lineNavy)
                        }
                    }
                    .tint(Color.lineBlue)
                    Text("Bring in periods, symptoms, wrist temperature, weight, sleep, activity and heart data from Apple Health, and save the weight and water you log here back to it.")
                        .font(.lineCaption())
                        .foregroundStyle(Color.lineNavy.opacity(0.56))

                    if settings.healthKitSyncEnabled && hasNewHealthPermissions {
                        Button {
                            Task { await reviewNewHealthPermissions(settings: settings) }
                        } label: {
                            Label("Review new Apple Health categories", systemImage: "heart.text.square")
                                .font(.app(.caption, weight: .bold))
                        }
                        .buttonStyle(.borderless)
                        .tint(Color.linePink)
                        .padding(.top, 3)
                    }

                    if let lastSync = settings.lastHealthKitSyncDate {
                        Label {
                            Text("Last synced \(lastSync.formatted(.relative(presentation: .named))) · \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(Color.lineBlue.opacity(0.78))
                        .padding(.top, 3)
                    }
                }

                Divider()

                Button { showReminderPreferences = true } label: {
                    HStack(spacing: 10) {
                        Text("Reminder Preferences")
                            .font(.lineSubheadline(.semibold))
                            .foregroundStyle(Color.lineNavy)

                        Spacer(minLength: 12)

                        Text("Customize")
                            .font(.lineCaption(.semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.54))

                        Image(systemName: "chevron.right")
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(Color.lineNavy.opacity(0.42))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                #if DEBUG
                Divider()

                Toggle(isOn: Binding(
                    get: { sendNotificationPreviews },
                    set: { shouldSend in
                        sendNotificationPreviews = shouldSend
                        guard shouldSend else { return }
                        Task { await sendDebugNotificationPreviews(settings: settings) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Preview notifications", systemImage: "bell.badge")
                            .font(.lineSubheadline(.semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.72))
                        Text("Sends all four reminder styles 5 seconds apart.")
                            .font(.lineCaption())
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                    }
                }
                .tint(Color.linePurple)
                .accessibilityHint("Schedules four debug notification previews")

                Divider()

                Toggle(isOn: Binding(
                    get: { generateWeeklyReportPreview },
                    set: { shouldGenerate in
                        generateWeeklyReportPreview = shouldGenerate
                        guard shouldGenerate else { return }
                        Task { await generateDebugWeeklyReport(settings: settings) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Generate Luna weekly report", systemImage: "sparkles.rectangle.stack")
                            .font(.lineSubheadline(.semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.72))
                        Text("Creates a new report now, ignoring the seven-day schedule.")
                            .font(.lineCaption())
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                    }
                }
                .tint(Color.linePurple)
                .accessibilityHint("Generates a debug Luna weekly report immediately")

                Divider()

                Button {
                    showDebugLoadingPreview = true
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Preview loading screen", systemImage: "hourglass")
                            .font(.lineSubheadline(.semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.72))
                        Text("Holds the loading screen open until you close it.")
                            .font(.lineCaption())
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    showDebugSplashPreview = true
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Preview splash screen", systemImage: "app.badge")
                            .font(.lineSubheadline(.semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.72))
                        Text("Shows the \"Opening MenoPlan\" screen until you close it.")
                            .font(.lineCaption())
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    replayOnboarding()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Replay onboarding", systemImage: "sparkles.rectangle.stack")
                            .font(.lineSubheadline(.semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.72))
                        Text("Runs the onboarding flow again. Unlike Start Fresh, saved tests and history are kept.")
                            .font(.lineCaption())
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()

                Toggle(isOn: Binding(
                    get: { seedSampleTrendsData },
                    set: { shouldSeed in
                        seedSampleTrendsData = shouldSeed
                        guard shouldSeed else { return }
                        seedSampleTrendsData(settings: settings)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Seed sample chart data", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.lineSubheadline(.semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.72))
                        Text("Adds six fake cycles, daily logs, Apple Health-style readings, weight, noticed signals and test results so every Trends card has data.")
                            .font(.lineCaption())
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                    }
                }
                .tint(Color.linePurple)
                .accessibilityHint("Inserts fake cycle, daily log, and scan data for previewing charts")

                Divider()

                Button {
                    guard !isInitializingCloudKitSchema else { return }
                    isInitializingCloudKitSchema = true
                    appState.toast = "Creating iCloud schema…"
                    Task.detached {
                        let message: String
                        do {
                            try CloudKitSchemaInitializer.initialize()
                            message = "iCloud development schema created. Deploy it in the CloudKit Console."
                        } catch {
                            message = "iCloud schema failed: \(error.localizedDescription)"
                        }
                        await MainActor.run {
                            isInitializingCloudKitSchema = false
                            appState.toast = message
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(isInitializingCloudKitSchema ? "Creating iCloud schema…" : "Create iCloud schema (development)", systemImage: "icloud.and.arrow.up")
                            .font(.lineSubheadline(.semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.72))
                        Text("Adds every synced type and field to the iCloud development database, ready to deploy to production. Needs an iCloud account on this device.")
                            .font(.lineCaption())
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isInitializingCloudKitSchema)
                #endif
            }
        }
    }

    @MainActor
    private func setNotifications(_ isEnabled: Bool, settings: UserSettings) async {
        let notificationService = NotificationService()
        if isEnabled {
            let granted = await notificationService.requestPermission()
            settings.notificationsEnabled = granted
            if granted {
                appState.toast = "Notifications enabled"
                await rescheduleUpcomingReminders()
            } else {
                appState.toast = "Notifications permission was not granted"
            }
        } else {
            notificationService.cancelAll()
            settings.notificationsEnabled = false
            appState.toast = "Notifications disabled"
        }
        try? modelContext.save()
    }

    /// People who connected before LineCheck asked for sleep, weight,
    /// activity and heart data see the system sheet again only for those.
    @MainActor
    private func reviewNewHealthPermissions(settings: UserSettings) async {
        do {
            try await HealthKitService.shared.requestAuthorization()
            settings.healthKitPermissionsVersionValue = HealthKitService.permissionsVersion
            hasNewHealthPermissions = false
            try? modelContext.save()
            _ = try? await HealthKitSyncService.sync(settings: settings, context: modelContext)
            appState.toast = "Apple Health categories updated"
        } catch {
            appState.toast = "Couldn't open Apple Health permissions"
        }
    }

    @MainActor
    private func setHealthKitSync(_ isEnabled: Bool, settings: UserSettings) async {
        guard isEnabled else {
            settings.healthKitSyncEnabled = false
            // Re-enabling deliberately re-reads the available history rather
            // than leaving a prior cursor hiding samples logged on Apple Watch.
            settings.lastHealthKitSyncDate = nil
            try? modelContext.save()
            await HealthKitBackgroundSyncCoordinator.shared.deactivate()
            appState.toast = "Apple Health sync turned off — next sync will recheck history"
            return
        }
        appState.toast = await HealthKitConnection.connect(settings: settings, context: modelContext, source: "settings")
    }

    private func rescheduleUpcomingReminders() async {
        let notificationService = NotificationService()
        for reminder in reminders where !reminder.isCompleted && reminder.scheduledDate > .now {
            try? await notificationService.schedule(ReminderNotification(reminder: reminder))
        }
    }

    #if DEBUG
    @MainActor
    private func sendDebugNotificationPreviews(settings: UserSettings) async {
        let notificationService = NotificationService()
        let granted = await notificationService.requestPermission()
        settings.notificationsEnabled = granted

        guard granted else {
            sendNotificationPreviews = false
            appState.toast = "Enable notifications to preview them"
            try? modelContext.save()
            return
        }

        do {
            try await notificationService.scheduleDebugPreviews()
            appState.toast = "Notification previews start in 5 seconds"
        } catch {
            appState.toast = "Couldn't schedule notification previews"
        }
        sendNotificationPreviews = false
        try? modelContext.save()
    }

    /// Fills every Trends card with believable data: six past cycles
    /// (varied lengths, period end dates, live forecasts, Peak-confirmed
    /// ovulation in most - one with a short luteal phase), daily logs with
    /// cycle-shaped symptoms, moods, mucus, BBT, wrist temperature and
    /// weekly weight, Apple Health-style metrics that rise after ovulation,
    /// a few noticed signals, and saved test results.
    ///
    /// The sample cycles end at the earliest real period, so real history is
    /// left as it is; with none, a current cycle starting 12 days ago is added. Existing log fields are never
    /// overwritten, so running it twice doesn't duplicate days. Re-fetches
    /// between steps because this view's @Query arrays don't see inserts
    /// until the next render.
    @MainActor
    private func seedSampleTrendsData(settings: UserSettings?) {
        guard let settings else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let marker = "[LineCheck Screenshot Sample]"
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today) ?? today }
        func addingDays(_ n: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: n, to: date) ?? date }
        func currentCycles() -> [CycleRecord] { ((try? modelContext.fetch(FetchDescriptor<CycleRecord>())) ?? []).filter { !$0.notes.contains(marker) } }
        func currentPeriods() -> [PeriodEvent] { ((try? modelContext.fetch(FetchDescriptor<PeriodEvent>())) ?? []).filter { !$0.notes.contains(marker) } }
        func period(startingOn day: Date) -> PeriodEvent? { currentPeriods().first { calendar.isDate($0.startDate, inSameDayAs: day) } }
        func cycle(startingOn day: Date) -> CycleRecord? { currentCycles().first { calendar.isDate($0.startDate, inSameDayAs: day) } }

        // Oldest first. ovulationDay is the 1-based cycle day a Peak test
        // confirmed (nil = estimate only); forecast is the length LineCheck
        // predicted when the cycle began.
        let plan: [(length: Int, periodDays: Int, ovulationDay: Int?, forecast: Int)] = [
            (29, 5, 15, 28), (27, 4, nil, 28), (31, 6, 17, 29), (26, 4, 17, 28), (28, 5, 15, 28), (30, 5, 15, 29)
        ]
        // Sample cycles go before the earliest real period so they never
        // overlap real history (a real period inside a sample cycle split it
        // into an implausible 5-day cycle).
        let earliestReal = currentPeriods().map { calendar.startOfDay(for: $0.startDate) }.filter { $0 <= today }.min()
        let anchor = earliestReal ?? daysAgo(12)
        var starts: [Date] = []
        var cursor = addingDays(-plan.map(\.length).reduce(0, +), to: anchor)
        for item in plan {
            starts.append(cursor)
            cursor = addingDays(item.length, to: cursor)
        }

        for start in starts + [anchor] where period(startingOn: start) == nil {
            _ = CycleTrackingService.recordPeriodStart(start, settings: settings, records: currentCycles(), periods: currentPeriods(), context: modelContext)
        }
        if let current = period(startingOn: anchor), current.endDate == nil, anchor <= daysAgo(5) {
            current.endDate = addingDays(4, to: anchor)
        }

        for (index, item) in plan.enumerated() {
            let start = starts[index]
            period(startingOn: start)?.endDate = addingDays(item.periodDays - 1, to: start)
            guard let record = cycle(startingOn: start) else { continue }
            // Tracked live, so Prediction Accuracy grades the forecast.
            record.createdAt = start
            record.expectedPeriodDate = addingDays(item.forecast, to: start)
            guard let ovulationDay = item.ovulationDay else { continue }
            let ovulation = addingDays(ovulationDay - 1, to: start)
            record.predictedOvulationDate = ovulation
            record.ovulationSource = .testSupported
            let opkSteps: [(before: Int, ratio: Double, result: ScanResultType)] = [(5, 0.3, .low), (3, 0.55, .low), (2, 0.9, .high), (1, 1.2, .peak)]
            for step in opkSteps {
                modelContext.insert(Scan(
                    createdAt: addingDays(-step.before, to: ovulation).addingTimeInterval(15 * 3600),
                    testType: .ovulation, testFormat: .midstream, resultType: step.result,
                    certaintyPercentage: 90, testControlRatio: step.ratio, analysisMode: .aiQuickCheck,
                    imageFilename: "debug_seed_placeholder.jpg", cycleRecordID: record.id
                ))
            }
        }

        // Daily logs and Apple Health-style metrics for every day since the
        // first sample period, shaped by where each day sits in its cycle.
        let existingLogs = Dictionary(((try? modelContext.fetch(FetchDescriptor<DailyFertilityLog>())) ?? []).map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
        let existingMetrics = Dictionary(((try? modelContext.fetch(FetchDescriptor<DailyHealthMetrics>())) ?? []).map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
        let flowByDay: [FlowIntensity] = [.heavy, .heavy, .medium, .light, .spotting, .spotting]
        let firstStart = starts.first ?? anchor
        // Real history keeps its own logs; sample days stop where it begins.
        let lastSampleDay = earliestReal.map { addingDays(-1, to: $0) } ?? today
        let totalDays = (calendar.dateComponents([.day], from: firstStart, to: lastSampleDay).day ?? -1) + 1
        var random = SystemRandomNumberGenerator()
        func noise(_ amount: Double) -> Double { Double.random(in: -amount...amount, using: &random) }

        for dayNumber in 0..<totalDays {
            let date = addingDays(dayNumber, to: firstStart)
            let cycleIndex = starts.lastIndex { $0 <= date }.flatMap { date < anchor ? $0 : nil }
            let cycleStart = cycleIndex.map { starts[$0] } ?? anchor
            let dayIndex = calendar.dateComponents([.day], from: cycleStart, to: date).day ?? 0
            let length = cycleIndex.map { plan[$0].length }
            let periodDays = cycleIndex.map { plan[$0].periodDays } ?? 5
            let ovulationIndex = (cycleIndex.flatMap { plan[$0].ovulationDay } ?? (length.map { $0 - 13 } ?? 15)) - 1
            let daysToPeriod = length.map { $0 - dayIndex }
            let isPeriod = dayIndex < periodDays
            let isLuteal = dayIndex > ovulationIndex
            let isFertile = !isLuteal && dayIndex >= ovulationIndex - 5

            let log: DailyFertilityLog
            if let existing = existingLogs[date] {
                log = existing
            } else {
                log = DailyFertilityLog(date: date)
                modelContext.insert(log)
            }
            if log.symptoms.isEmpty {
                var symptoms: [String] = []
                if isPeriod && dayIndex < 2 { symptoms += ["Cramps", "Fatigue"] }
                if let daysToPeriod, daysToPeriod <= 3 { symptoms += daysToPeriod == 2 ? ["Bloating", "Cramps"] : ["Bloating", "Tender breasts"] }
                if dayIndex == ovulationIndex || (isFertile && dayNumber.isMultiple(of: 5)) { symptoms.append("Headache") }
                log.symptoms = symptoms
            }
            if log.moods.isEmpty {
                if let daysToPeriod, daysToPeriod <= 4 { log.moods = [daysToPeriod.isMultiple(of: 2) ? "Irritable" : "Anxious"] }
                else if isPeriod { log.moods = ["Tired"] }
                else if !isLuteal && dayNumber.isMultiple(of: 2) { log.moods = [isFertile ? "Happy" : "Calm"] }
            }
            if log.flowIntensity == nil, isPeriod { log.flowIntensity = flowByDay[min(dayIndex, flowByDay.count - 1)] }
            // Thermometer readings for the last two sample cycles and the
            // current one, so the BBT chart can find the temperature rise.
            if log.basalBodyTemperatureCelsius == nil, (cycleIndex ?? plan.count) >= plan.count - 2, date <= today {
                log.basalBodyTemperatureCelsius = (isLuteal ? 36.68 : 36.32) + noise(0.05)
            }
            if log.wristTemperatureCelsius == nil { log.wristTemperatureCelsius = (isLuteal ? 35.62 : 35.3) + noise(0.06) }
            if log.weightKg == nil, dayNumber.isMultiple(of: 7) { log.weightKg = 64.8 - Double(dayNumber) / 90 + noise(0.2) }

            let metrics: DailyHealthMetrics
            if let existing = existingMetrics[date] {
                metrics = existing
            } else {
                metrics = DailyHealthMetrics(date: date)
                modelContext.insert(metrics)
            }
            if metrics.restingHeartRate == nil { metrics.restingHeartRate = (isLuteal ? 61.5 : 58) + noise(1.2) }
            if metrics.heartRateVariabilityMs == nil { metrics.heartRateVariabilityMs = (isLuteal ? 44 : 52) + noise(4) }
            if metrics.sleepHours == nil { metrics.sleepHours = (isLuteal ? 6.9 : 7.4) + noise(0.35) }
            if metrics.steps == nil { metrics.steps = 8200 + noise(2500) }
            if metrics.exerciseMinutes == nil { metrics.exerciseMinutes = 32 + noise(15) }
        }

        // A few things LineCheck "noticed", spread across recent cycles.
        let noticed: [(id: String, tone: MenoPlan.CycleSignal.Tone, symbol: String, title: String, detail: String, first: Date, days: Int)] = [
            ("longCycle", .info, "calendar.badge.clock", "A longer cycle than usual",
             "Cycles often lengthen and vary in perimenopause.",
             addingDays(40, to: starts[plan.count - 2]), 5),
            ("shortSleep", .info, "bed.double", "Short on sleep this week",
             "You've averaged under 7 hours of sleep. Night sweats and hot flushes often break up sleep.",
             addingDays(20, to: starts[plan.count - 2]), 4),
            ("weightChange", .info, "scalemass", "Weight has come down",
             "Your weight is down a little over the last couple of months.",
             daysAgo(6), 6),
        ]
        for item in noticed {
            let signal = MenoPlan.CycleSignal(id: item.id, tone: item.tone, symbol: item.symbol, title: item.title, detail: item.detail, surfaces: [.home, .luna])
            let row = NoticedSignal(signal: signal, on: item.first)
            row.lastSeen = min(today, addingDays(item.days - 1, to: item.first))
            row.seenAt = row.lastSeen
            modelContext.insert(row)
        }

        try? modelContext.save()
        appState.toast = "Sample data added - check Trends"
    }

    @MainActor
    private func generateDebugWeeklyReport(settings: UserSettings) async {
        appState.toast = "Generating Luna weekly report…"
        let result = await WeeklyLunaUpdateService.generateForDebug(
            settings: settings,
            scans: scans,
            dailyLogs: dailyLogs,
            cycles: cycles,
            periods: periods,
            context: modelContext
        )
        switch result {
        case .generated:
            appState.toast = "Luna weekly report is ready"
        case .notPro:
            appState.toast = "Enable Debug Premium to generate a report"
        case .noRecentActivity:
            appState.toast = "Add a scan, symptom, or activity from the last 7 days first"
        case .failed:
            appState.toast = "Couldn't generate the Luna weekly report"
        }
        generateWeeklyReportPreview = false
    }
    #endif

    private var privacyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Privacy")
                    .font(.lineHeadline())
                    .foregroundStyle(Color.lineNavy)
                    .padding(.bottom, 8)

                SettingsActionRow(
                    title: "iCloud Sync",
                    detail: iCloudStatus.detail,
                    systemImage: iCloudStatus.systemImage
                )
                .padding(.vertical, 10)

                Divider()

                Link(destination: URL(string: "https://getsolutions.app/privacy")!) {
                    SettingsActionRow(title: "Privacy Policy", detail: "getsolutions.app/privacy", tint: .linePurple, systemImage: "hand.raised", isInteractive: true)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider()

                Link(destination: URL(string: "https://getsolutions.app/terms")!) {
                    SettingsActionRow(title: "Terms of Use", detail: "getsolutions.app/terms", tint: .linePurple, systemImage: "doc.text", isInteractive: true)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if appState.adConsent.privacyOptionsRequired {
                    Divider()

                    Button {
                        Task {
                            let shown = await appState.adConsent.showPrivacyOptions()
                            appState.toast = shown ? "Ad privacy choices updated" : "Ad privacy choices unavailable"
                        }
                    } label: {
                        SettingsActionRow(title: "Ad privacy choices", detail: "Manage Google ad consent", tint: .linePurple, systemImage: "rectangle.and.hand.point.up.left", isInteractive: true)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                Button {
                    exportDocument = LineCheckExportDocument(data: makeExportData())
                    showExporter = true
                } label: {
                    SettingsActionRow(title: "Export My Data", detail: "Save a JSON copy of your tracking history", tint: .linePurple, systemImage: "square.and.arrow.up", isInteractive: true)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider()
                Button(role: .destructive) { confirmDeleteAllData = true } label: {
                    SettingsActionRow(title: "Delete All Data", detail: "Erase MenoPlan data from this device and iCloud", tint: .linePink, systemImage: "trash", isInteractive: true)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func refreshICloudStatus() async {
        do {
            let status = try await CKContainer(identifier: "iCloud.com.menocheck.app").accountStatus()
            iCloudStatus = ICloudAvailability(status)
        } catch {
            iCloudStatus = .unavailable
        }
    }

    private var aboutCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if let url = URL(string: "mailto:info@getsolutions.app") {
                        openURL(url)
                    }
                } label: {
                    SettingsActionRow(title: "Help & Support", detail: "info@getsolutions.app", tint: .linePurple, systemImage: "questionmark.circle", isInteractive: true)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    showAbout = true
                } label: {
                    SettingsActionRow(title: "About MenoPlan", detail: "How the app works", tint: .linePurple, systemImage: "info.circle", isInteractive: true)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    showMedicalSources = true
                } label: {
                    SettingsActionRow(title: "Medical Sources", detail: "Citations and safety", tint: .linePurple, systemImage: "cross.case", isInteractive: true)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider()

                SettingsActionRow(title: "App version", detail: appVersionLabel, systemImage: "number")
                    .padding(.vertical, 10)
            }
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (.some(version), .some(build)) where build.isEmpty == false:
            return "\(version) (\(build))"
        case let (.some(version), _):
            return version
        default:
            return "Unknown"
        }
    }

    private func makeExportData() -> Data {
        let iso = ISO8601DateFormatter()
        func date(_ value: Date?) -> Any { value.map(iso.string(from:)) ?? NSNull() }
        let payload: [String: Any] = [
            "exportedAt": iso.string(from: .now),
            "settings": settings.map { [
                "userName": $0.userName,
                "trackingFocus": $0.trackingFocus.rawValue,
                "lastPeriodStart": date($0.lastPeriodStartDate),
                "averageCycleLength": $0.averageCycleLength,
                "lutealPhaseLength": $0.lutealPhaseLength
            ] } ?? [:],
            "periods": periods.map { ["id": $0.id.uuidString, "start": date($0.startDate), "end": date($0.endDate), "source": $0.source.rawValue, "notes": $0.notes] },
            "cycles": cycles.map { ["id": $0.id.uuidString, "start": date($0.startDate), "end": date($0.endDate), "predictedOvulation": date($0.predictedOvulationDate), "confirmedOvulation": date($0.confirmedOvulationDate), "expectedPeriod": date($0.expectedPeriodDate), "cycleLength": $0.averageCycleLengthAtStart, "lutealLength": $0.lutealPhaseLengthAtStart] },
            "bodySigns": dailyLogs.map { ["date": date($0.date), "symptoms": $0.symptoms, "moods": $0.moods, "supplements": $0.supplements, "healthKitObservations": $0.healthKitObservations, "notes": $0.notes] },
            "tests": scans.map { ["id": $0.id.uuidString, "date": date($0.createdAt), "type": $0.testType.rawValue, "result": $0.resultType.rawValue, "certainty": $0.certaintyPercentage, "lineStrength": $0.lineStrength, "ratio": $0.testControlRatio, "notes": $0.notes] },
            "comparisons": comparisons.map { ["id": $0.id.uuidString, "date": date($0.createdAt), "type": $0.testType.rawValue, "earlierScanID": $0.earlierScanID.uuidString, "laterScanID": $0.laterScanID.uuidString, "summary": $0.localSummaryDetail] },
            "reminders": reminders.map { ["id": $0.id.uuidString, "title": $0.title, "type": $0.reminderType.rawValue, "date": date($0.scheduledDate), "completed": $0.isCompleted] },
            "lunaConversations": conversations.map { conversation in
                ["id": conversation.id.uuidString, "title": conversation.title, "createdAt": date(conversation.createdAt), "messages": conversation.messages.map { ["role": $0.role.rawValue, "text": $0.text, "date": date($0.createdAt)] }] as [String: Any]
            }
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    private func deleteAllLocalData() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        scans.forEach { scan in
            ImageStorageService.shared.delete(filename: scan.imageFilename)
            ImageStorageService.shared.delete(filename: scan.enhancedImageFilename)
            ImageStorageService.shared.delete(filename: scan.autoEnhancedImageFilename)
            ImageStorageService.shared.delete(filename: scan.thumbnailFilename)
            modelContext.delete(scan)
        }
        comparisons.forEach(modelContext.delete)
        cycles.forEach(modelContext.delete)
        periods.forEach(modelContext.delete)
        dailyLogs.forEach(modelContext.delete)
        reminders.forEach(modelContext.delete)
        conversations.forEach(modelContext.delete)
        settingsQuery.forEach(modelContext.delete)
        let freshSettings = UserSettings()
        modelContext.insert(freshSettings)
        appState.settings = freshSettings
        try? modelContext.save()
        appState.toast = "All local data deleted"
    }

    private func startFresh(deleteTestHistory: Bool) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        cycles.forEach(modelContext.delete)
        periods.forEach(modelContext.delete)
        dailyLogs.forEach(modelContext.delete)
        reminders.forEach(modelContext.delete)
        conversations.forEach(modelContext.delete)

        if deleteTestHistory {
            scans.forEach { scan in
                ImageStorageService.shared.delete(filename: scan.imageFilename)
                ImageStorageService.shared.delete(filename: scan.enhancedImageFilename)
                ImageStorageService.shared.delete(filename: scan.autoEnhancedImageFilename)
                ImageStorageService.shared.delete(filename: scan.thumbnailFilename)
                modelContext.delete(scan)
            }
            comparisons.forEach(modelContext.delete)
        } else {
            scans.forEach { $0.cycleRecordID = nil }
        }

        settings?.resetOnboardingState()
        settings?.userName = ""
        settings?.hasMigratedCycleHistory = true
        try? modelContext.save()

        deleteTestsWhenStartingFresh = false
        showStartFresh = false
        appState.activeFlow = nil
        appState.onboardingResetID = UUID()
    }

    /// Shows onboarding again without the data loss `startFresh` causes - this
    /// only flips the completion flag, so scans, cycles and comparisons all
    /// survive. Onboarding writes the cycle dates it collects on the way
    /// through, as it normally would.
    private func replayOnboarding() {
        settings?.hasCompletedOnboarding = false
        try? modelContext.save()
        appState.activeFlow = nil
        appState.onboardingResetID = UUID()
    }

    private func dismissStartFresh() {
        deleteTestsWhenStartingFresh = false
        showStartFresh = false
    }
}

private struct ReminderPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CycleRecord.startDate) private var cycles: [CycleRecord]
    @Query(sort: \Reminder.scheduledDate) private var reminders: [Reminder]
    let settings: UserSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Reminder Preferences")
                            .font(.app(size: LineType.size(28), weight: .bold))
                            .foregroundStyle(Color.lineNavy)
                        Text("Keep the useful nudges, skip the rest. Cycle dates are predictions, not deadlines.")
                            .font(.lineSubheadline())
                            .foregroundStyle(Color.lineNavy.opacity(0.62))
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("AUTOMATIC REMINDERS")
                                .font(.app(.caption, weight: .bold))
                                .foregroundStyle(Color.linePurple)
                            preferenceToggle(
                                "Cycle-aware reminders",
                                detail: "Use your cycle timeline to schedule the alerts below.",
                                isOn: Binding(
                                    get: { settings.autoRemindersEnabled },
                                    set: { value in
                                        settings.autoRemindersEnabled = value
                                        try? modelContext.save()
                                        AppAnalytics.log("linecheck_auto_reminders_toggled", ["enabled": value])
                                        Task { await resyncAutoReminders() }
                                    }
                                )
                            )
                        }
                    }

                    if settings.autoRemindersEnabled {
                        preferenceGroup("Period") {
                            preferenceToggle("Period heads-up", detail: "The day before your predicted period, with the estimated date explained in Calendar.", isOn: binding(\.autoPeriodExpectedRemindersEnabled))
                            preferenceToggle("Period check-in", detail: "Asks whether your period started, right on your expected day.", isOn: binding(\.autoPeriodCheckInRemindersEnabled))
                            preferenceToggle("Period late check-in", detail: "One optional follow-up 7 days after your estimated date, or 14 days if your cycles vary. The Home check-in remains available daily.", isOn: binding(\.autoPeriodLateRemindersEnabled))
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Personal reminders", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.lineSubheadline(.semibold))
                                .foregroundStyle(Color.lineNavy)
                            Text("Medication, body-sign, test-result, and cycle-setup reminders are always set manually from the Calendar, so you choose the exact time.")
                                .font(.lineCaption())
                                .foregroundStyle(Color.lineNavy.opacity(0.60))
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background { LineCheckBrandBackdrop() }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(30)
        .tint(Color.linePurple)
    }

    private func preferenceGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased())
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(Color.linePurple)
                    .padding(.bottom, 4)
                content()
            }
        }
    }

    private func preferenceToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.lineSubheadline(.semibold))
                    .foregroundStyle(Color.lineNavy)
                Text(detail)
                    .font(.lineCaption())
                    .foregroundStyle(Color.lineNavy.opacity(0.58))
            }
            .padding(.vertical, 8)
        }
        .tint(Color.linePurple)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<UserSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                settings[keyPath: keyPath] = value
                try? modelContext.save()
                Task { await resyncAutoReminders() }
            }
        )
    }

    @MainActor
    private func resyncAutoReminders() async {
        guard let cycle = CycleTrackingService.activeCycle(records: cycles),
              let window = CycleTrackingService.window(records: cycles, settings: settings) else { return }
        await ReminderAutomationService.syncPredictedReminders(
            cycle: cycle,
            window: window,
            settings: settings,
            existingReminders: reminders,
            context: modelContext
        )
    }
}

private struct StartFreshDialog: View {
    @Binding var deleteTestHistory: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Start Fresh")
                    .font(.app(size: LineType.size(28), weight: .heavy))
                    .foregroundStyle(Color.lineNavy)
                Text("MenoPlan will clear your cycle dates, period history, body-sign entries, reminders, and Luna chats, then take you through setup again.")
                    .font(.lineSubheadline(.semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $deleteTestHistory) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Also delete saved tests")
                        .font(.lineSubheadline(.bold))
                        .foregroundStyle(Color.lineNavy)
                    Text("Includes test photos and saved comparisons. Leave this off to keep every test on its original date.")
                        .font(.lineCaption())
                        .foregroundStyle(Color.lineNavy.opacity(0.58))
                }
            }
            .tint(Color.linePink)
            .padding(15)
            .background(Color.linePurpleSoft.opacity(0.56), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.secondaryLine)
                Button("Start Fresh", role: .destructive, action: onConfirm)
                    .buttonStyle(.primaryLine)
            }
        }
        .padding(20)
        .frame(maxWidth: 430)
        .background(
            LinearGradient(
                colors: [Color.white, Color.linePurpleSoft.opacity(0.72), Color.linePinkSoft.opacity(0.56)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.82), lineWidth: 1)
        }
        .shadow(color: Color.lineNavy.opacity(0.20), radius: 24, y: 12)
        .preferredColorScheme(.light)
    }
}

private enum ICloudAvailability {
    case checking
    case available
    case noAccount
    case restricted
    case unavailable

    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .couldNotDetermine, .temporarilyUnavailable: self = .unavailable
        @unknown default: self = .unavailable
        }
    }

    var detail: String {
        switch self {
        case .checking: "Checking…"
        case .available: "On · Syncs automatically"
        case .noAccount: "Sign in to iCloud to sync"
        case .restricted: "Restricted on this device"
        case .unavailable: "Temporarily unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "icloud"
        case .available: "checkmark.icloud"
        case .noAccount, .restricted, .unavailable: "exclamationmark.icloud"
        }
    }
}

private struct LineCheckExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct AboutLineCheckSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 18) {
                    header
                    missionCard
                    featureGrid
                    safetyCard
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.primaryLine)
                }
                .padding(.horizontal, 20)
                .padding(.top, max(24, geo.safeAreaInsets.top + 18))
                .padding(.bottom, max(24, geo.safeAreaInsets.bottom + 16))
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.linePurpleSoft.opacity(0.82),
                        Color.lineBackground,
                        Color.linePinkSoft.opacity(0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: LineType.size(15), weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.82))
                        .frame(width: 36, height: 36)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                        .shadow(color: Color.lineNavy.opacity(0.08), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.top, max(18, geo.safeAreaInsets.top + 10))
                .padding(.trailing, 20)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            LunaAvatarView(size: 112)
                .padding(18)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.78))
                        .shadow(color: Color.lineBlue.opacity(0.16), radius: 24, y: 12)
                )

            VStack(spacing: 8) {
                Text("About MenoPlan")
                    .font(.app(size: LineType.size(34), weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                    .multilineTextAlignment(.center)

                Text("A calmer place to track perimenopause and menopause symptoms, cycles and tests.")
                    .font(.lineSubheadline(.medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 18)
    }

    private var missionCard: some View {
        AppCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("What it does")
                        .font(.lineHeadline())
                        .foregroundStyle(Color.lineNavy)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.lineBlue)
                }

                Text("MenoPlan keeps your test photos, saved reads, reminders, calendar context, and Luna guidance in one place. You can use local tools for free, then choose Luna Check when you want an AI-assisted read.")
                    .font(.lineSubheadline())
                    .foregroundStyle(Color.lineNavy.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var featureGrid: some View {
        VStack(spacing: 12) {
            AboutFeatureRow(
                icon: "camera.viewfinder",
                title: "Capture tests",
                detail: "Take or import FSH test photos.",
                tint: Color.linePink
            )
            AboutFeatureRow(
                icon: "wand.and.stars",
                title: "Enhance locally",
                detail: "Use contrast, greyscale, crop, and image tools without Pro.",
                tint: Color.lineTeal
            )
            AboutFeatureRow(
                icon: "calendar",
                title: "Track timing",
                detail: "See symptoms, periods, tests and reminders together.",
                tint: Color.lineBlue
            )
            AboutFeatureRow(
                icon: "bubble.left.and.text.bubble.right",
                title: "Ask Luna",
                detail: "Use Pro for AI reads, saved comparisons, and contextual guidance.",
                tint: Color.linePurple
            )
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: LineType.size(16), weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                    .frame(width: 34, height: 34)
                    .background(Color.lineNavy.opacity(0.08), in: Circle())

                Text("Privacy and safety")
                    .font(.lineHeadline())
                    .foregroundStyle(Color.lineNavy)
            }

            Text("Your saved history stays on this device unless you choose a Luna feature. \(AppConstants.safetyCopy)")
                .font(.lineCaption())
                .foregroundStyle(Color.lineNavy.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.80), lineWidth: 1)
        )
    }
}

private struct AboutFeatureRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: LineType.size(16), weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.lineSubheadline(.semibold))
                    .foregroundStyle(Color.lineNavy)
                Text(detail)
                    .font(.lineCaption())
                    .foregroundStyle(Color.lineNavy.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

