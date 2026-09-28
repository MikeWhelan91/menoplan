import SwiftData
import PopupView
import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(\.lineLayout) private var layout
    @Query(sort: \Scan.createdAt, order: .reverse) private var scans: [Scan]
    @Query(sort: \Reminder.scheduledDate) private var reminders: [Reminder]
    @Query(sort: \CycleRecord.startDate) private var cycleRecords: [CycleRecord]
    @Query(sort: \PeriodEvent.startDate) private var periodEvents: [PeriodEvent]
    // Kept while the cycle-summary helpers are moved into Test Trends; it is
    // no longer rendered on Home.
    @Query(sort: \DailyFertilityLog.date, order: .reverse) private var dailyLogs: [DailyFertilityLog]
    @Query(sort: \DailyHealthMetrics.date) private var healthMetrics: [DailyHealthMetrics]
    @Query(sort: \NoticedSignal.lastSeen) private var noticedSignals: [NoticedSignal]
    private var settings: UserSettings? { appState.settings }
    private var nextReminder: Reminder? {
        reminders.first { !$0.isCompleted && $0.scheduledDate >= .now }
    }

    @State private var reminderDraft: HomeReminderDraft?
    @State private var showPeriodStartCheckIn = false
    @State private var showFocusSheet = false
    @State private var showAppointmentSheet = false
    @State private var showSummary = false
    @State private var logRequest: HomeLogRequest?
    @State private var showPersonalization = false
    @State private var showBodySignals = false
    @State private var showHealthPrompt = false
    /// Day of the latest postmenopausal bleed whose nudge was dismissed.
    @AppStorage("homeBleedingNudgeDismissedDay") private var bleedingNudgeDismissedDay = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    journeyOverview
                    urgentNudges
                    homeCards
                    todayPanel
                    quickLinks
                }
                // On compact these resolve to the 16/24 this screen has always
                // used, so the iPhone layout is unchanged.
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, layout.topPadding)
                .lineBottomInset()
                // The single column keeps its phone proportions on iPad instead
                // of being stretched to the full width — a fertility curve drawn
                // across 900pt flattens into a straight line.
                .lineContentColumn()
            }
            .background { LineCheckBrandBackdrop() }
            .sheet(item: $reminderDraft) { draft in
                ReminderEditorView(initialType: draft.type, initialDate: draft.date, initialTitle: draft.title)
            }
            .popup(isPresented: $showBodySignals) {
                BodySignalsPopup(
                    signals: homeSignals,
                    onAskLuna: {
                        showBodySignals = false
                        appState.pendingLunaPrompt = "What do these mean for my cycle? " + homeSignals.map(\.title).joined(separator: "; ")
                        appState.selectedTab = .assistant
                    },
                    onClose: { showBodySignals = false },
                    onConnectHealth: HealthKitConnection.canOffer(settings) ? {
                        showBodySignals = false
                        connectAppleHealth(source: "body_signals_popup")
                    } : nil
                )
            } customize: {
                // Opaque presents over the whole window, so the dimming
                // covers the tab bar as well as Home.
                $0.type(.default)
                    .position(.center)
                    .displayMode(.sheet)
                    .closeOnTap(false)
                    .closeOnTapOutside(true)
                    .backgroundColor(Color.lineNavy.opacity(0.30))
                    .animation(.easeOut(duration: 0.2))
            }
            .popup(isPresented: $showHealthPrompt) {
                HealthConnectPromptPopup(
                    onConnect: {
                        showHealthPrompt = false
                        connectAppleHealth(source: "home_reminder")
                    },
                    onNotNow: { showHealthPrompt = false },
                    onNeverAsk: {
                        showHealthPrompt = false
                        settings?.healthPromptOptOutValue = true
                        try? modelContext.save()
                    }
                )
            } customize: {
                $0.type(.default)
                    .position(.center)
                    .displayMode(.sheet)
                    .closeOnTap(false)
                    .closeOnTapOutside(true)
                    .backgroundColor(Color.lineNavy.opacity(0.30))
                    .animation(.easeOut(duration: 0.2))
            }
            // Occasional nudge to connect Apple Health - paced by
            // HealthKitConnection.shouldShowReminder, never over another popup.
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !showBodySignals, HealthKitConnection.shouldShowReminder(settings), let settings else {
                    try? modelContext.save()
                    return
                }
                HealthKitConnection.recordReminderShown(settings)
                try? modelContext.save()
                showHealthPrompt = true
            }
            // Keep the calendar's "What MenoPlan noticed" history current.
            .task(id: signalHistoryKey) {
                guard settings != nil else { return }
                CycleSignalHistory.record(homeSignals, context: modelContext)
            }
            .sheet(isPresented: $showFocusSheet) {
                FocusSymptomSheet(initial: focus) { chosen in
                    settings?.focusSymptoms = chosen
                    try? modelContext.save()
                }
            }
            .sheet(isPresented: $showSummary) {
                if let settings {
                    AppointmentSummaryView(settings: settings)
                }
            }
            .sheet(isPresented: $showAppointmentSheet) {
                AppointmentDateSheet(initial: settings?.upcomingAppointment) { date in
                    settings?.nextAppointmentDate = date
                    try? modelContext.save()
                }
            }
            .sheet(item: $logRequest) { request in
                DailyFertilityLogEditor(date: request.date, existing: log(for: request.date), initialSection: request.section)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showPersonalization) {
                if let settings {
                    PersonalizationQuizSheet(settings: settings)
                }
            }
            .sheet(isPresented: $showPeriodStartCheckIn) {
                if let settings {
                    PeriodStartUpdateView(settings: settings, initialDate: .now)
                        .presentationDetents(layout.isRegular ? [.large] : [.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
        .tint(Color.lineBlue)
    }

    private var fertilityWindow: FertilityWindow? {
        CycleTrackingService.window(records: cycleRecords, settings: settings)
    }

    private var activeCycle: CycleRecord? { CycleTrackingService.activeCycle(records: cycleRecords) }

    private var stage: MenopauseStage { settings?.menopauseStage ?? .perimenopause }
    private var tracksCycle: Bool { stage.tracksCycle }

    private var realLogs: [DailyFertilityLog] {
        dailyLogs.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
    }

    private var focus: [String] { settings?.focusSymptoms ?? FocusSymptoms.defaults }

    private var cycleChange: CycleChangeSummary {
        let sample = "[LineCheck Screenshot Sample]"
        let starts = periodEvents.filter { !$0.notes.contains(sample) }.map(\.startDate)
            + cycleRecords.filter { !$0.notes.contains(sample) }.map(\.startDate)
        return CycleChangeCalculator.summary(periodStarts: starts)
    }

    private var recentChange: RecentChange? {
        RecentChangeCalculator.observation(logs: realLogs, focus: focus, hrtChanged: settings?.hrtLastChangedDate)
    }

    private var loggedDaysLast30: Int {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: .now)) else { return 0 }
        return Set(realLogs.filter { $0.hasContent && $0.date >= cutoff }.map { calendar.startOfDay(for: $0.date) }).count
    }

    /// Within a week of an appointment, preparing for it comes first.
    private var appointmentIsSoon: Bool {
        guard let date = settings?.upcomingAppointment else { return false }
        return (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: date).day ?? 99) <= 7
    }

    /// Check-in, then what's changed, the appointment, today's HRT (only
    /// for people using it) and the cycle (only while periods continue).
    @ViewBuilder
    private var homeCards: some View {
        if appointmentIsSoon { appointmentCard }
        CheckInCard(
            log: log(for: .now),
            focus: focus,
            onImpact: { impact in editToday { $0.dayImpact = impact } },
            onAdvance: { name in editToday { FocusSymptoms.advance(name, in: $0) } },
            onSetSeverity: { name, severity in editToday { $0.setSeverity(severity, for: name) } },
            onCount: { name, delta in
                editToday { FocusSymptoms.setCount((FocusSymptoms.count(name, in: $0) ?? 0) + delta, for: name, in: $0) }
            },
            onOpenLog: { logRequest = HomeLogRequest(date: .now, section: nil) },
            onEditFocus: { showFocusSheet = true }
        )
        homeNudges
        if let recentChange {
            RecentChangeCard(change: recentChange, onOpenTrends: openTrends)
        }
        if !appointmentIsSoon { appointmentCard }
        if let settings, !settings.hrtRegimen.isEmpty {
            HRTTodayCard(
                regimen: settings.hrtRegimen,
                taken: log(for: .now)?.hrtTaken ?? [],
                doseText: settings.hrtDoseText,
                lastChanged: settings.hrtLastChangedDate,
                reminderTime: settings.hrtReminderTime,
                onToggle: { item in
                    editToday { log in
                        log.hrtTaken = log.hrtTaken.contains(item) ? log.hrtTaken.filter { $0 != item } : (log.hrtTaken + [item]).sorted()
                    }
                },
                onReminder: { setHRTReminder($0) },
                onEdit: { appState.selectedTab = .settings }
            )
        }
        if tracksCycle, cycleChange.lastPeriodStart != nil {
            CycleChangeCard(
                summary: cycleChange,
                onLogPeriod: { showPeriodStartCheckIn = true },
                onOpenCalendar: { appState.selectedTab = .calendar },
                onSwitchStage: {
                    withAnimation(.snappy) { settings?.menopauseStage = .postmenopause }
                    try? modelContext.save()
                }
            )
        }
    }

    private var appointmentCard: some View {
        AppointmentCard(
            appointment: settings?.upcomingAppointment,
            loggedDays: loggedDaysLast30,
            onPrepare: { showSummary = true },
            onSetDate: { showAppointmentSheet = true }
        )
    }

    private func openTrends() {
        appState.showTrendsRequested = true
        appState.selectedTab = .calendar
    }

    /// Applies a check-in change to today's log, creating it on first touch.
    private func editToday(_ change: (DailyFertilityLog) -> Void) {
        let today = Calendar.current.startOfDay(for: .now)
        let entry: DailyFertilityLog
        if let existing = log(for: today) {
            entry = existing
        } else {
            entry = DailyFertilityLog(date: today)
            modelContext.insert(entry)
        }
        withAnimation(.snappy) { change(entry) }
        entry.updatedAt = .now
        try? modelContext.save()
    }

    private func setHRTReminder(_ time: Date?) {
        guard let settings else { return }
        settings.hrtReminderTime = time
        try? modelContext.save()
        guard let time else {
            NotificationService().cancelDailyHRTReminder()
            return
        }
        Task {
            let service = NotificationService()
            guard await service.requestPermission() else { return }
            try? await service.scheduleDailyHRTReminder(at: time)
        }
    }

    /// Most recent bleeding logged in the last 30 days, for the
    /// postmenopause nudge.
    private var recentPostmenopausalBleed: Date? {
        guard stage == .postmenopause else { return nil }
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: .now)) else { return nil }
        return dailyLogs.first { $0.flowIntensity != nil && $0.date >= cutoff }.map { calendar.startOfDay(for: $0.date) }
    }

    // MARK: - Greeting

    private var journeyOverview: some View {
        VStack(alignment: .leading, spacing: 9) {
            TimelineView(.everyMinute) { timeline in
                Text(HomeGreeting.title(name: settings?.userName ?? "", at: timeline.date))
                    .font(.app(size: LineType.size(28), weight: .heavy))
                    .foregroundStyle(Color.lineNavy)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            // A retained Home tab must refresh immediately after a long
            // background session, as well as at minute boundaries while open.
            .id(scenePhase)
            .overlay(alignment: .trailing) { bodySignalsButton }

            HomeWeekStrip(
                window: nil,
                cycleRecords: cycleRecords,
                periodEvents: tracksCycle ? periodEvents : [],
                loggedDays: loggedDays
            ) { day in
                logRequest = HomeLogRequest(date: day, section: nil)
            }
            .padding(.top, 2)

            if tracksCycle, cycleChange.lastPeriodStart == nil {
                Button {
                    appState.calendarSetupRequest = .ovulation
                    appState.selectedTab = .calendar
                } label: {
                    VStack(spacing: 3) {
                        Text("Add your last period")
                            .font(.app(size: LineType.size(17), weight: .bold))
                            .foregroundStyle(Color.linePink)
                            .underline()
                        Text(homeTimelineDetail)
                            .font(.app(.caption, weight: .medium))
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens cycle setup in Calendar")
            }
        }
        .padding(.vertical, 4)
    }

    private var loggedDays: Set<Date> {
        let calendar = Calendar.current
        let logDays = dailyLogs.filter(\.hasContent).map { calendar.startOfDay(for: $0.date) }
        let scanDays = scans.prefix(60).map { calendar.startOfDay(for: $0.createdAt) }
        return Set(logDays + scanDays)
    }

    private func log(for date: Date) -> DailyFertilityLog? {
        dailyLogs.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: - Setup checklist (for people who skipped onboarding)

    private func cycleIsSetUp(_ settings: UserSettings) -> Bool {
        settings.lastPeriodStartDate != nil || cycleRecords.contains { !$0.notes.contains("[LineCheck Screenshot Sample]") }
    }

    private func healthIsSetUp(_ settings: UserSettings) -> Bool {
        settings.healthKitSyncEnabled || !HealthKitService.shared.isAvailable
    }

    private func showsSetupChecklist(_ settings: UserSettings) -> Bool {
        settings.skippedOnboardingSetupValue == true
            && settings.dismissedSetupChecklistValue != true
            // Apple Health is optional (plenty of people have no Health
            // data), so it never keeps the checklist open on its own.
            && !((cycleIsSetUp(settings) || !settings.menopauseStage.tracksCycle) && settings.hasCompletedPersonalization)
    }

    /// Everything onboarding would have asked, one tap each, ticking off as
    /// it's done - so skipping setup to scan never costs anything later.
    private func setupChecklist(_ settings: UserSettings) -> some View {
        let items: [(done: Bool, optional: Bool, title: String, detail: String, symbol: String, action: () -> Void)] = [
            (cycleIsSetUp(settings), false, "Your cycle", "Last period and cycle length, to see how it's changing", "calendar", {
                appState.calendarSetupRequest = .ovulation
                appState.selectedTab = .calendar
            }),
            (settings.hasCompletedPersonalization, false, "About you", "Your name and a few questions that tailor results", "person.text.rectangle", {
                showPersonalization = true
            }),
            (healthIsSetUp(settings), true, "Apple Health", "If you use it, fill in hot flushes, sleep, periods and more automatically", "heart.text.square", {
                connectAppleHealth(source: "setup_checklist")
            })
        ].filter { $0.title != "Your cycle" || settings.menopauseStage.tracksCycle }
        let remaining = items.filter { !$0.done && !$0.optional }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish setting up")
                        .font(.app(size: LineType.size(18), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                    Text(remaining == 1 ? "1 step left" : "\(remaining) steps left")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                }
                Spacer()
                Button {
                    withAnimation(.snappy) { settings.dismissedSetupChecklistValue = true }
                    try? modelContext.save()
                } label: {
                    Image(systemName: "xmark")
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(Color.lineNavy.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button(action: item.action) {
                    HStack(spacing: 12) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : item.symbol)
                            .font(.system(size: LineType.size(16), weight: .bold))
                            .foregroundStyle(item.done ? Color.lineTeal : Color.linePurple)
                            .frame(width: 34, height: 34)
                            .background((item.done ? Color.lineTeal : Color.linePurple).opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .font(.app(.subheadline, weight: .bold))
                                    .foregroundStyle(Color.lineNavy.opacity(item.done ? 0.5 : 1))
                                    .strikethrough(item.done, color: Color.lineNavy.opacity(0.3))
                                if item.optional && !item.done {
                                    Text("Optional")
                                        .font(.app(size: LineType.size(10), weight: .heavy))
                                        .foregroundStyle(Color.lineNavy.opacity(0.5))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.lineNavy.opacity(0.06), in: Capsule())
                                }
                            }
                            Text(item.detail)
                                .font(.app(.caption))
                                .foregroundStyle(Color.lineNavy.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        if !item.done {
                            Image(systemName: "chevron.right")
                                .font(.app(.caption, weight: .bold))
                                .foregroundStyle(Color.lineNavy.opacity(0.3))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.done)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.97), Color.linePurple.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.linePurple.opacity(0.18)))
    }

    private func connectAppleHealth(source: String) {
        guard let settings else { return }
        Task { appState.toast = await HealthKitConnection.connect(settings: settings, context: modelContext, source: source) }
    }

    /// Re-records history when the day or the underlying data changes.
    private var signalHistoryKey: String {
        "\(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)|\(dailyLogs.count)|\(healthMetrics.count)|\(scans.count)|\(cycleRecords.count)|\(dailyLogs.first?.updatedAt.timeIntervalSince1970 ?? 0)"
    }

    private func signalInputs(settings: UserSettings) -> CycleSignalInputs {
        CycleSignalInputs(
            window: fertilityWindow,
            activeCycle: activeCycle,
            logs: dailyLogs,
            metrics: healthMetrics,
            scans: Array(scans),
            profile: settings.healthProfile
        )
    }

    /// Everything worth showing behind Home's info button.
    private var homeSignals: [CycleSignal] {
        guard let settings else { return [] }
        return CycleSignalsEngine.signals(for: .home, signalInputs(settings: settings))
    }

    /// Beside the greeting. A dot shows when
    /// there's something new to see; pink when one is worth a look.
    /// Signals the person hasn't opened the popup to see yet. One with no
    /// history row yet (recorded a moment later) counts as unseen.
    private var unseenSignals: [CycleSignal] {
        homeSignals.filter { signal in
            noticedSignals.last { $0.signalID == signal.id }?.seenAt == nil
        }
    }

    private func markSignalsSeen() {
        guard settings != nil else { return }
        CycleSignalHistory.record(homeSignals, context: modelContext)
        let ids = Set(homeSignals.map(\.id))
        let rows = (try? modelContext.fetch(FetchDescriptor<NoticedSignal>())) ?? []
        for id in ids {
            if let latest = rows.filter({ $0.signalID == id }).max(by: { $0.lastSeen < $1.lastSeen }), latest.seenAt == nil {
                latest.seenAt = .now
            }
        }
        try? modelContext.save()
    }

    private var bodySignalsButton: some View {
        let signals = unseenSignals
        let hasAttention = signals.contains { $0.tone == .attention }
        return Button {
            markSignalsSeen()
            showBodySignals = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: LineType.size(20), weight: .semibold))
                .foregroundStyle(Color.linePurple)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.85), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if !signals.isEmpty {
                        Text("\(signals.count)")
                            .font(.app(size: LineType.size(10), weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(hasAttention ? Color.linePink : Color.linePurple, in: Circle())
                            .offset(x: 3, y: -3)
                    }
                }
                .shadow(color: Color.linePurple.opacity(0.12), radius: 6, y: 3)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("What your body is telling us")
        .accessibilityValue(signals.isEmpty ? "Nothing new" : "\(signals.count) new observations")
    }

    // MARK: - Nudges

    /// The one prompt allowed above the check-in: bleeding after menopause.
    @ViewBuilder
    private var urgentNudges: some View {
        if let bleed = recentPostmenopausalBleed, bleed.timeIntervalSince1970 > bleedingNudgeDismissedDay {
            HomeNudgeCard(
                symbol: "stethoscope",
                tint: .linePink,
                title: "Please get this bleeding checked",
                message: "You logged bleeding on \(DateFormatting.shortDate.string(from: bleed)). Bleeding after menopause should always be looked at by a GP or clinician. It's often nothing serious, but it needs checking.",
                onDismiss: {
                    withAnimation(.snappy) { bleedingNudgeDismissedDay = bleed.timeIntervalSince1970 }
                }
            ) {
                EmptyView()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    @ViewBuilder
    private var homeNudges: some View {
        if let settings {
            if settings.healthProfile.shouldSuggestDoctor(), !settings.dismissedDoctorSuggestion {
                HomeNudgeCard(
                    symbol: "stethoscope",
                    tint: .linePurple,
                    title: "It may help to talk to a doctor",
                    message: "Under 45, doctors usually check menopause-type symptoms with a blood test, as the causes and support can differ. Your MenoPlan record can help that conversation.",
                    onDismiss: {
                        withAnimation(.snappy) { settings.dismissedDoctorSuggestion = true }
                        try? modelContext.save()
                    }
                ) {
                    Button {
                        appState.showTrendsRequested = true
                        appState.selectedTab = .calendar
                    } label: {
                        Label("Prepare a report in Test Trends", systemImage: "doc.text")
                            .font(.app(.subheadline, weight: .bold))
                    }
                    .foregroundStyle(Color.linePurple)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            if showsSetupChecklist(settings) {
                setupChecklist(settings)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            if settings.hasCompletedOnboarding, !settings.hasCompletedPersonalization, !settings.dismissedPersonalizationPrompt, !showsSetupChecklist(settings) {
                HomeNudgeCard(
                    symbol: "person.crop.circle.badge.questionmark",
                    tint: .linePink,
                    title: "Make MenoPlan fit you",
                    message: "A few quick questions so MenoPlan and Luna take your situation into account.",
                    onDismiss: {
                        withAnimation(.snappy) { settings.dismissedPersonalizationPrompt = true }
                        try? modelContext.save()
                    }
                ) {
                    Button("Answer a few questions") { showPersonalization = true }
                        .buttonStyle(.primaryLine)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    private var homeTimelineDetail: String {
        "While you still have periods, logging them shows how your cycle is changing."
    }

    private var quickLinks: some View {
        HStack(spacing: 10) {
            homeLink("Ask Luna", imageName: "HomeLunaIcon", tint: .linePurple) { appState.selectedTab = .assistant }
            // FSH is one data point, so the test reader is a tool here rather
            // than a hero.
            homeLink("FSH Test", imageName: nil, symbol: "camera.viewfinder", tint: .linePink) {
                appState.startScan(testType: .ovulation)
            }
            homeLink("Trends", imageName: "HomeTrendsIcon", tint: .linePurple, action: openTrends)
        }
        // The surrounding VStack's 14pt spacing is tuned for a phone; on iPad
        // this row sits between two large cards and needs more room to read as
        // its own band rather than as part of them.
        .padding(.vertical, layout.isRegular ? 10 : 0)
    }

    private func homeLink(_ title: String, imageName: String?, symbol: String? = nil, tint: Color, iconSize: CGSize = CGSize(width: 48, height: 38), showsProBadge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: layout.scaled(8)) {
                Group {
                    if let imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                    } else if let symbol {
                        Image(systemName: symbol)
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.semibold)
                            .foregroundStyle(LinearGradient(colors: [Color.linePink, Color.linePurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .padding(3)
                    }
                }
                .frame(width: layout.scaled(LineType.size(iconSize.width)), height: layout.scaled(LineType.size(iconSize.height)))
                Text(title)
                    .font(.app(size: layout.scaled(13), weight: .bold))
                    .foregroundStyle(Color.lineNavy)
            }
            .frame(maxWidth: .infinity, minHeight: layout.scaled(layout.isRegular ? 116 : 82))
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.96), tint.opacity(0.09)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.13)))
            .overlay(alignment: .topTrailing) {
                if showsProBadge {
                    Text("PRO")
                        .font(.system(size: layout.scaled(9), weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.linePurple, in: Capsule())
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// A "Next step" nudge used to sit here too, alongside the reminder
    /// panel (or alone, full-width, when there was no active reminder) -
    /// removed since it was a distraction from the reminder itself; this
    /// panel now shows only real, user-scheduled reminders, nothing when
    /// there isn't one.
    private var todayPanel: some View {
        Group {
            if let nextReminder {
                nextReminderPanel(nextReminder)
            }
        }
    }

    private var reminderChevron: some View {
        Image(systemName: "chevron.right")
            .font(.app(.caption, weight: .bold))
            .foregroundStyle(Color.linePurple.opacity(0.60))
    }

    private func nextReminderPanel(_ reminder: Reminder) -> some View {
        Button {
            appState.selectedTab = .calendar
        } label: {
            // The card is a stacked title/date block on a phone. On iPad that
            // left a short two-line block against the card's leading edge with
            // the rest of a 720pt row empty, so the regular layout runs it on
            // one line and moves the timestamp over beside the chevron - the
            // content then spans the card instead of hugging one side.
            HStack(alignment: .center, spacing: layout.isRegular ? 16 : 12) {
                Image("CalendarReminderIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: layout.isRegular ? 56 : 50, height: layout.isRegular ? 52 : 46)

                if layout.isRegular {
                    Text(HomeReminderTitle.display(for: reminder))
                        .font(.app(size: LineType.size(19), weight: .semibold))
                        .foregroundStyle(Color.lineNavy)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 16)

                    Text(HomeReminderTitle.scheduleLabel(for: reminder))
                        .font(.app(size: LineType.size(15), weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()

                    reminderChevron
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(HomeReminderTitle.display(for: reminder))
                            .font(.app(size: LineType.size(16), weight: .semibold))
                            .foregroundStyle(Color.lineNavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)

                        Text(HomeReminderTitle.scheduleLabel(for: reminder))
                            .font(.app(.caption, weight: .medium))
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                }
            }
            .overlay(alignment: .trailing) {
                // Regular puts the chevron in the stack itself, after the
                // timestamp, so it isn't overlaid on top of it.
                if layout.isCompact {
                    reminderChevron
                }
            }
            .padding(.horizontal, layout.isRegular ? 18 : 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: layout.isRegular ? 72 : 64)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.94), Color.linePurple.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.linePurple.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

}

enum HomeReminderTitle {
    static func scheduleLabel(for reminder: Reminder) -> String {
        let dateAndTime = "\(DateFormatting.shortDate.string(from: reminder.scheduledDate)) · \(DateFormatting.shortTime.string(from: reminder.scheduledDate))"
        return reminder.isAutoGenerated && reminder.reminderType == .periodExpected
            ? "Reminder on \(dateAndTime)"
            : dateAndTime
    }

    static func display(for reminder: Reminder, calendar: Calendar = .current) -> String {
        guard reminder.isAutoGenerated else { return reminder.title }
        switch reminder.reminderType {
        case .periodExpected:
            let expectedDate = calendar.date(byAdding: .day, value: 1, to: reminder.scheduledDate) ?? reminder.scheduledDate
            return "Period estimate · \(DateFormatting.shortDate.string(from: expectedDate))"
        case .periodCheckIn:
            return "Period check-in · \(DateFormatting.shortDate.string(from: reminder.scheduledDate))"
        default:
            return reminder.title
        }
    }
}

private struct HomeLogRequest: Identifiable {
    let date: Date
    let section: DailyLogSection?
    var id: String { "\(date.timeIntervalSince1970)-\(section?.rawValue ?? "all")" }
}

private struct HomeReminderDraft: Identifiable {
    let type: ReminderType
    let date: Date
    let title: String
    var id: String { "\(type.rawValue)-\(title)-\(date.timeIntervalSince1970)" }
}

struct ScanRow: View {
    var scan: Scan

    var body: some View {
        HStack(spacing: 12) {
            ScanThumbnailView(scan: scan)

            VStack(alignment: .leading, spacing: 3) {
                Text(scan.testType.title)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy)

                Text(scan.resultType.title)
                    .font(.app(.caption))
                    .foregroundStyle(scan.resultType.tint)

                Text("\(DateFormatting.shortDate.string(from: scan.createdAt)), \(DateFormatting.shortTime.string(from: scan.createdAt))")
                    .font(.app(.caption2))
                    .foregroundStyle(Color.lineNavy.opacity(0.55))
            }

            Spacer()

            ResultBadge(result: scan.resultType)

            if scan.certaintyPercentage > 0 {
                Text("\(scan.certaintyPercentage)%")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.55))
            }
        }
    }
}

private struct ScanThumbnailView: View {
    var scan: Scan

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(red: 0.975, green: 0.978, blue: 0.986))

            if let image = ImageStorageService.shared.load(scan.compactImageRef) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                TestIllustration(testType: scan.testType, result: scan.resultType, compact: true)
                    .scaleEffect(0.72)
            }
        }
        .frame(width: 66, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.07)))
    }
}
