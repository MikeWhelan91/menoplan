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
    @State private var showPredictionWhy = false
    @State private var showPeriodStartCheckIn = false
    @AppStorage("homePeriodCheckInSnoozedCycleID") private var checkInSnoozedCycleID = ""
    @AppStorage("homePeriodCheckInDismissedUntilNextDay") private var checkInSnoozedUntil = 0.0
    @State private var logRequest: HomeLogRequest?
    @State private var storyLaunch: HomeStoryLaunch?
    @State private var showPersonalization = false
    @State private var showPregnancyDetails = false
    @State private var showPregnancyReveal = false
    @State private var showBodySignals = false
    @State private var showHealthPrompt = false
    /// "<cycle start epoch>|story,story" - which insight cards have been
    /// opened this cycle, so unseen ones keep their highlight ring.
    @AppStorage("homeStoriesSeen") private var storiesSeenRaw = ""
    @AppStorage("homePregnancyPromptSnoozedUntil") private var pregnancyPromptSnoozedUntil = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    journeyOverview
                    homeNudges
                    if activeCycle?.pregnancyState != .confirmedPregnant {
                        scanTiles
                    }
                    todayPanel
                    quickLinks
                    recentScansPanel
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
            .sheet(isPresented: $showPredictionWhy) {
                if let window = fertilityWindow, let settings {
                    PredictionWhySheet(window: window, cycle: activeCycle, settings: settings)
                }
            }
            .sheet(item: $logRequest) { request in
                DailyFertilityLogEditor(date: request.date, existing: log(for: request.date), initialSection: request.section)
                    .presentationDetents([.large])
            }
            .fullScreenCover(item: $storyLaunch) { launch in
                if let timeline = conceptionTimeline {
                    CycleStoryViewer(
                        timeline: timeline,
                        stories: stories(for: timeline),
                        index: min(launch.index, stories(for: timeline).count - 1),
                        onSeen: markStorySeen,
                        onAction: handleStoryAction
                    )
                }
            }
            .sheet(isPresented: $showPersonalization) {
                if let settings {
                    PersonalizationQuizSheet(settings: settings)
                }
            }
            .sheet(isPresented: $showPregnancyDetails) {
                if let pregnancyProgress {
                    PregnancyDetailSheet(
                        progress: pregnancyProgress,
                        completedMilestones: activeCycle?.completedMilestones ?? [],
                        onPregnancyEnded: { changePregnancyMode(PregnancyModeService.markPregnancyEnded) },
                        onNotPregnant: { changePregnancyMode(PregnancyModeService.returnToCycleTracking) },
                        onSetDueDate: { date in
                            changePregnancyMode { cycle, settings, context in
                                await PregnancyModeService.setManualDueDate(date, cycle: cycle, settings: settings, context: context)
                            }
                        },
                        onResetDueDate: { changePregnancyMode(PregnancyModeService.clearManualDueDate) },
                        onToggleMilestone: { title in
                            activeCycle?.toggleMilestone(title)
                            try? modelContext.save()
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: $showPregnancyReveal) {
                if let pregnancyProgress {
                    PregnancyRevealView(progress: pregnancyProgress, name: settings?.userName ?? "") {
                        showPregnancyReveal = false
                    }
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

    private var shouldShowPeriodCheckIn: Bool {
        guard settings != nil else { return false }
        return HomePeriodCheckInPolicy.shouldShow(
            on: .now, window: fertilityWindow, cycle: activeCycle, periods: periodEvents,
            snoozedCycleID: checkInSnoozedCycleID, snoozedUntil: checkInSnoozedUntil
        )
    }

    private func snoozePeriodCheckIn() {
        guard let activeCycle else { return }
        checkInSnoozedCycleID = activeCycle.id.uuidString
        checkInSnoozedUntil = (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now).timeIntervalSince1970
    }

    private var periodCheckInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Has your period started?", systemImage: "calendar.badge.clock")
                .font(.app(.headline, weight: .bold))
                .foregroundStyle(Color.lineNavy)
            if let expected = fertilityWindow?.nextPeriodDate {
                Text("Your period \(Calendar.current.isDateInToday(expected) ? "is" : "was") estimated around \(DateFormatting.shortDate.string(from: expected)). That's only a prediction—not a period we've logged.")
                    .font(.app(.subheadline))
                    .foregroundStyle(Color.lineNavy.opacity(0.7))
            }
            Text("If it hasn't started, your current cycle stays open. If it has, log the actual first day—even if that date is different from the estimate.")
                .font(.app(.caption))
                .foregroundStyle(Color.lineNavy.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Not yet") { snoozePeriodCheckIn() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("Log first day") { showPeriodStartCheckIn = true }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .font(.app(.subheadline, weight: .semibold))
            Text("‘Not yet’ hides this Home check-in until tomorrow. It doesn't record a period or change your reminder settings.")
                .font(.app(.caption2))
                .foregroundStyle(Color.lineNavy.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.linePurple.opacity(0.22)))
    }

    // MARK: - Live Cycle Plan

    /// This is deliberately a local, evidence-led summary rather than another
    /// chat response. It gives the user one concrete next step, while keeping
    /// predictions clearly labelled as estimates.
    private struct CyclePlan {
        let title: String
        let detail: String
        let nextStep: String
        let uncertainty: String
        let icon: String
        let tint: Color
        let evidence: [String]
    }

    private var liveCyclePlan: some View {
        let plan = currentCyclePlan
        let isPro = settings?.proUnlocked == true

        return Button {
            guard !isPro else { return }
            appState.paywallSource = "live_cycle_plan_locked"
            appState.showPremium = true
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: plan.icon)
                        .font(.app(.title3, weight: .bold))
                        .foregroundStyle(plan.tint)
                        .frame(width: 36, height: 36)
                        .background(plan.tint.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Cycle Plan")
                            .font(.app(.headline, weight: .heavy))
                            .foregroundStyle(Color.lineNavy)
                        Text("Your signals, translated into one next step")
                            .font(.app(.caption, weight: .medium))
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                    }

                    Spacer()
                    if isPro {
                        Text("PRO")
                            .font(.app(.caption2, weight: .heavy))
                            .foregroundStyle(plan.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(plan.tint.opacity(0.11), in: Capsule())
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(Color.linePurple)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.app(.title3, weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                    Text(plan.detail)
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Color.lineNavy.opacity(0.08))

                Label {
                    Text(plan.nextStep)
                        .font(.app(.subheadline, weight: .bold))
                } icon: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .foregroundStyle(plan.tint)

                if isPro {
                    if !plan.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Based on")
                                .font(.app(.caption, weight: .heavy))
                                .foregroundStyle(Color.lineNavy.opacity(0.48))
                            Text(plan.evidence.joined(separator: " · "))
                                .font(.app(.caption, weight: .medium))
                                .foregroundStyle(Color.lineNavy.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(plan.uncertainty)
                        .font(.app(.caption))
                        .foregroundStyle(Color.lineNavy.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Unlock the full signal summary and tailored next steps.")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Color.linePurple)
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.97), plan.tint.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(plan.tint.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityHint(isPro ? "Shows your current cycle summary." : "Opens MenoPlan Pro.")
    }

    private var currentCyclePlan: CyclePlan {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let recentOPKs = scans.filter {
            $0.testType == .ovulation &&
            !$0.excludedFromCalculations &&
            $0.createdAt <= .now &&
            $0.createdAt >= (calendar.date(byAdding: .day, value: -7, to: today) ?? .distantPast)
        }
        let latestOPK = recentOPKs.max { $0.createdAt < $1.createdAt }
        let recentLogs = dailyLogs.filter {
            (calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: today).day ?? -99) >= -6
        }
        let bbtCount = recentLogs.filter { $0.basalBodyTemperatureCelsius != nil }.count
        let recentMucus = recentLogs.sorted(by: { $0.date > $1.date }).compactMap(\.cervicalMucusRaw).first
        var evidence: [String] = []
        if let latestOPK { evidence.append("Latest OPK: \(latestOPK.resultType.badgeTitle)") }
        if let recentMucus { evidence.append("Mucus: \(recentMucus)") }
        if bbtCount > 0 { evidence.append("\(bbtCount) BBT \(bbtCount == 1 ? "reading" : "readings") this week") }
        if settings?.healthKitSyncEnabled == true { evidence.append("Apple Health connected") }

        guard let window = fertilityWindow else {
            return CyclePlan(
                title: "Set up your cycle plan",
                detail: "Add a period start to place your tests, symptoms, and activities in cycle context.",
                nextStep: "Add your last period in Calendar",
                uncertainty: "Without a cycle start, MenoPlan cannot estimate a fertile window or expected period.",
                icon: "calendar.badge.plus",
                tint: .linePurple,
                evidence: evidence
            )
        }

        if activeCycle?.pregnancyState == .confirmedPregnant {
            return CyclePlan(
                title: "Pregnancy confirmed",
                detail: "Cycle predictions are paused while your saved results stay available in History.",
                nextStep: "Use History to keep your results together",
                uncertainty: "This is an organisational summary, not medical advice.",
                icon: "heart.fill",
                tint: .linePink,
                evidence: evidence
            )
        }

        if window.isPastExpectedPeriod(on: today) {
            return CyclePlan(
                title: "Cycle longer than estimated",
                detail: "No new period is logged after the expected date. The cycle remains anchored to your last recorded start.",
                nextStep: "If it hasn't started, no action is needed. When it does, log the actual first day in Calendar.",
                uncertainty: "The date was an estimate; a late period does not establish when ovulation happened.",
                icon: "calendar.badge.clock",
                tint: .linePurple,
                evidence: evidence
            )
        }

        if let latestOPK, latestOPK.resultType == .peak {
            let peakApplied = activeCycle?.ovulationSource == .testSupported
                && activeCycle?.id == latestOPK.cycleRecordID
            return CyclePlan(
                title: "LH peak logged",
                detail: peakApplied ? "Your latest ovulation test is marked Peak, and this cycle's estimate reflects it." : "Your latest ovulation test is marked Peak. It is saved in your history, but this cycle's estimate may use other information.",
                nextStep: "If you are trying to conceive, today and tomorrow are useful days to try",
                uncertainty: "An LH peak supports timing; it does not by itself confirm ovulation. Keep logging tests or temperatures if you want a fuller picture.",
                icon: "chart.line.uptrend.xyaxis",
                tint: .linePurple,
                evidence: evidence
            )
        }

        if activeCycle?.confirmedOvulationDate != nil {
            return CyclePlan(
                title: "Ovulation timing recorded",
                detail: "Your calendar is using a recorded ovulation date for this cycle rather than a general estimate.",
                nextStep: "Keep logging only the signals that feel useful to you",
                uncertainty: "Cycle timing can vary. This view describes your saved records and does not confirm a health outcome.",
                icon: "checkmark.seal.fill",
                tint: .lineTeal,
                evidence: evidence
            )
        }

        if let latestOPK, latestOPK.resultType == .high || latestOPK.resultType == .rising {
            let isHigh = latestOPK.resultType == .high
            return CyclePlan(
                title: isHigh ? "LH is building" : "LH is rising",
                detail: isHigh ? "Your latest test is High, which can happen as an LH surge approaches." : "Your latest test is Rising. Continue testing consistently to see how the pattern develops.",
                nextStep: isHigh ? "Test again later today or tomorrow, following your kit instructions" : "Continue testing at a consistent time each day",
                uncertainty: "One result cannot pinpoint ovulation. Your fertile-window dates remain estimates unless supported by more signals.",
                icon: "arrow.up.right.circle.fill",
                tint: .lineTeal,
                evidence: evidence
            )
        }

        if window.containsFertileDay(today) {
            return CyclePlan(
                title: "Estimated fertile window",
                detail: "You are in the estimated fertile window, with ovulation predicted around \(DateFormatting.shortDate.string(from: window.predictedOvulationDate)).",
                nextStep: "Keep ovulation tests and body-sign notes consistent over the next few days",
                uncertainty: window.isIrregular ? "Your recent cycle lengths vary, so this window is intentionally broader than a single predicted date." : "This timing is based on your recorded cycle pattern and can shift from cycle to cycle.",
                icon: "sparkles",
                tint: .lineTeal,
                evidence: evidence
            )
        }

        if today < window.fertileStartDate {
            return CyclePlan(
                title: "Preparing for your fertile window",
                detail: "Your estimated fertile window starts \(DateFormatting.shortDate.string(from: window.fertileStartDate)).",
                nextStep: "Set a reminder to begin ovulation tests on \(DateFormatting.shortDate.string(from: window.opkStartDate))",
                uncertainty: window.isIrregular ? "Your recent cycle lengths vary, so start testing early if that works for you." : "This is a calendar estimate, not a prediction of an exact ovulation day.",
                icon: "calendar.badge.clock",
                tint: .linePurple,
                evidence: evidence
            )
        }

        return CyclePlan(
            title: "After estimated ovulation",
            detail: "Your calendar places estimated ovulation around \(DateFormatting.shortDate.string(from: window.predictedOvulationDate)).",
            nextStep: "Keep any symptoms, temperatures, or test results together in your timeline",
            uncertainty: "A calendar estimate alone cannot confirm whether or when ovulation occurred.",
            icon: "moon.stars.fill",
            tint: .linePink,
            evidence: evidence
        )
    }

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

            if shouldShowPeriodCheckIn {
                periodCheckInCard
            }

            if let cycle = activeCycle, cycle.pregnancyState == .confirmedPregnant, let pregnancyProgress {
                PregnancyWeekStrip(currentWeek: pregnancyProgress.weeks)
                    .padding(.top, 2)
                PregnancyHomeHero(progress: pregnancyProgress) { showPregnancyDetails = true }
                    .padding(.top, 4)
                    .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                    .id(cycle.id)
            } else if let window = fertilityWindow {
                if activeCycle?.pregnancyState == .ended {
                        // Deliberately neutral, not celebratory or alarming -
                        // this covers a pregnancy loss as well as any other
                        // reason a cycle ended early. History stays intact;
                        // nothing here implies the user must "reset" anything.
                        VStack(spacing: 8) {
                            Text("This cycle has ended")
                                .font(.app(size: LineType.size(18), weight: .bold))
                                .foregroundStyle(Color.lineNavy)
                            Text("Your saved tests and history are kept as they are. Predictions and reminders for this cycle are paused.")
                                .font(.app(.caption, weight: .medium))
                                .foregroundStyle(Color.lineNavy.opacity(0.62))
                                .multilineTextAlignment(.center)
                            Button("Start tracking a new cycle") {
                                appState.selectedTab = .calendar
                            }
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(Color.lineBlue)
                        }
                        .frame(maxWidth: .infinity)
                } else {
                    HomeWeekStrip(
                        window: window,
                        cycleRecords: cycleRecords,
                        periodEvents: periodEvents,
                        loggedDays: loggedDays
                    ) { day in
                        logRequest = HomeLogRequest(date: day, section: nil)
                    }
                    .padding(.top, 2)

                    let tryingToConceive = settings?.ovulationTrackingGoal != .trackingCycle
                    let countdown = CycleJourneyCalculator.reacting(
                        CycleJourneyCalculator.countdown(window: window, tryingToConceive: tryingToConceive),
                        to: settings.map { CycleSignalsEngine.signals(signalInputs(settings: $0)) } ?? [],
                        tryingToConceive: tryingToConceive
                    )
                    HomeCountdownHero(
                        countdown: countdown,
                        numberColor: HomePhaseStyle.forDay(.now, window: window, cycleRecords: cycleRecords, periodEvents: periodEvents).accent,
                        uncertaintyNote: uncertaintyNote(for: window),
                        onWhy: { showPredictionWhy = true }
                    ) {
                        Button {
                            appState.selectedTab = .calendar
                        } label: {
                            HomeFertilityCurve(window: window)
                                // The curve is mostly transparent, so without
                                // this only the drawn strokes would take a tap.
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the calendar")
                    }
                    .overlay(alignment: .topTrailing) { bodySignalsButton }

                    HomeQuickActionsRow(actions: quickActions(for: countdown))
                        .padding(.bottom, 4)

                    if showsPregnancyConfirmPrompt {
                        pregnancyConfirmCard
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            } else {
                    Button {
                        appState.calendarSetupRequest = .ovulation
                        appState.selectedTab = .calendar
                    } label: {
                        VStack(spacing: 3) {
                            Text("Set up your cycle timeline")
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
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: activeCycle?.pregnancyState)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: showsPregnancyConfirmPrompt)
    }

    // MARK: - Journey helpers

    private var pregnancyProgress: PregnancyProgress? {
        guard let cycle = activeCycle, cycle.pregnancyState == .confirmedPregnant else { return nil }
        return CycleJourneyCalculator.pregnancyProgress(
            cycle: cycle,
            fallbackCycleLength: settings?.averageCycleLength ?? 28,
            fallbackLutealLength: settings?.lutealPhaseLength ?? 14
        )
    }

    /// Only while a cycle is being tracked - not once pregnant or ended.
    private var conceptionTimeline: ConceptionTimeline? {
        guard let window = fertilityWindow else { return nil }
        if let state = activeCycle?.pregnancyState, state == .confirmedPregnant || state == .ended { return nil }
        return CycleJourneyCalculator.conceptionTimeline(window: window, cycle: activeCycle)
    }

    private func stories(for timeline: ConceptionTimeline) -> [CycleStory] {
        guard settings?.ovulationTrackingGoal != .trackingCycle else { return [.cycleDay, .hormones] }
        return CycleStory.stories(for: timeline, tryingToConceive: true)
    }

    private var storiesSeenKey: String {
        conceptionTimeline.map { String(Int($0.cycleStart.timeIntervalSince1970)) } ?? ""
    }

    private var seenStories: Set<String> {
        let parts = storiesSeenRaw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == storiesSeenKey else { return [] }
        return Set(parts[1].split(separator: ",").map(String.init))
    }

    private func markStorySeen(_ story: CycleStory) {
        var seen = seenStories
        guard seen.insert(story.rawValue).inserted else { return }
        storiesSeenRaw = storiesSeenKey + "|" + seen.sorted().joined(separator: ",")
    }

    private func handleStoryAction(_ action: CycleStoryAction) {
        switch action {
        case .remindToTest(let date):
            let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
            // Let the story cover finish dismissing before the sheet rises.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                reminderDraft = HomeReminderDraft(type: .pregnancyRetest, date: max(morning, .now), title: "Take a pregnancy test")
            }
        case .scanPregnancyTest:
            appState.startScan(testType: .pregnancy)
        }
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

    private func uncertaintyNote(for window: FertilityWindow) -> String? {
        if window.isIrregular { return "Your cycles vary, so dates are approximate" }
        if let widening = window.profileWidening { return widening.shortNote }
        return nil
    }

    private func quickActions(for countdown: HomeCountdown) -> [HomeQuickAction] {
        let today = Calendar.current.startOfDay(for: .now)
        return [
            HomeQuickAction(id: "period", title: "Log period", symbol: "drop.fill", tint: .linePink, filled: true) {
                showPeriodStartCheckIn = true
            },
            HomeQuickAction(id: "symptoms", title: "Symptoms", symbol: "plus", tint: .linePurple) {
                logRequest = HomeLogRequest(date: today, section: .symptoms)
            },
            HomeQuickAction(id: "pregnancy", title: "Pregnancy", symbol: "camera.viewfinder", tint: TestType.pregnancy.tint) {
                appState.startScan(testType: .pregnancy)
            },
            HomeQuickAction(id: "ovulation", title: "Ovulation", symbol: "camera.viewfinder", tint: TestType.ovulation.tint) {
                appState.startScan(testType: .ovulation)
            }
        ]
    }

    // MARK: - Pregnancy mode

    private var showsPregnancyConfirmPrompt: Bool {
        FeatureFlags.pregnancyModeEnabled
            && activeCycle?.pregnancyState == .possiblePositive
            && Date.now.timeIntervalSince1970 >= pregnancyPromptSnoozedUntil
    }

    private var pregnancyConfirmCard: some View {
        HomeNudgeCard(
            symbol: "heart.circle.fill",
            tint: .linePink,
            title: "You saved a positive test",
            message: "Switch to pregnancy mode to see how far along you are and your estimated due date. You can switch back any time."
        ) {
            HStack(spacing: 10) {
                Button("Not yet") {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
                    withAnimation { pregnancyPromptSnoozedUntil = tomorrow.timeIntervalSince1970 }
                }
                .buttonStyle(.secondaryLine)
                Button("I’m pregnant") { confirmPregnancy() }
                    .buttonStyle(.primaryLine)
            }
        }
    }

    private func confirmPregnancy() {
        guard let cycle = activeCycle, let settings else { return }
        Task {
            await PregnancyModeService.confirmPregnancy(cycle: cycle, settings: settings, context: modelContext)
            showPregnancyReveal = true
        }
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
            && !(cycleIsSetUp(settings) && settings.hasCompletedPersonalization)
    }

    /// Everything onboarding would have asked, one tap each, ticking off as
    /// it's done - so skipping setup to scan never costs anything later.
    private func setupChecklist(_ settings: UserSettings) -> some View {
        let items: [(done: Bool, optional: Bool, title: String, detail: String, symbol: String, action: () -> Void)] = [
            (cycleIsSetUp(settings), false, "Your cycle", "Last period and cycle length, for predictions", "calendar", {
                appState.calendarSetupRequest = .ovulation
                appState.selectedTab = .calendar
            }),
            (settings.hasCompletedPersonalization, false, "About you", "Your name and a few questions that tailor results", "person.text.rectangle", {
                showPersonalization = true
            }),
            (healthIsSetUp(settings), true, "Apple Health", "If you use it, fill in temperature, periods and more automatically", "heart.text.square", {
                connectAppleHealth(source: "setup_checklist")
            })
        ]
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
            profile: settings.healthProfile,
            tryingToConceive: settings.ovulationTrackingGoal == .tryingToConceive,
            pregnancyState: settings.pregnancyJourneyState
        )
    }

    /// Everything worth showing behind Home's info button.
    private var homeSignals: [CycleSignal] {
        guard let settings else { return [] }
        return CycleSignalsEngine.signals(for: .home, signalInputs(settings: settings))
    }

    /// Top-right of the countdown, just under the date row. A dot shows when
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

    private func changePregnancyMode(_ change: @escaping @MainActor (CycleRecord, UserSettings, ModelContext) async -> Void) {
        guard let cycle = activeCycle, let settings else { return }
        Task { await change(cycle, settings, modelContext) }
    }

    // MARK: - Nudges

    @ViewBuilder
    private var homeNudges: some View {
        if let settings {
            let isPregnant = activeCycle?.pregnancyState == .confirmedPregnant
            if !isPregnant, settings.healthProfile.shouldSuggestDoctor(), !settings.dismissedDoctorSuggestion {
                HomeNudgeCard(
                    symbol: "stethoscope",
                    tint: .linePurple,
                    title: "It may help to talk to a doctor",
                    message: "Doctors usually suggest a fertility check-up after a year of trying, or after 6 months from age 35. It’s a routine step, and your MenoPlan history can help that conversation.",
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
            if settings.hasCompletedOnboarding, !settings.hasCompletedPersonalization, !settings.dismissedPersonalizationPrompt, !isPregnant, !showsSetupChecklist(settings) {
                HomeNudgeCard(
                    symbol: "person.crop.circle.badge.questionmark",
                    tint: .linePink,
                    title: "Make MenoPlan fit you",
                    message: "A few quick questions so your predictions and results take your situation into account.",
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

    private func isAfterOvulation(_ window: FertilityWindow) -> Bool {
        Calendar.current.startOfDay(for: .now) > Calendar.current.startOfDay(for: window.predictedOvulationDate)
    }

    private var homeTimelineDetail: String {
        guard let window = fertilityWindow else {
            return "Add your last period to see useful cycle timing."
        }
        let fertile = compactHomeDateRange(window.fertileStartDate, window.fertileEndDate)
        return fertile
    }

    private var compactJourneyTitle: String {
        guard let window = fertilityWindow else { return "Set up your calendar" }
        let today = Calendar.current.startOfDay(for: .now)
        if Calendar.current.isDate(today, inSameDayAs: window.predictedOvulationDate) { return "Estimated ovulation is today" }
        if window.containsFertileDay(today) { return "You’re in your estimated fertile window" }
        if today > window.predictedOvulationDate {
            let nextPeriod = Calendar.current.startOfDay(for: window.nextPeriodDate)
            let days = Calendar.current.dateComponents([.day], from: today, to: nextPeriod).day ?? 0
            if days == 1 { return "Next period expected tomorrow" }
            if days > 1 { return "Next period expected in \(days) days" }
            if days == 0 { return "Next period expected today" }
            let lateDays = abs(days)
            return lateDays == 1 ? "Your period is 1 day late" : "Your period is \(lateDays) days late"
        }
        return "Fertile window starts"
    }

    private func upcomingFertileDetail(_ window: FertilityWindow) -> String {
        let today = Calendar.current.startOfDay(for: .now)
        let start = Calendar.current.startOfDay(for: window.fertileStartDate)
        let days = max(0, Calendar.current.dateComponents([.day], from: today, to: start).day ?? 0)
        let countdown = days == 1 ? "Tomorrow" : "In \(days) days"
        return "\(countdown) · Estimated through \(shortHomeDate(window.fertileEndDate))"
    }

    private func activeFertileDetail(_ window: FertilityWindow) -> String {
        let today = Calendar.current.startOfDay(for: .now)
        let ovulation = Calendar.current.startOfDay(for: window.predictedOvulationDate)
        let days = Calendar.current.dateComponents([.day], from: today, to: ovulation).day ?? 0
        let ending = shortHomeDate(window.fertileEndDate)

        if days <= 0 {
            return "This is your estimated peak day. Fertile window ends \(ending)."
        }
        if days == 1 {
            return "Estimated ovulation is tomorrow. Fertile window ends \(ending)."
        }
        return "Estimated ovulation is in \(days) days. Fertile window ends \(ending)."
    }

    private func fullHomeDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }

    private func shortHomeDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }

    private func compactHomeDateRange(_ start: Date, _ end: Date) -> String {
        let day = DateFormatter()
        day.dateFormat = "d"
        let endDate = DateFormatter()
        endDate.dateFormat = "d MMM"
        return "\(day.string(from: start))–\(endDate.string(from: end))"
    }

    private func timelineMetric(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.app(.caption2, weight: .bold))
                .foregroundStyle(Color.lineNavy.opacity(0.46))
            Text(value)
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var cycleDayText: String {
        fertilityWindow.map { "CD \($0.cycleDay)" } ?? "Not set"
    }

    private var cycleProgress: CGFloat {
        guard let fertilityWindow else { return 0.08 }
        // The window's own length, not the settings value: a learned, hand-set
        // or ovulation-adjusted cycle is what the rest of Home is counting to.
        let length = Calendar.current.dateComponents([.day], from: fertilityWindow.cycleStart, to: fertilityWindow.nextPeriodDate).day ?? 28
        return min(max(CGFloat(fertilityWindow.cycleDay) / CGFloat(max(1, length)), 0.04), 1)
    }

    private var journeyTitle: String {
        guard let window = fertilityWindow else { return "Set up your cycle" }
        let today = Calendar.current.startOfDay(for: .now)
        if Calendar.current.isDate(today, inSameDayAs: window.predictedOvulationDate) { return "Predicted ovulation day" }
        if window.containsFertileDay(today) { return window.fertileRangeTitle }
        if today > window.predictedOvulationDate { return "After predicted ovulation" }
        return "Preparing for your fertile window"
    }

    private var journeyDetail: String {
        guard fertilityWindow != nil else { return "Add your last period and typical cycle length to personalise timing and reminders." }
        return "Your tests, predicted timing, and reminders stay together in one calendar."
    }

    private var fertileWindowText: String {
        guard let window = fertilityWindow else { return "Add cycle" }
        return "\(DateFormatting.shortDate.string(from: window.fertileStartDate))–\(DateFormatting.shortDate.string(from: window.fertileEndDate))"
    }

    private var expectedPeriodText: String {
        guard let window = fertilityWindow else { return "Add cycle" }
        return DateFormatting.shortDate.string(from: window.nextPeriodDate)
    }

    private var quickLinks: some View {
        HStack(spacing: 10) {
            homeLink("Trends", imageName: "HomeTrendsIcon", tint: .linePurple) {
                appState.showTrendsRequested = true
                appState.selectedTab = .calendar
            }
            homeLink("Progression", imageName: "HomeProgressionIcon", tint: .linePink, iconSize: CGSize(width: 40, height: 32), showsProBadge: settings?.proUnlocked != true) {
                appState.historyRoute = .progression
                appState.selectedTab = .history
            }
            homeLink("Ask Luna", imageName: "HomeLunaIcon", tint: .linePurple) { appState.selectedTab = .assistant }
        }
        // The surrounding VStack's 14pt spacing is tuned for a phone; on iPad
        // this row sits between two large cards and needs more room to read as
        // its own band rather than as part of them.
        .padding(.vertical, layout.isRegular ? 10 : 0)
    }

    private func homeLink(_ title: String, imageName: String, tint: Color, iconSize: CGSize = CGSize(width: 48, height: 38), showsProBadge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: layout.scaled(8)) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
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

    private var scanTiles: some View {
        VStack(spacing: 12) {
            ScanHeroTile(
                testType: .pregnancy,
                title: "Pregnancy Test Check",
                subtitle: "Check a home pregnancy test",
                result: .faintLineDetected
            ) {
                appState.startScan(testType: .pregnancy)
            }

            ScanHeroTile(
                testType: .ovulation,
                title: "Ovulation Test Check",
                subtitle: "Check an ovulation test",
                result: .high
            ) {
                appState.startScan(testType: .ovulation)
            }
        }
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

    private var latestScan: Scan? { scans.first }

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

    private var recentScansPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scans")
                    .font(.app(.headline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)

                Spacer()

                Button("View all") {
                    appState.selectedTab = .history
                }
                .font(.app(.caption, weight: .bold))
            }

            if scans.isEmpty {
                Text("No saved scans yet.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(scans.prefix(3).enumerated()), id: \.element.id) { index, scan in
                        ScanRow(scan: scan)
                            .padding(.vertical, 10)

                        if index < min(scans.count, 3) - 1 {
                            Divider()
                                .padding(.leading, 94)
                        }
                    }
                }

            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.96), Color.linePurple.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.linePurple.opacity(0.13)))
    }

}

enum HomePeriodCheckInPolicy {
    static func shouldShow(
        on date: Date,
        window: FertilityWindow?,
        cycle: CycleRecord?,
        periods: [PeriodEvent],
        snoozedCycleID: String,
        snoozedUntil: TimeInterval,
        calendar: Calendar = .current
    ) -> Bool {
        guard let window, let cycle, cycle.endDate == nil,
              cycle.pregnancyState == .trying else { return false }
        let today = calendar.startOfDay(for: date)
        guard today >= calendar.startOfDay(for: window.nextPeriodDate) else { return false }
        let start = calendar.startOfDay(for: cycle.startDate)
        guard !periods.contains(where: {
            !$0.notes.contains("[LineCheck Screenshot Sample]") && calendar.startOfDay(for: $0.startDate) > start
        }) else { return false }
        return snoozedCycleID != cycle.id.uuidString || date.timeIntervalSince1970 >= snoozedUntil
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

private struct HomeStoryLaunch: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct HomeReminderDraft: Identifiable {
    let type: ReminderType
    let date: Date
    let title: String
    var id: String { "\(type.rawValue)-\(title)-\(date.timeIntervalSince1970)" }
}

private struct ScanHeroTile: View {
    @Environment(\.lineLayout) private var layout
    var testType: TestType
    var title: String
    var subtitle: String
    var result: ScanResultType
    var action: () -> Void

    /// The tile's own width: the content column, minus the page gutters it
    /// sits inside. Everything in `wideContent` is sized from this so the
    /// layout keeps its proportions on any regular-width screen instead of
    /// holding constants picked for one particular iPad.
    private var tileWidth: CGFloat {
        min(layout.width, layout.contentMaxWidth) - layout.horizontalPadding * 2
    }

    /// 372/672 and 248/672 - the ratios the tile was originally drawn at.
    private var textMaxWidth: CGFloat { min(max(372, tileWidth * 0.554), 520) }
    private var imageWidth: CGFloat { min(max(248, tileWidth * 0.369), 340) }
    private var imageHeight: CGFloat { imageWidth * (150.0 / 248.0) }

    /// iPad: no width arithmetic at all. The text block states what it needs
    /// and the image takes a bounded share of what's left, so the subtitle can
    /// never end up underneath the artwork the way computed widths allowed.
    private var wideContent: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.app(size: LineType.size(22), weight: .heavy))
                    .foregroundStyle(testType.tint)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.app(size: LineType.size(17), weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // An explicit bound rather than "whatever is left": the strip
            // artwork is drawn wider than its slot and rotated, so relying on
            // the remaining space let its translucent end cap sit over the last
            // word of the subtitle. Text wraps inside this instead.
            //
            // Proportional to the tile rather than a flat 372, which was tuned
            // against the 11" iPad's 672pt tile and left the 13" with its text
            // and artwork clustered at either end of a much wider card.
            .frame(maxWidth: textMaxWidth, alignment: .leading)
            .layoutPriority(1)

            // 18 + text + 14 + image + 4 keeps the same proportions the 672pt
            // tile was designed at, so nothing has to shrink and neither line
            // has to wrap. `body` still falls back to the compact tile below
            // 700pt rather than letting these squeeze.
            Spacer(minLength: 14)

            ScanTileTestImage(testType: testType, viewportWidth: imageWidth)
                .frame(width: imageWidth, height: imageHeight, alignment: .trailing)
                .allowsHitTesting(false)
                .padding(.trailing, 4)
        }
        .padding(.leading, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The long-standing iPhone tile, unchanged.
    private var compactContent: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 30, 0)
            let textWidth = min(max(contentWidth * 0.58, 188), 224)
            let imageViewportWidth = max(contentWidth - textWidth - 10, 96)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.app(size: LineType.size(22), weight: .heavy))
                        .foregroundStyle(testType.tint)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.app(size: LineType.size(17), weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: textWidth, alignment: .leading)
                .layoutPriority(1)

                ScanTileTestImage(testType: testType)
                    .frame(width: imageViewportWidth, height: 90, alignment: .trailing)
                    .allowsHitTesting(false)
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                testType.tint.opacity(0.17),
                testType.tint.opacity(0.07),
                Color.white.opacity(0.82)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        Button(action: action) {
            Group {
                if layout.isRegular && layout.width >= 700 {
                    wideContent
                } else {
                    compactContent
                }
            }
            .frame(maxWidth: .infinity)
            // A minimum, not a fixed height. This was `height:` with a
            // `clipShape` below it, so any width that made the title or
            // subtitle wrap an extra line had that line cut off - very visible
            // in a resized iPad window, where the tile is far narrower than
            // either the phone or full-screen iPad case these numbers were
            // picked for.
            .frame(minHeight: layout.isRegular ? 184 : 124)
            .background(gradient, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.34),
                        Color.white.opacity(0.72)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 58)
                .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(testType.tint.opacity(0.10)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct ScanTileTestImage: View {
    @Environment(\.lineLayout) private var layout
    var testType: TestType
    /// The width of the window the artwork is cropped into. Only needed on
    /// iPad, where the crop is computed from it rather than hard-coded.
    var viewportWidth: CGFloat? = nil

    private var assetName: String {
        testType == .pregnancy ? "HomePregnancyTest" : "HomeOvulationTest"
    }

    private var artScale: CGFloat { layout.isRegular ? 1.45 : 1 }

    private var imageWidth: CGFloat { (testType == .pregnancy ? 304 : 334) * artScale }
    private var viewportHeight: CGFloat { (testType == .pregnancy ? 88 : 82) * artScale }

    /// Shifts the artwork right inside its window, so the test enters from the
    /// left with its cap intact and only its far end is cropped — the phone's
    /// framing. On iPad the shift is derived from the window rather than
    /// hard-coded: landing the artwork's left edge exactly on the window's left
    /// edge is what guarantees nothing is cut off that end, at any art scale.
    private var cropOffset: CGFloat {
        guard layout.isRegular, let viewportWidth else {
            return testType == .pregnancy ? 92 : 124
        }
        return max(0, imageWidth - viewportWidth)
    }

    private var rotation: Double {
        testType == .pregnancy ? -7 : -4
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: imageWidth)
            .rotationEffect(.degrees(rotation))
            .offset(x: cropOffset)
            .frame(maxWidth: .infinity, maxHeight: viewportHeight, alignment: .trailing)
            .clipped()
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            .allowsHitTesting(false)
    }
}

private struct HomeFertilityCurve: View {
    let window: FertilityWindow

    private var cycleLength: Int {
        max(1, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: window.cycleStart),
            to: Calendar.current.startOfDay(for: window.nextPeriodDate)
        ).day ?? 28)
    }

    private func cycleProgress(for date: Date) -> CGFloat {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: window.cycleStart),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        return min(max(CGFloat(days) / CGFloat(cycleLength), 0), 1)
    }

    private let peakProgress: CGFloat = 0.5

    private func chartProgress(for date: Date) -> CGFloat {
        let distanceFromOvulation = cycleProgress(for: date) - cycleProgress(for: window.predictedOvulationDate)
        return min(max(peakProgress + distanceFromOvulation, 0), 1)
    }

    private var todayProgress: CGFloat { chartProgress(for: .now) }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let baseline = height - 24
                let peakX = peakProgress * width
                let peakY = curveY(at: peakProgress, height: height)
                let todayX = todayProgress * width
                let todayY = curveY(at: todayProgress, height: height)
                let fertileStartX = chartProgress(for: window.fertileStartDate) * width
                let fertileEndX = chartProgress(for: window.fertileEndDate) * width
                // Near the peak the two labels would collide, so Today drops
                // below its dot while Ovulation stays above the peak.
                let todayLabelBelow = abs(todayX - peakX) < (ovulationLabelWidth + todayLabelWidth) / 2 + 4

                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: baseline))
                            for step in 0...64 {
                                let xProgress = CGFloat(step) / 64
                                path.addLine(to: CGPoint(x: xProgress * width, y: curveY(at: xProgress, height: height)))
                            }
                            path.addLine(to: CGPoint(x: width, y: baseline))
                            path.closeSubpath()
                        }
                        .fill(phaseGradient(
                            width: width, fertileStartX: fertileStartX, fertileEndX: fertileEndX, peakX: peakX,
                            neutral: .clear, fertile: Self.fertile.opacity(0.16), luteal: Self.luteal.opacity(0.1)
                        ))

                        Path { path in
                            for step in 0...64 {
                                let xProgress = CGFloat(step) / 64
                                let point = CGPoint(x: xProgress * width, y: curveY(at: xProgress, height: height))
                                step == 0 ? path.move(to: point) : path.addLine(to: point)
                            }
                        }
                        .stroke(
                            phaseGradient(
                                width: width, fertileStartX: fertileStartX, fertileEndX: fertileEndX, peakX: peakX,
                                neutral: Self.neutral.opacity(0.55), fertile: Self.fertile, luteal: Self.luteal
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                    // Fade the flat tails so the line doesn't hit the screen edges.
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.1),
                                .init(color: .black, location: 0.9),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                    Capsule()
                        .fill(Self.fertile.opacity(0.6))
                        .frame(width: max(10, fertileEndX - fertileStartX), height: 4)
                        .offset(x: fertileStartX, y: baseline + 5)

                    Text(window.isWidened ? "Possible fertile days" : "Fertile window")
                        .font(.app(size: LineType.size(8), weight: .bold))
                        .foregroundStyle(Self.ovulation)
                        .fixedSize()
                        .frame(width: fertileLabelWidth)
                        .offset(
                            x: min(max(((fertileStartX + fertileEndX) / 2) - fertileLabelWidth / 2, 0),
                                   max(0, width - fertileLabelWidth)),
                            y: baseline + 11
                        )

                    Path { path in
                        path.move(to: CGPoint(x: peakX, y: peakY + 7))
                        path.addLine(to: CGPoint(x: peakX, y: baseline))
                    }
                    .stroke(
                        Self.ovulation.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )

                    Text("Ovulation")
                        .font(.app(size: LineType.size(9), weight: .bold))
                        .foregroundStyle(Self.ovulation)
                        .fixedSize()
                        .frame(width: ovulationLabelWidth)
                        .offset(
                            x: min(max(peakX - ovulationLabelWidth / 2, 0), max(0, width - ovulationLabelWidth)),
                            y: peakY - LineType.size(20)
                        )

                    Circle()
                        .fill(Self.ovulation)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: peakX - 4.5, y: peakY - 4.5)

                    Text("Today")
                        .font(.app(size: LineType.size(9), weight: .bold))
                        .foregroundStyle(Color.lineNavy)
                        .fixedSize()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(todayLabelBelow ? 0.85 : 0), in: Capsule())
                        .frame(width: todayLabelWidth)
                        .offset(
                            x: min(max(todayX - todayLabelWidth / 2, 0), max(0, width - todayLabelWidth)),
                            y: todayLabelBelow ? todayY + 8 : max(0, todayY - LineType.size(20))
                        )

                    Circle()
                        .fill(Color.lineNavy)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: todayX - 4, y: todayY - 4)
                }
            }
            .frame(height: 104)

            Text("Cycle day \(window.cycleDay) · \(window.isPastExpectedPeriod(on: .now) ? "expected period was" : "next period") \(DateFormatting.shortDate.string(from: window.nextPeriodDate))")
                .font(.app(.caption2, weight: .bold))
                .foregroundStyle(Color.lineNavy.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated fertility curve. Today is cycle day \(window.cycleDay). Estimated ovulation is \(DateFormatting.shortDate.string(from: window.predictedOvulationDate)). Next period \(DateFormatting.shortDate.string(from: window.nextPeriodDate)).")
    }

    // Calendar's phase colours, so the curve reads the same as the month grid.
    private static let fertile = Color.lineFertileSoft
    private static let ovulation = Color.linePurple
    private static let luteal = Color.lineLutealSoft
    private static let neutral = Color(red: 0.58, green: 0.61, blue: 0.72)

    /// Colours the curve by phase (before the fertile window, through it to
    /// ovulation, then the luteal phase), with a short blend at each boundary.
    private func phaseGradient(
        width: CGFloat, fertileStartX: CGFloat, fertileEndX: CGFloat, peakX: CGFloat,
        neutral: Color, fertile: Color, luteal: Color
    ) -> LinearGradient {
        let blend: CGFloat = 0.03
        let start = min(max(fertileStartX / width, blend), 1)
        let end = min(max(max(fertileEndX, peakX) / width, start), 1 - blend)
        return LinearGradient(
            stops: [
                .init(color: neutral, location: 0),
                .init(color: neutral, location: start - blend),
                .init(color: fertile, location: start),
                .init(color: fertile, location: end),
                .init(color: luteal, location: end + blend),
                .init(color: luteal, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// The label boxes have to grow with the type scale, or the words wrap.
    private var todayLabelWidth: CGFloat { LineType.size(30) }
    private var ovulationLabelWidth: CGFloat { LineType.size(52) }
    private var fertileLabelWidth: CGFloat { LineType.size(window.isWidened ? 104 : 76) }

    private func curveY(at progress: CGFloat, height: CGFloat) -> CGFloat {
        let distance = (progress - peakProgress) / 0.115
        let intensity = exp(-0.5 * distance * distance)
        let baseline = height - 28
        return baseline - intensity * max(0, baseline - 28)
    }
}

private struct MiniTrendView: View {
    var values: [Double]
    var tint: Color

    private var normalizedValues: [Double] {
        let source = values.count > 1 ? values : [0.18, 0.30, 0.26, 0.52, 0.76, 0.70]
        guard let minValue = source.min(), let maxValue = source.max(), maxValue > minValue else {
            return source.map { _ in 0.5 }
        }
        return source.map { ($0 - minValue) / (maxValue - minValue) }
    }

    var body: some View {
        GeometryReader { proxy in
            let points = makePoints(in: proxy.size)

            ZStack {
                VStack(spacing: 0) {
                    Spacer()
                    Divider().opacity(0.5)
                    Spacer()
                    Divider().opacity(0.5)
                    Spacer()
                }

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(index == points.count - 1 ? tint : Color.lineCard)
                        .overlay(Circle().stroke(tint, lineWidth: 1.5))
                        .frame(width: index == points.count - 1 ? 10 : 7, height: index == points.count - 1 ? 10 : 7)
                        .position(point)
                }
            }
        }
    }

    private func makePoints(in size: CGSize) -> [CGPoint] {
        let values = normalizedValues
        guard values.count > 1 else { return [] }

        let horizontalStep = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) * horizontalStep
            let y = size.height - 12 - (CGFloat(value) * (size.height - 24))
            return CGPoint(x: x, y: y)
        }
    }
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
