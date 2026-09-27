import SwiftData
import SwiftUI

struct AssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.lineLayout) private var layout
    @Environment(AppState.self) private var appState
    @Query(sort: \AssistantConversation.updatedAt, order: .reverse) private var conversations: [AssistantConversation]
    @Query(sort: \WeeklyLunaUpdate.createdAt, order: .reverse) private var weeklyLunaUpdates: [WeeklyLunaUpdate]
    @Query private var settingsQuery: [UserSettings]
    @State private var activeConversationID: UUID?
    @State private var showingDraftChat = false
    @State private var showingWeeklyUpdates = false

    private var settings: UserSettings? { UserSettings.canonical(from: settingsQuery) }

    var body: some View {
        Group {
            if let settings {
                if settings.proUnlocked {
                    if let activeConversation = activeConversation {
                        AssistantChatScreen(conversation: activeConversation) {
                            activeConversationID = nil
                        }
                    } else if showingDraftChat {
                        AssistantChatScreen(conversation: nil) {
                            showingDraftChat = false
                        }
                    } else {
                        inbox(settings: settings)
                    }
                } else {
                    lockedState
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background { LineCheckBrandBackdrop() }
        .sheet(isPresented: $showingWeeklyUpdates) {
            WeeklyLunaUpdatesSheet(updates: weeklyLunaUpdates)
        }
        .onAppear {
            appState.isTabBarHidden = activeConversationID != nil || showingDraftChat
            if appState.pendingLunaPrompt != nil, settings?.proUnlocked == true {
                showingDraftChat = true
            }
        }
        .onDisappear {
            appState.isTabBarHidden = false
        }
        .onChange(of: activeConversationID != nil || showingDraftChat) { _, isActive in
            appState.isTabBarHidden = isActive
        }
        .tint(Color.lineBlue)
    }

    private var activeConversation: AssistantConversation? {
        guard let activeConversationID else { return nil }
        return conversations.first(where: { $0.id == activeConversationID })
    }

    private func inbox(settings: UserSettings) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    inboxHero(settings: settings)

                    if let latestWeeklyUpdate = weeklyLunaUpdates.first {
                        WeeklyLunaUpdateCard(update: latestWeeklyUpdate) {
                            showingWeeklyUpdates = true
                        }
                    }

                    if conversations.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Previous chats")
                                    .font(.app(size: LineType.size(22), weight: .bold))
                                    .foregroundStyle(Color.lineNavy)
                                Spacer()
                                Text("\(conversations.count)")
                                    .font(.app(size: LineType.size(13), weight: .bold))
                                    .foregroundStyle(Color.lineBlue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.lineBlue.opacity(0.10), in: Capsule())
                            }

                            ForEach(groupedConversations, id: \.title) { section in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(section.title)
                                        .font(.app(size: LineType.size(12), weight: .bold))
                                        .foregroundStyle(Color.lineNavy.opacity(0.50))
                                        .textCase(.uppercase)
                                        .tracking(0.8)
                                        .padding(.horizontal, 6)

                                    ForEach(section.items) { conversation in
                                        Button {
                                            open(conversation)
                                        } label: {
                                            HStack(alignment: .top, spacing: 13) {
                                                LunaAvatarView(size: 42)

                                                Text(conversation.title)
                                                    .font(.app(size: LineType.size(17), weight: .bold))
                                                    .foregroundStyle(Color.lineNavy)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .multilineTextAlignment(.leading)
                                                    .frame(maxWidth: .infinity, alignment: .leading)

                                                Spacer(minLength: 10)

                                                VStack(alignment: .trailing, spacing: 10) {
                                                    Text(DateFormatting.shortTime.string(from: conversation.updatedAt))
                                                        .font(.app(size: LineType.size(11), weight: .bold))
                                                        .foregroundStyle(Color.lineNavy.opacity(0.52))
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.lineNavy.opacity(0.05), in: Capsule())
                                                    Image(systemName: "chevron.right")
                                                        .font(.app(.caption, weight: .bold))
                                                        .foregroundStyle(Color.lineNavy.opacity(0.35))
                                                }
                                            }
                                            .padding(16)
                                            .background(
                                                Color.white.opacity(0.92),
                                                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                                    .stroke(Color.white.opacity(0.90), lineWidth: 1)
                                            )
                                            .shadow(color: Color.lineNavy.opacity(0.07), radius: 18, y: 8)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                delete(conversation)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .lineBottomInset()
                .lineContentColumn()
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                startNewConversation()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: LineType.size(20), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(canStartConversation(settings: settings) ? Color.lineBlue : Color.lineBlue.opacity(0.35), in: Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(canStartConversation(settings: settings) == false)
            .padding(.trailing, 20)
            .lineBottomInset(adjust: -46)
        }
    }

    private func inboxHero(settings: UserSettings) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Text("Luna")
                    .font(.app(size: LineType.size(25), weight: .bold))
                    .foregroundStyle(Color.lineNavy)

                HStack {
                    if !weeklyLunaUpdates.isEmpty {
                        Button {
                            showingWeeklyUpdates = true
                        } label: {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: LineType.size(18), weight: .semibold))
                                .foregroundStyle(Color.linePurple)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.96), in: Circle())
                                .overlay(Circle().stroke(Color.linePurple.opacity(0.14), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Past Luna weekly updates")
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)

            Text("Calm support for tests, timing, and worries.")
                .font(.app(size: LineType.size(13), weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No chats yet")
                .font(.app(size: LineType.size(22), weight: .bold))
                .foregroundStyle(Color.lineNavy)
            Text("Start a conversation when you want help thinking through a result, timing a retest, or sorting out a scan that feels unclear.")
                .font(.app(size: LineType.size(15), weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }

    private func canStartConversation(settings: UserSettings) -> Bool {
        settings.proUnlocked
    }

    private var lockedState: some View {
        ScrollView {
            VStack(spacing: 18) {
                LunaAvatarView(size: 128)

                VStack(spacing: 8) {
                    Text("MenoPlan Pro")
                        .font(.app(size: LineType.size(34), weight: .bold))
                        .foregroundStyle(Color.lineNavy)

                    Text("AI help for harder reads, repeat testing, and better answers from recent results.")
                        .font(.app(.subheadline))
                        .foregroundStyle(Color.lineNavy.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 9) {
                    lockedFeatureRow(symbol: "clock.badge.checkmark", title: "Answers based on recent results", detail: "AI can use your recent tests and reminders.", tint: .linePink)
                    lockedFeatureRow(symbol: "bell.badge", imageName: "CalendarReminderIcon", title: "Reminder suggestions", detail: "Get retest and ovulation timing ideas when they fit.", tint: .linePurple)
                    lockedFeatureRow(symbol: "heart.text.square", title: "Natural support", detail: "Useful guidance for worries, uncertainty, and fertility questions in plain language.", tint: .linePink)
                }

                Button("Unlock Pro") {
                    appState.paywallSource = "assistant_locked"
                    appState.showPremium = true
                }
                .buttonStyle(.primaryLine)
                .frame(maxWidth: layout.isRegular ? 320 : .infinity)
            }
            .padding(.top, 20)
            .padding(.horizontal, 18)
            // Let the final button scroll clear of the floating tab bar on
            // both iPhone and iPad.
            .lineBottomInset()
            .lineContentColumn(layout.isRegular ? 460 : nil)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func lockedFeatureRow(symbol: String, imageName: String? = nil, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Group {
                if let imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 18)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: LineType.size(13), weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 31, height: 31)
            .background(Color.white.opacity(0.78), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.lineSubheadline(.semibold))
                    .foregroundStyle(Color.lineNavy)
                Text(detail)
                    .font(.lineCaption())
                    .foregroundStyle(Color.lineNavy.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: "checkmark")
                .font(.app(.caption, weight: .black))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(tint.opacity(0.085), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.76), lineWidth: 1)
        }
    }

    private var groupedConversations: [AssistantConversationSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: conversations) { conversation in
            calendar.startOfDay(for: conversation.updatedAt)
        }

        return grouped.keys.sorted(by: >).map { day in
            AssistantConversationSection(
                title: sectionTitle(for: day),
                items: grouped[day]?.sorted(by: { $0.updatedAt > $1.updatedAt }) ?? []
            )
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return DateFormatting.shortDate.string(from: date)
    }

    private func startNewConversation() {
        guard let settings, canStartConversation(settings: settings) else { return }
        activeConversationID = nil
        showingDraftChat = true
    }

    private func delete(_ conversation: AssistantConversation) {
        if activeConversationID == conversation.id {
            activeConversationID = nil
        }
        modelContext.delete(conversation)
        try? modelContext.save()
    }

    private func open(_ conversation: AssistantConversation) {
        showingDraftChat = false
        activeConversationID = conversation.id
    }
}

private struct AssistantConversationSection {
    var title: String
    var items: [AssistantConversation]
}


private struct AssistantChatScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Scan.createdAt, order: .reverse) private var scans: [Scan]
    @Query(sort: \CycleRecord.startDate, order: .reverse) private var cycles: [CycleRecord]
    @Query(sort: \Reminder.scheduledDate) private var reminders: [Reminder]
    @Query(sort: \DailyFertilityLog.date, order: .reverse) private var dailyLogs: [DailyFertilityLog]
    @Query(sort: \PeriodEvent.startDate) private var periodEvents: [PeriodEvent]
    @Query(sort: \DailyHealthMetrics.date) private var healthMetrics: [DailyHealthMetrics]
    @Query private var settingsQuery: [UserSettings]

    let conversation: AssistantConversation?
    let close: () -> Void

    @State private var viewModel: AssistantViewModel
    @State private var draftConversation: AssistantConversation?
    @State private var appliedSuggestionIDs: Set<String> = []
    @State private var pendingSettingSuggestion: AssistantSuggestion?
    @FocusState private var composerFocused: Bool

    init(conversation: AssistantConversation?, close: @escaping () -> Void) {
        self.conversation = conversation
        self.close = close
        _viewModel = State(initialValue: AssistantViewModel())
    }

    private var settings: UserSettings? { UserSettings.canonical(from: settingsQuery) }

    var body: some View {
        Group {
            if let settings {
                VStack(spacing: 0) {
                    topBar(settings: settings)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(viewModel.messages) { message in
                                    messageRow(message)
                                        .id(message.id)
                                }

                                if viewModel.isSending {
                                    typingRow
                                        .id("typing")
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                            .padding(.bottom, 24)
                            .lineContentColumn()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            composerFocused = false
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: viewModel.messages.count) { _, _ in
                            scrollToBottom(proxy)
                        }
                        .onChange(of: viewModel.isSending) { _, _ in
                            scrollToBottom(proxy)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer(settings: settings)
                        .background(Color.lineBackground)
                }
                .background { LineCheckBrandBackdrop() }
                .overlay {
                    if let message = viewModel.errorMessage {
                        BrandedNoticeOverlay(
                            icon: "moon.fill",
                            imageName: "HomeLunaIcon",
                            title: "Luna couldn't reply",
                            message: message,
                            primaryTitle: "OK",
                            primaryAction: { viewModel.errorMessage = nil }
                        )
                    }
                }
                .overlay {
                    if let suggestion = pendingSettingSuggestion {
                        BrandedNoticeOverlay(
                            icon: "calendar.badge.checkmark",
                            imageName: "CalendarReminderIcon",
                            title: suggestion.title,
                            message: settingConfirmationMessage(suggestion),
                            primaryTitle: "Confirm",
                            secondaryTitle: "Cancel",
                            primaryAction: { confirmSettingUpdate(suggestion, settings: settings) },
                            secondaryAction: { pendingSettingSuggestion = nil }
                        )
                    }
                }
            } else {
                BrandedLoadingScreen(title: "Opening Luna")
            }
        }
        .task {
            viewModel.load(messages: conversation?.messages ?? [], userName: settings?.userName ?? "")
            if let prompt = appState.pendingLunaPrompt {
                viewModel.composerText = prompt
                appState.pendingLunaPrompt = nil
            }
        }
    }

    private func topBar(settings: UserSettings) -> some View {
        ZStack {
            HStack(spacing: 8) {
                LunaAvatarView(size: 28)
                Text("Luna")
                    .font(.app(size: LineType.size(24), weight: .bold))
                    .foregroundStyle(Color.lineNavy)
            }

            HStack {
                Button {
                    close()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: LineType.size(22), weight: .semibold))
                        .foregroundStyle(Color.lineNavy)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer()

            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .lineContentColumn()
    }

    private func messageRow(_ message: AssistantChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .assistant {
                LunaAvatarView(size: 34)
                    .padding(.bottom, 2)
                bubbleBody(message, assistant: true)
                Spacer(minLength: 36)
            } else {
                Spacer(minLength: 36)
                bubbleBody(message, assistant: false)
            }
        }
        .modifier(AssistantSuggestionModifier(
            message: message,
            isApplied: { isSuggestionApplied($0, suggestedAt: message.createdAt) },
            applySuggestion: { applySuggestion($0, suggestedAt: message.createdAt) }
        ))
    }

    private func bubbleBody(_ message: AssistantChatMessage, assistant: Bool) -> some View {
        Text(message.text)
            .font(.app(size: LineType.size(17), weight: .medium))
            .foregroundStyle(assistant ? Color.lineNavy : .white)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                assistant ? Color.linePurple.opacity(0.10) : Color.lineBlue,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                if assistant {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                }
            }
    }

    private var typingRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            LunaAvatarView(size: 34)
                .padding(.bottom, 2)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.lineNavy.opacity(0.35))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.linePurple.opacity(0.10), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 1))
            Spacer(minLength: 36)
        }
    }

    private func composer(settings: UserSettings) -> some View {
        HStack(spacing: 10) {
            TextField("Write a message...", text: $viewModel.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
                .onChange(of: viewModel.composerText) { _, value in
                    guard value.count > AssistantViewModel.maximumMessageLength else { return }
                    viewModel.composerText = String(value.prefix(AssistantViewModel.maximumMessageLength))
                }

            Button {
                Task {
                    await send(viewModel.composerText, settings: settings)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: LineType.size(19), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(sendEnabled(settings: settings) ? Color.lineBlue : Color.lineBlue.opacity(0.30), in: Circle())
            }
            .disabled(sendEnabled(settings: settings) == false)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private func sendEnabled(settings: UserSettings) -> Bool {
        settings.proUnlocked && viewModel.isSending == false && viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && viewModel.canUseAssistant(settings: settings)
    }

    private func send(_ text: String, settings: UserSettings) async {
        await viewModel.send(
            text: text,
            settings: settings,
            recentScans: recentScanContext,
            reminders: reminderContext,
            userContext: userContext(settings)
        )
        if viewModel.messages.contains(where: { $0.role == .user }) {
            let storedConversation = persistedConversation()
            viewModel.persist(into: storedConversation)
            try? modelContext.save()
        }
        composerFocused = false
    }

    private func persistedConversation() -> AssistantConversation {
        if let conversation {
            return conversation
        }
        if let draftConversation {
            return draftConversation
        }
        let created = AssistantConversation()
        modelContext.insert(created)
        draftConversation = created
        return created
    }

    private var recentScanContext: [AssistantRecentScanContext] {
        // Six compact results give Luna useful near-term context without resending
        // a long test history on every chat reply.
        scans
            .filter { $0.createdAt >= Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast }
            .prefix(6)
            .map { AssistantContextBuilder.recentScan($0, includeFreeText: false) }
    }

    private var reminderContext: [AssistantReminderContext] {
        AssistantContextBuilder.reminders(reminders, maximum: 3)
    }

    private func userContext(_ settings: UserSettings) -> AssistantUserContext {
        AssistantContextBuilder.userContext(
            settings: settings,
            cycles: cycles,
            dailyLogs: Array(dailyLogs.prefix(5)),
            periodEvents: periodEvents,
            maximumCycleSummaries: 2,
            maximumDailySummaries: 5,
            allDailyLogs: dailyLogs,
            healthMetrics: healthMetrics,
            scans: scans,
            signalSurface: .luna
        )
    }

    private func applySuggestion(_ suggestion: AssistantSuggestion, suggestedAt: Date) {
        guard appliedSuggestionIDs.contains(suggestion.id) == false else {
            appState.toast = "This suggestion was already applied"
            return
        }
        switch suggestion.kind {
        case .calendar:
            appliedSuggestionIDs.insert(suggestion.id)
            close()
            appState.selectedTab = .calendar
        case .history:
            appliedSuggestionIDs.insert(suggestion.id)
            close()
            appState.historyRoute = .recent
            appState.selectedTab = .history
        case .compare:
            appliedSuggestionIDs.insert(suggestion.id)
            close()
            appState.historyRoute = .compare
            appState.selectedTab = .history
        case .cycleTiming:
            appliedSuggestionIDs.insert(suggestion.id)
            close()
            appState.calendarSetupRequest = .ovulation
            appState.selectedTab = .calendar
        case .ovulationScan:
            appliedSuggestionIDs.insert(suggestion.id)
            close()
            appState.startScan(testType: .ovulation)
        case .settingUpdate:
            guard suggestedAt >= Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast else {
                appState.toast = "This change has expired"
                return
            }
            guard validatedSettingValue(for: suggestion) != nil else {
                appState.toast = "This change is no longer available"
                return
            }
            pendingSettingSuggestion = suggestion
        case .reminder:
            let type = reminderType(from: suggestion.reminderType)
            let date = Calendar.current.date(
                byAdding: .hour,
                value: suggestion.offsetHours ?? defaultOffset(for: type),
                to: suggestedAt
            ) ?? suggestedAt
            guard date > .now else {
                appState.toast = "This reminder suggestion has expired"
                return
            }
            let duplicateExists = reminders.contains {
                $0.reminderType == type &&
                abs($0.scheduledDate.timeIntervalSince(date)) < 60 &&
                $0.title.caseInsensitiveCompare(suggestion.title) == .orderedSame
            }
            guard duplicateExists == false else {
                appliedSuggestionIDs.insert(suggestion.id)
                appState.toast = "This reminder is already saved"
                return
            }
            appliedSuggestionIDs.insert(suggestion.id)
            let reminder = Reminder(title: suggestion.title, reminderType: type, scheduledDate: date)
            let notification = ReminderNotification(reminder: reminder)
            modelContext.insert(reminder)
            Task {
                let notificationsEnabled = await NotificationService().requestPermission()
                var notificationScheduled = false
                if notificationsEnabled {
                    do {
                        try await NotificationService().schedule(notification)
                        notificationScheduled = true
                    } catch {
                        notificationScheduled = false
                    }
                }
                await MainActor.run {
                    settings?.notificationsEnabled = notificationsEnabled
                    try? modelContext.save()
                    if notificationScheduled {
                        appState.toast = "Reminder saved and notification scheduled"
                    } else if notificationsEnabled {
                        appState.toast = "Reminder saved, but notification scheduling failed"
                    } else {
                        appState.toast = "Reminder saved without notifications"
                    }
                }
            }
        }
    }

    private func isSuggestionApplied(_ suggestion: AssistantSuggestion, suggestedAt: Date) -> Bool {
        if appliedSuggestionIDs.contains(suggestion.id) {
            return true
        }
        switch suggestion.kind {
        case .reminder:
            let type = reminderType(from: suggestion.reminderType)
            let date = Calendar.current.date(
                byAdding: .hour,
                value: suggestion.offsetHours ?? defaultOffset(for: type),
                to: suggestedAt
            ) ?? suggestedAt
            return reminders.contains {
                $0.reminderType == type &&
                abs($0.scheduledDate.timeIntervalSince(date)) < 60 &&
                $0.title.caseInsensitiveCompare(suggestion.title) == .orderedSame
            }
        case .settingUpdate:
            guard let settings, let key = suggestion.settingKey,
                  let value = validatedSettingValue(for: suggestion) else { return false }
            switch (key, value) {
            case (.expectedPeriodDate, .date(let date)):
                return settings.expectedPeriodDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
            case (.knownOvulationDate, .date(let date)):
                return settings.knownOvulationDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
            case (.lastPeriodStartDate, .date(let date)):
                return settings.lastPeriodStartDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
            case (.averageCycleLength, .integer(let number)):
                return settings.averageCycleLength == number
            case (.lutealPhaseLength, .integer(let number)):
                return settings.lutealPhaseLength == number
            default:
                return false
            }
        default:
            return false
        }
    }

    private enum ValidatedSettingValue {
        case date(Date)
        case integer(Int)
    }

    private func validatedSettingValue(for suggestion: AssistantSuggestion) -> ValidatedSettingValue? {
        guard let key = suggestion.settingKey, let rawValue = suggestion.proposedValue else { return nil }
        switch key {
        case .averageCycleLength:
            guard let value = Int(rawValue), FertilityWindowCalculator.plausibleCycleLengthRange.contains(value) else { return nil }
            return .integer(value)
        case .lutealPhaseLength:
            guard let value = Int(rawValue), (10...18).contains(value) else { return nil }
            return .integer(value)
        case .expectedPeriodDate, .knownOvulationDate, .lastPeriodStartDate:
            guard let date = Self.settingDateFormatter.date(from: rawValue) else { return nil }
            let day = Calendar.current.startOfDay(for: date)
            let today = Calendar.current.startOfDay(for: .now)
            switch key {
            case .expectedPeriodDate:
                guard let earliest = Calendar.current.date(byAdding: .day, value: -90, to: today),
                      let latest = Calendar.current.date(byAdding: .day, value: 365, to: today),
                      (earliest...latest).contains(day) else { return nil }
            case .knownOvulationDate:
                guard let earliest = Calendar.current.date(byAdding: .day, value: -90, to: today),
                      (earliest...today).contains(day) else { return nil }
            case .lastPeriodStartDate:
                guard let earliest = Calendar.current.date(byAdding: .day, value: -365, to: today),
                      (earliest...today).contains(day) else { return nil }
            default:
                break
            }
            return .date(day)
        }
    }

    private func settingConfirmationMessage(_ suggestion: AssistantSuggestion) -> String {
        guard let key = suggestion.settingKey,
              let value = validatedSettingValue(for: suggestion) else {
            return "This change is no longer available."
        }
        let displayedValue: String
        switch value {
        case .date(let date):
            displayedValue = DateFormatting.shortDate.string(from: date)
        case .integer(let number):
            displayedValue = "\(number) days"
        }
        return "Set \(settingName(key)) to \(displayedValue)?"
    }

    private func confirmSettingUpdate(_ suggestion: AssistantSuggestion, settings: UserSettings) {
        guard let key = suggestion.settingKey,
              let value = validatedSettingValue(for: suggestion) else {
            pendingSettingSuggestion = nil
            appState.toast = "This change is no longer available"
            return
        }
        switch (key, value) {
        case (.expectedPeriodDate, .date(let date)):
            settings.expectedPeriodDate = date
        // Cycle facts go through the same paths as the Calendar: once a cycle
        // exists, predictions read it rather than these settings, so writing
        // only the setting used to make Luna's "updated" change nothing.
        case (.knownOvulationDate, .date(let date)):
            settings.knownOvulationDate = date
            if let cycle = CycleTrackingService.cycle(containing: date, records: realCycles) {
                CycleTrackingService.confirmOvulation(date, on: cycle)
            }
        case (.lastPeriodStartDate, .date(let date)):
            _ = CycleTrackingService.recordPeriodStart(date, settings: settings, records: realCycles, periods: periodEvents, context: modelContext)
        case (.averageCycleLength, .integer(let number)):
            settings.averageCycleLength = number
            if let cycle = CycleTrackingService.activeCycle(records: realCycles) {
                cycle.averageCycleLengthAtStart = number
                cycle.userSetCycleLength = number
                refreshBaseline(for: cycle)
            }
        case (.lutealPhaseLength, .integer(let number)):
            settings.lutealPhaseLength = number
            if let cycle = CycleTrackingService.activeCycle(records: realCycles) {
                cycle.lutealPhaseLengthAtStart = number
                refreshBaseline(for: cycle)
            }
        default:
            pendingSettingSuggestion = nil
            appState.toast = "This change is no longer available"
            return
        }
        appliedSuggestionIDs.insert(suggestion.id)
        pendingSettingSuggestion = nil
        try? modelContext.save()
        appState.toast = "\(settingName(key)) updated"
    }

    private var realCycles: [CycleRecord] {
        cycles.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
    }

    /// Re-derives a cycle's cached ovulation/period dates after a length
    /// change, keeping any Peak-supported or confirmed ovulation as evidence.
    private func refreshBaseline(for cycle: CycleRecord) {
        if let confirmed = cycle.confirmedOvulationDate {
            cycle.expectedPeriodDate = FertilityWindowCalculator.nextPeriod(afterOvulation: confirmed, lutealPhaseLength: cycle.lutealPhaseLengthAtStart)
        } else if cycle.ovulationSource == nil,
                  let baseline = FertilityWindowCalculator.window(for: cycle.startDate, lastPeriodStart: cycle.startDate, averageCycleLength: cycle.userSetCycleLength ?? cycle.averageCycleLengthAtStart, lutealPhaseLength: cycle.lutealPhaseLengthAtStart) {
            cycle.predictedOvulationDate = baseline.predictedOvulationDate
            cycle.expectedPeriodDate = baseline.nextPeriodDate
        }
        cycle.updatedAt = .now
    }

    private func settingName(_ key: AssistantSuggestion.SettingKey) -> String {
        switch key {
        case .expectedPeriodDate: "expected period"
        case .knownOvulationDate: "ovulation date"
        case .lastPeriodStartDate: "last period start"
        case .averageCycleLength: "average cycle"
        case .lutealPhaseLength: "days from ovulation to the next period"
        }
    }

    private static let settingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private func reminderType(from rawValue: String?) -> ReminderType {
        guard let rawValue, let parsed = ReminderType(rawValue: rawValue) else { return .custom }
        return parsed
    }

    private func defaultOffset(for type: ReminderType) -> Int {
        switch type {
        case .ovulationTest, .ovulationFollowUp, .fertileWindow, .fertilePeak, .periodExpected, .periodCheckIn, .periodLate, .logTestResult, .bodyCheckIn, .cycleSetup: 12
        case .medication, .custom: 24
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if viewModel.isSending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = viewModel.messages.last?.id {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }
}

private struct AssistantSuggestionModifier: ViewModifier {
    let message: AssistantChatMessage
    let isApplied: (AssistantSuggestion) -> Bool
    let applySuggestion: (AssistantSuggestion) -> Void

    func body(content: Content) -> some View {
        VStack(alignment: message.role == .assistant ? .leading : .trailing, spacing: 10) {
            content

            if message.role == .assistant, !message.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(message.suggestions) { suggestion in
                        let applied = isApplied(suggestion)
                        Button {
                            applySuggestion(suggestion)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: icon(for: suggestion.kind))
                                    .font(.system(size: LineType.size(13), weight: .bold))
                                    .foregroundStyle(Color.lineBlue)
                                    .frame(width: 26, height: 26)
                                    .background(Color.lineBlue.opacity(0.10), in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(.lineCaption(.bold))
                                        .foregroundStyle(Color.lineNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(suggestion.detail)
                                        .font(.app(.caption2, weight: .medium))
                                        .foregroundStyle(Color.lineNavy.opacity(0.62))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .layoutPriority(1)

                                Spacer(minLength: 8)
                                Image(systemName: applied ? "checkmark" : "chevron.right")
                                    .font(.app(.caption2, weight: .bold))
                                    .foregroundStyle(Color.lineNavy.opacity(0.36))
                            }
                            .padding(10)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(applied)
                    }
                }
                .padding(.leading, 44)
                .padding(.trailing, 36)
            }
        }
    }

    private func icon(for kind: AssistantSuggestion.Kind) -> String {
        switch kind {
        case .reminder: "bell"
        case .ovulationScan: "waveform.path.ecg"
        case .calendar: "calendar"
        case .settingUpdate: "calendar.badge.checkmark"
        case .history: "clock.arrow.circlepath"
        case .compare: "rectangle.split.2x1"
        case .cycleTiming: "calendar.badge.clock"
        }
    }
}

struct LunaAvatarView: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: "Luna") {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                Image(systemName: "moon.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.lineBlue)
                    .padding(size * 0.18)
                    .background(Color.lineBlue.opacity(0.12), in: Circle())
            }
        }
        .frame(width: size, height: size)
    }
}
