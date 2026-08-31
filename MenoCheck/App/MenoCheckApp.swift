import SwiftUI
import UIKit

@main
struct MenoCheckApp: App {
    init() { MainActor.assumeIsolated { MenoAppearance.apply() } }

    var body: some Scene {
        WindowGroup { MenoRootView().tint(MenoColor.primary).preferredColorScheme(.light) }
    }
}

struct MenoRootView: View {
    enum AppTab: Hashable { case home, history, calendar, luna, settings }

    @State private var selection: AppTab = .home
    @StateObject private var store = MenoStore()
    @StateObject private var health = MenoHealthStore()
    @AppStorage("menocheck.onboardingComplete") private var onboardingComplete = false

    var body: some View {
        Group {
            if onboardingComplete {
                appShell
            } else {
                MenoOnboardingView { onboardingComplete = true }
                    .environmentObject(store)
                    .environmentObject(health)
            }
        }
    }

    private var appShell: some View {
        ZStack {
            Group {
                switch selection {
                case .home: TodayView()
                case .history: MenoHistoryView()
                case .calendar: MenoCalendarView()
                case .luna: MenoLunaView()
                case .settings: MenoSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { MenoFloatingTabBar(selection: $selection) }
        .background { MenoBrandBackdrop() }
        .tint(MenoColor.primary)
        .environmentObject(store)
        .environmentObject(health)
        .onChange(of: selection) { _, tab in store.selectedTab = [AppTab.home, .history, .calendar, .luna, .settings].firstIndex(of: tab) ?? 0 }
        .onChange(of: store.selectedTab) { _, index in selection = [AppTab.home, .history, .calendar, .luna, .settings][min(max(index, 0), 4)] }
    }
}

private struct MenoFloatingTabBar: View {
    @Binding var selection: MenoRootView.AppTab

    private let tabs: [(MenoRootView.AppTab, String, String)] = [
        (.home, "Home", "house.fill"),
        (.history, "History", "clock.arrow.circlepath"),
        (.calendar, "Calendar", "calendar"),
        (.luna, "Ask Luna", "sparkles"),
        (.settings, "Settings", "gearshape.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab in
                Button { withAnimation(.snappy(duration: 0.22)) { selection = tab.0 } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.2).font(.system(size: 23, weight: .bold))
                        Text(tab.1).font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(selection == tab.0 ? MenoColor.primary : MenoColor.ink)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(selection == tab.0 ? MenoColor.ink.opacity(0.08) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab.0 ? .isSelected : [])
            }
        }
        .padding(5)
        .background(MenoColor.surface, in: Capsule())
        .overlay { Capsule().stroke(MenoColor.surface.opacity(0.85), lineWidth: 1) }
        .shadow(color: MenoColor.ink.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

/// The system tab bar handles the safe area, scroll-edge effects and tab traits; the
/// theme only supplies the palette.
@MainActor
enum MenoAppearance {
    static func apply() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = MenoColor.uiCanvas.withAlphaComponent(0.96)
        tabBar.shadowColor = MenoColor.uiRule
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = MenoColor.uiCanvas
        navBar.shadowColor = .clear
        navBar.titleTextAttributes = [
            .font: UIFont.preferredFont(forTextStyle: .headline),
            .foregroundColor: MenoColor.uiInk,
        ]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
    }
}

// MARK: - Linecheck-style destinations

struct MenoHistoryView: View {
    @EnvironmentObject private var store: MenoStore
    @State private var query = ""
    @State private var selected = "FSH checks"
    private var visibleEntries: [TimelineEntry] {
        store.entries.filter { entry in
            let matchesType = selected == "FSH checks" ? entry.title.localizedCaseInsensitiveContains("FSH") : !entry.title.localizedCaseInsensitiveContains("FSH")
            let matchesQuery = query.isEmpty || "\(entry.title) \(entry.detail ?? "")".localizedCaseInsensitiveContains(query)
            return matchesType && matchesQuery
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MenoSpace.l) {
                    MenoHistoryControls(query: $query, selected: $selected)

                    VStack(alignment: .leading, spacing: MenoSpace.m) {
                        HStack {
                            Text("Recent checks").font(MenoFont.heading).foregroundStyle(MenoColor.ink)
                            Spacer()
                            Text("View all").font(MenoFont.caption.weight(.bold)).foregroundStyle(MenoColor.primary)
                        }
                        if visibleEntries.isEmpty {
                            Text("No matching records yet.").font(MenoFont.secondary).foregroundStyle(MenoColor.inkSecondary).padding(.vertical, MenoSpace.l)
                        }
                        ForEach(visibleEntries.prefix(30)) { entry in
                            NavigationLink { MenoEntryDetailView(entry: entry) } label: {
                                MenoHistoryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .menoCard()
                }
                .padding(.horizontal, MenoSpace.gutter)
                .padding(.top, MenoSpace.l)
                .padding(.bottom, 104)
            }
            .background { MenoBrandBackdrop() }
            .scrollIndicators(.hidden)
        }
    }
}

struct MenoCalendarView: View {
    @EnvironmentObject private var store: MenoStore
    @State private var showDayEditor = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MenoSpace.l) {
                    HStack { MenoTabHeader(title: "Calendar", subtitle: "Plan checks, track symptoms, and spot patterns."); Spacer(); Image(systemName: "bell.fill").foregroundStyle(MenoColor.primary).frame(width: 42, height: 42).background(MenoColor.surface, in: Circle()) }
                    MenoMonthCard(selectedDate: $store.selectedCalendarDate) { showDayEditor = true }
                    Text("Selected: \(store.selectedCalendarDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                        .font(MenoFont.caption.weight(.semibold))
                        .foregroundStyle(MenoColor.primary)
                    NavigationLink { InsightsView() } label: {
                        MenoDestinationCard(title: "Trends", detail: "Hot flashes, sleep, and your test series", icon: "chart.line.uptrend.xyaxis", tint: MenoColor.primary)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { SymptomLogView() } label: {
                        MenoDestinationCard(title: "Add a record", detail: "Log symptoms, sleep, medication, or a note", icon: "plus.circle.fill", tint: MenoColor.accent)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { MenoReminderView() } label: {
                        MenoDestinationCard(title: "Reminders", detail: "Next FSH test · tomorrow at 07:30", icon: "bell.badge.fill", tint: MenoColor.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, MenoSpace.gutter)
                .padding(.top, MenoSpace.l)
                .padding(.bottom, 104)
            }
            .background { MenoBrandBackdrop() }
            .scrollIndicators(.hidden)
            .sheet(isPresented: $showDayEditor) { MenoDayEditor(date: store.selectedCalendarDate) }
        }
    }
}

private struct MenoChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var suggestions: [MenoAssistantSuggestion] = []
    var isError = false
}

struct MenoLunaView: View {
    @EnvironmentObject private var store: MenoStore
    @State private var message = ""
    @State private var messages: [MenoChatMessage] = []
    @State private var isSending = false
    @State private var showScan = false
    @State private var showLog = false
    private let service = MenoAssistantService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: MenoSpace.l) {
                            header
                            if messages.isEmpty {
                                emptyState
                            } else {
                                ForEach(messages) { bubble(for: $0) }
                            }
                            if isSending {
                                typingIndicator.id("typing")
                            }
                        }
                        .padding(.horizontal, MenoSpace.gutter)
                        .padding(.top, MenoSpace.l)
                        .padding(.bottom, MenoSpace.l)
                        .id("bottom")
                    }
                    .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: isSending) { _, sending in if sending { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
                }
                inputBar
            }
            .background { MenoBrandBackdrop() }
        }
        .sheet(isPresented: $showScan) { FSHCheckStartView() }
        .sheet(isPresented: $showLog) { SymptomLogView() }
    }

    private var header: some View {
        VStack(spacing: MenoSpace.m) {
            VStack(spacing: 7) {
                Text("Luna").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(MenoColor.ink)
                Text("Calm support for tests, symptoms, and worries.").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(MenoColor.inkSecondary)
            }.frame(maxWidth: .infinity)
            HStack(spacing: MenoSpace.m) {
                Image("Luna")
                    .resizable().scaledToFit()
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(MenoColor.primarySoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Luna").font(MenoFont.heading).foregroundStyle(MenoColor.ink)
                    Text("Your menopause companion").font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary)
                }
            }
            .menoCard()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No chats yet").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(MenoColor.ink)
            Text("Start a conversation when you want help thinking through a result, preparing for an appointment, or sorting out a symptom pattern.").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(MenoColor.inkSecondary)
        }.menoCard()
    }

    private var typingIndicator: some View {
        HStack(spacing: MenoSpace.s) {
            ProgressView().tint(MenoColor.primary)
            Text("Luna is thinking…").font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary)
        }
        .padding(.horizontal, MenoSpace.m)
    }

    private func bubble(for item: MenoChatMessage) -> some View {
        VStack(alignment: item.role == .user ? .trailing : .leading, spacing: MenoSpace.s) {
            VStack(alignment: .leading, spacing: MenoSpace.s) {
                if item.role == .assistant {
                    Text(item.isError ? "Luna couldn't reply" : "Luna")
                        .font(MenoFont.caption.weight(.bold))
                        .foregroundStyle(item.isError ? MenoColor.caution : MenoColor.primary)
                }
                Text(item.text)
                    .font(MenoFont.secondary)
                    .foregroundStyle(item.role == .user ? MenoColor.onPrimary : MenoColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .menoCard(background: item.role == .user ? MenoColor.primary : MenoColor.primarySoft)
            .frame(maxWidth: 300, alignment: item.role == .user ? .trailing : .leading)

            if !item.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: MenoSpace.s) {
                    ForEach(item.suggestions) { suggestion in
                        Button { handle(suggestion) } label: {
                            HStack(spacing: MenoSpace.s) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title).font(MenoFont.label).foregroundStyle(MenoColor.ink)
                                    Text(suggestion.detail).font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(MenoColor.primary)
                            }
                            .padding(.horizontal, MenoSpace.m).padding(.vertical, MenoSpace.s)
                            .background(MenoColor.surface, in: RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous).stroke(MenoColor.rule))
                        }.buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: item.role == .user ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: MenoSpace.s) {
            TextField("Ask Luna anything", text: $message, axis: .vertical)
                .font(MenoFont.body).padding(.horizontal, MenoSpace.m).padding(.vertical, MenoSpace.s)
            Button { send() } label: {
                Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(.white).frame(width: 42, height: 42).background(MenoColor.primary, in: Circle())
            }
            .disabled(isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(isSending ? 0.6 : 1)
        }
        .padding(MenoSpace.s)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, MenoSpace.gutter)
        .padding(.bottom, 82)
    }

    private func handle(_ suggestion: MenoAssistantSuggestion) {
        switch suggestion.kind {
        case .fshScan: showScan = true
        case .logSymptom: showLog = true
        case .careSummary: store.selectedTab = 4
        }
    }

    private func send() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        messages.append(MenoChatMessage(role: .user, text: trimmed))
        message = ""
        isSending = true
        let conversation = messages.dropLast().suffix(8).map {
            MenoAssistantConversationTurn(role: $0.role == .user ? "user" : "assistant", text: $0.text)
        }
        Task {
            do {
                let response = try await service.reply(
                    message: trimmed,
                    conversation: Array(conversation),
                    recentReadings: MenoAssistantContextBuilder.recentReadings(store.fshReadings),
                    recentSymptoms: MenoAssistantContextBuilder.recentSymptoms(Array(store.dailyRecords.values)),
                    userContext: MenoAssistantContextBuilder.userContext(profile: store.profile)
                )
                messages.append(MenoChatMessage(role: .assistant, text: response.reply, suggestions: response.suggestions))
            } catch {
                messages.append(MenoChatMessage(role: .assistant, text: error.localizedDescription, isError: true))
            }
            isSending = false
        }
    }
}

struct MenoSettingsView: View {
    private let rows = [
        ("Your profile", "Name, age and menopause stage", "person.fill"),
        ("Your plan", "Experiments and self-care pathways", "leaf.fill"),
        ("Test preferences", "FSH test brand and check schedule", "testtube.2"),
        ("Reminders", "Test and symptom check-ins", "bell.fill"),
        ("Health & medications", "HRT and health connections", "cross.case.fill"),
        ("Apple Health", "Import sleep and steps you choose", "heart.fill"),
        ("iCloud sync", "Keep your private record in sync", "icloud.fill"),
        ("Export your record", "Create a clinician-ready PDF", "square.and.arrow.up"),
        ("Privacy & support", "Your data, help and medical sources", "lock.fill"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MenoSpace.l) {
                    MenoSettingsProCard()
                    NavigationLink { ProfileView() } label: { MenoProfileSummary() }.buttonStyle(.plain)
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            NavigationLink {
                                if row.0 == "Export your record" { MenoCareSummaryView() }
                                else if row.0 == "Your plan" { MenoPlanView() }
                                else if row.0 == "Health & medications" { MenoHRTReviewView() }
                                else if row.0 == "Apple Health" { MenoHealthConnectionsView() }
                                else if row.0 == "iCloud sync" { MenoICloudSyncView() }
                                else { MenoSettingsDetailView(title: row.0, detail: row.1, icon: row.2) }
                            } label: {
                                MenoRow(title: row.0, detail: row.1, icon: row.2)
                            }
                            .buttonStyle(.plain)
                            if index < rows.count - 1 { MenoRule() }
                        }
                    }
                    .menoCard()
                }
                .padding(.horizontal, MenoSpace.gutter)
                .padding(.top, MenoSpace.l)
                .padding(.bottom, 104)
            }
            .background { MenoBrandBackdrop() }
            .scrollIndicators(.hidden)
        }
    }
}

private struct MenoTabHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: MenoSpace.xs) {
            Text(title).font(MenoFont.display).foregroundStyle(MenoColor.ink)
            Text(subtitle).font(MenoFont.secondary).foregroundStyle(MenoColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Same three-part control stack as Linecheck History: search, test-type switcher, filters.
private struct MenoHistoryControls: View {
    @Binding var query: String
    @Binding var selected: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(MenoColor.inkSecondary)
                TextField("Search checks", text: $query).font(MenoFont.secondary)
                Spacer(); Image(systemName: "slider.horizontal.3").foregroundStyle(MenoColor.primary)
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(MenoColor.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(MenoColor.primary.opacity(0.10)))

            HStack(spacing: 8) {
                ForEach(["FSH checks", "Symptoms"], id: \.self) { option in
                    Button { selected = option } label: {
                        Text(option).font(.subheadline.weight(.bold)).foregroundStyle(selected == option ? .white : MenoColor.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(selected == option ? MenoColor.primary : MenoColor.surface.opacity(0.75), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Text("All time").font(.caption.weight(.bold)).foregroundStyle(MenoColor.primary).padding(.horizontal, 12).padding(.vertical, 7).background(MenoColor.primarySoft, in: Capsule())
                Text("Newest first").font(.caption.weight(.bold)).foregroundStyle(MenoColor.inkSecondary).padding(.horizontal, 12).padding(.vertical, 7).background(MenoColor.surface, in: Capsule())
            }
        }
    }
}

/// The top subscription/preferences block is intentionally positioned before settings rows,
/// as it is in Linecheck Settings.
private struct MenoSettingsProCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Menoplan Pro").font(MenoFont.heading).foregroundStyle(MenoColor.ink)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free plan").font(MenoFont.body.weight(.semibold)).foregroundStyle(MenoColor.ink)
                    Text("Unlock unlimited FSH reads, more Luna support, and an ad-free app.").font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary)
                }
                Spacer()
                Text("FREE").font(.caption.weight(.bold)).foregroundStyle(MenoColor.primary).padding(.horizontal, 10).padding(.vertical, 6).background(MenoColor.primarySoft, in: Capsule())
            }
            HStack(spacing: 10) {
                Text("Unlock Pro").font(MenoFont.body.weight(.semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(MenoColor.primary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text("Restore").font(MenoFont.body.weight(.semibold)).foregroundStyle(MenoColor.primary).padding(.horizontal, 18).padding(.vertical, 12).background(MenoColor.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
        .menoCard()
    }
}

struct MenoDestinationCard: View {
    let title: String; let detail: String; let icon: String; let tint: Color
    var body: some View {
        HStack(spacing: MenoSpace.m) {
            Image(systemName: icon).font(.title3.weight(.bold)).foregroundStyle(tint).frame(width: 48, height: 48).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(MenoFont.body.weight(.bold)).foregroundStyle(MenoColor.ink)
                Text(detail).font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(tint)
        }
        .menoCard()
    }
}

private struct MenoHistoryRow: View {
    let entry: TimelineEntry
    var body: some View {
        HStack(spacing: MenoSpace.m) {
            Image(systemName: entry.icon).foregroundStyle(MenoColor.primary).frame(width: 36, height: 36).background(MenoColor.primarySoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(MenoFont.body.weight(.semibold)).foregroundStyle(MenoColor.ink)
                Text(entry.detail ?? entry.time).font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(MenoColor.inkTertiary)
        }
        .padding(.vertical, MenoSpace.s)
    }
}

private struct MenoMonthCard: View {
    @EnvironmentObject private var store: MenoStore
    private let days = ["M", "T", "W", "T", "F", "S", "S"]
    @Binding var selectedDate: Date
    let onSelect: () -> Void
    @State private var month = Calendar.current.startOfDay(for: .now)

    private var dayCount: Int { Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30 }
    private var leadingDays: Int {
        guard let first = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month)) else { return 0 }
        return (Calendar.current.component(.weekday, from: first) + 5) % 7
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MenoSpace.m) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(MenoFont.heading).foregroundStyle(MenoColor.ink)
                Spacer()
                Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
            }
            HStack { ForEach(days, id: \.self) { Text($0).font(MenoFont.caption.weight(.bold)).foregroundStyle(MenoColor.inkSecondary).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                ForEach(0..<leadingDays, id: \.self) { _ in Color.clear.frame(height: 32) }
                ForEach(1...dayCount, id: \.self) { day in
                    Button {
                        let date = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: month), month: Calendar.current.component(.month, from: month), day: day)) ?? selectedDate
                        selectedDate = date
                        onSelect()
                    } label: {
                        let date = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: month), month: Calendar.current.component(.month, from: month), day: day)) ?? month
                        let chosen = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        let hasRecord = store.dailyRecords[MenoStore.dayKey(date)] != nil
                        VStack(spacing: 1) {
                            Text("\(day)").font(MenoFont.caption.weight(chosen ? .bold : .regular)).foregroundStyle(chosen ? .white : MenoColor.ink).frame(width: 32, height: 28).background(chosen ? MenoColor.accent : .clear, in: Circle())
                            Circle().fill(hasRecord ? MenoColor.primary : .clear).frame(width: 4, height: 4)
                        }.frame(height: 36)
                    }.buttonStyle(.plain)
                }
            }
        }
        .menoCard()
    }
}

private struct MenoProfileSummary: View {
    var body: some View {
        HStack(spacing: MenoSpace.m) {
            Text("A").font(MenoFont.title).foregroundStyle(.white).frame(width: 54, height: 54).background(LinearGradient(colors: [MenoColor.primary, MenoColor.accent], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            VStack(alignment: .leading, spacing: 2) { Text("Alex Mercer").font(MenoFont.heading).foregroundStyle(MenoColor.ink); Text("Your menopause record").font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(MenoColor.primary)
        }
        .menoCard()
    }
}

private struct MenoCompareView: View {
    @EnvironmentObject private var store: MenoStore
    var body: some View {
        MenoScreen(title: "Compare tests", subtitle: "Your saved FSH readings, in order.") {
            if store.fshReadings.isEmpty {
                MenoDisclaimer(text: "No saved FSH readings yet. Complete a mock test check to compare result windows here.")
            } else {
                VStack(spacing: MenoSpace.l) {
                    ForEach(store.fshReadings.reversed()) { reading in
                        VStack(alignment: .leading, spacing: MenoSpace.s) {
                            Text(reading.date.formatted(date: .abbreviated, time: .shortened)).font(MenoFont.caption.weight(.bold)).foregroundStyle(MenoColor.primary)
                            TestStripDiagram(controlLine: 1, testLine: reading.testLineStrength)
                        }
                        .menoCard()
                    }
                }
            }
        }
    }
}
private struct MenoEntryDetailView: View { let entry: TimelineEntry; var body: some View { MenoScreen(title: entry.title, subtitle: entry.detail ?? entry.time) { MenoDisclaimer() } } }
private struct MenoReminderView: View {
    @State private var showScan = false
    @AppStorage("menocheck.reminderHour") private var reminderHour = 7
    var body: some View {
        MenoScreen(title: "Reminders", subtitle: "Stay on top of the check-ins that matter to you.") {
            MenoSection(title: "FSH stick test") {
                Stepper("Reminder time: \(String(format: "%02d:00", reminderHour))", value: $reminderHour, in: 5...11)
                Button("Start a test now", systemImage: "camera") { showScan = true }.buttonStyle(MenoPrimaryButtonStyle())
            }
        }
        .sheet(isPresented: $showScan) { FSHCheckStartView() }
    }
}
private struct MenoSettingsDetailView: View {
    let title: String; let detail: String; let icon: String
    @AppStorage("menocheck.testBrand") private var testBrand = "Home FSH strip"
    @AppStorage("menocheck.reminderHour") private var reminderHour = 7
    var body: some View { MenoScreen(title: title, subtitle: detail) {
        if title == "Test preferences" { MenoSection(title: "Your FSH checks") { TextField("Test brand", text: $testBrand); Stepper("Preferred check time: \(String(format: "%02d:00", reminderHour))", value: $reminderHour, in: 5...11) } }
        else if title == "Reminders" { MenoSection(title: "Check-in reminder") { Toggle("Daily FSH reminder", isOn: .constant(true)); Stepper("Reminder time: \(String(format: "%02d:00", reminderHour))", value: $reminderHour, in: 5...11) } }
        else if title == "Health & medications" { NavigationLink { ProfileView() } label: { MenoDestinationCard(title: "Update health context", detail: "Menopause stage and HRT use", icon: "cross.case.fill", tint: MenoColor.primary) }.buttonStyle(.plain) }
        else if title == "Export your record" { MenoDisclaimer(text: "Your record is stored on this device. PDF export needs a clinician-summary format before it can be offered safely.") }
        else { MenoDisclaimer(text: "Your check-ins are saved locally on this device. Luna offers general information, not diagnosis or emergency care.") }
    } }
}

struct MenoDayEditor: View {
    @EnvironmentObject private var store: MenoStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var record: MenoDailyRecord

    init(date: Date) {
        self.date = date
        _record = State(initialValue: MenoDailyRecord(date: date))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(date.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                    Stepper("Hot flashes: \(record.hotFlashes)", value: $record.hotFlashes, in: 0...30)
                    HStack { Text("Sleep"); Spacer(); TextField("Hours", value: $record.sleepHours, format: .number.precision(.fractionLength(1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("hours") }
                    Toggle("Bleeding", isOn: $record.bleeding)
                    Toggle("HRT taken today", isOn: $record.hrtTaken)
                }
                Section("Notes") { TextField("Anything you want to remember", text: $record.note, axis: .vertical).lineLimit(3...6) }
                Section { Text("Your entries help you and your clinician spot patterns. They do not diagnose menopause or explain every symptom.").font(.footnote).foregroundStyle(MenoColor.inkSecondary) }
            }
            .navigationTitle("Daily record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(record); dismiss() } }
            }
            .onAppear { record = store.record(for: date) }
        }
    }
}
