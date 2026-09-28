import SwiftUI
import SwiftData

private let earliestReasonableOnboardingCycleDate = Calendar.current.date(byAdding: .year, value: -3, to: .now) ?? .distantPast

enum OnboardingCompletionAction {
    var isSkipSetup: Bool { if case .skipSetup = self { return true } else { return false } }

    case finish
    /// "Just scan a test" on the welcome page: setup is skipped for now.
    case skipSetup
    case quickTest(TestType, AnalysisMode)
}

struct OnboardingView: View {
    private enum Page: Int, CaseIterable {
        case welcome
        case name
        case goal
        case focus
        case aboutYou
        case cycleDetails
        case reminders
        case appleHealth
        case finish
    }

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CycleRecord.startDate) private var cycleRecords: [CycleRecord]
    @Query(sort: \PeriodEvent.startDate) private var periodEvents: [PeriodEvent]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var complete: (OnboardingCompletionAction) -> Void

    @State private var currentPage: Page = .welcome
    @State private var previousPage: Page = .welcome
    @State private var includeCycleDetails = false
    @State private var lastPeriodStartDate = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
    @State private var averageCycleLength = 28
    @State private var periodLength = FertilityWindowCalculator.defaultPeriodLength
    @State private var autoReminders = false
    @State private var allowNotifications = false
    @State private var isConnectingHealth = false
    @State private var isAddingPeriodHistory = false
    @State private var previousPeriodStarts: [Date] = []
    @State private var historyDate = Calendar.current.date(byAdding: .day, value: -42, to: .now) ?? .now
    @State private var showPaywall = false
    @State private var contentVisible = false
    @State private var revealedWelcomeHighlights = 0
    @State private var userName = ""
    @State private var stage: MenopauseStage = .perimenopause
    @State private var focusSymptoms: [String] = []
    @State private var quizAnswers = PersonalizationAnswers()
    @State private var quizIndex = 0
    @State private var quizMovingForward = true
    @FocusState private var nameFieldFocused: Bool

    private var settings: UserSettings? { appState.settings }
    /// Apple Health only appears where Health exists (not on every iPad).
    private var setupPages: [Page] {
        [.name, .goal, .focus, .aboutYou] + (stage.tracksCycle ? [.cycleDetails] : []) + [.reminders]
            + (HealthKitService.shared.isAvailable ? [.appleHealth] : [])
            + [.finish]
    }

    private var quizQuestions: [PersonalizationQuestion] {
        PersonalizationQuestion.sequence
    }

    private var progressIndex: Int? {
        guard let index = setupPages.firstIndex(of: currentPage) else { return nil }
        return index
    }

    private var isMovingForward: Bool {
        currentPage.rawValue >= previousPage.rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            if currentPage != .welcome {
                if let progressIndex {
                    OnboardingCapsuleProgress(activeIndex: progressIndex, total: setupPages.count)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: 18)
            }

            ZStack {
                currentPageView
                    .id(currentPage)
                    .transition(pageTransition)
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, currentPage == .welcome ? 0 : 20)

            if currentPage != .welcome {
                Spacer(minLength: 18)
                onboardingNavigation
            }
        }
        .background { LineCheckBrandBackdrop() }
        .preferredColorScheme(.light)
        .onAppear(perform: syncFromSettings)
        .task { animateContentIn() }
        .onChange(of: currentPage) { _, _ in
            contentVisible = false
            animateContentIn()
        }
        .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.14), value: currentPage)
        .animation(.easeOut(duration: 0.42), value: contentVisible)
        .fullScreenCover(isPresented: $showPaywall) {
            PremiumView(onRequestDismiss: { complete(.finish) })
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Lottie art is decorative and was sized for a phone. Even at the plain
    /// type-ramp scale it reads small against an iPad page, so it gets an extra
    /// bump on top - iPhone keeps the original point sizes exactly.
    private func heroSize(_ points: CGFloat) -> CGFloat {
        LineType.scale > 1 ? (LineType.size(points) * 1.3).rounded() : points
    }

    @ViewBuilder
    private var currentPageView: some View {
        switch currentPage {
        case .welcome:
            welcomePage
        case .name:
            namePage
        case .goal:
            goalPage
        case .focus:
            focusPage
        case .aboutYou:
            aboutYouPage
        case .cycleDetails:
            ovulationContextPage
        case .reminders:
            remindersPage
        case .appleHealth:
            appleHealthPage
        case .finish:
            finishPage
        }
    }

    private var welcomePage: some View {
        GeometryReader { proxy in
            let metrics = WelcomeLayoutMetrics(
                availableHeight: proxy.size.height,
                availableWidth: proxy.size.width,
                dynamicTypeSize: dynamicTypeSize
            )
            let compactMetrics = WelcomeLayoutMetrics(
                availableHeight: proxy.size.height,
                availableWidth: proxy.size.width,
                dynamicTypeSize: dynamicTypeSize,
                compact: true
            )

            ViewThatFits(in: .vertical) {
                welcomeContent(metrics: metrics)
                    .frame(minHeight: proxy.size.height, alignment: .center)

                ScrollView(.vertical, showsIndicators: false) {
                    welcomeContent(metrics: compactMetrics)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 640)
        .background {
            ZStack {
                Circle()
                    .fill(Color.linePink.opacity(0.055))
                    .frame(width: 330, height: 330)
                    .blur(radius: 10)
                    .offset(x: 210, y: 260)
                Circle()
                    .fill(Color.linePurple.opacity(0.05))
                    .frame(width: 280, height: 280)
                    .blur(radius: 12)
                    .offset(x: -220, y: 560)
            }
            .allowsHitTesting(false)
        }
    }

    private func welcomeContent(metrics: WelcomeLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            LottieView(name: "welcome")
                .frame(width: metrics.heroWidth, height: metrics.heroHeight)
                .clipped()
                .padding(.bottom, metrics.heroBottomPadding)

            welcomeIntro(metrics: metrics)

            welcomeHighlights
                .padding(.top, metrics.highlightTopSpacing)

            Spacer(minLength: metrics.actionTopSpacing)

            welcomeActions
        }
        .padding(.horizontal, 20)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
        .frame(maxWidth: .infinity)
    }

    private func welcomeIntro(metrics: WelcomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.introSpacing) {
            Text("Welcome")
                .font(.app(size: LineType.size(metrics.eyebrowSize), weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.lineBlue)

            HStack(spacing: 0) {
                Text("Meno")
                    .foregroundStyle(Color.lineNavy)
                Text("Plan")
                    .foregroundStyle(Color.linePink)
            }
                .font(.app(size: LineType.size(metrics.titleSize), weight: .heavy))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Track symptoms, cycle changes and FSH tests in one place.")
                .font(.app(size: LineType.size(metrics.subtitleSize), weight: .semibold))
                .lineSpacing(metrics.subtitleLineSpacing)
                .foregroundStyle(Color.lineNavy.opacity(0.64))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var welcomeHighlights: some View {
        VStack(alignment: .leading, spacing: LineType.size(8)) {
            welcomeHighlight(0, "camera.viewfinder", "Scan home FSH tests", tint: .linePink)
            welcomeHighlight(1, "rectangle.on.rectangle", "Save results & compare changes", tint: .linePurple)
            welcomeHighlight(2, "calendar", "Track timing & reminders", tint: .linePink)
            welcomeHighlight(3, "moon.fill", "Ask Luna for a second look", tint: .linePurple)
            welcomeHighlight(4, "heart.text.square", "Works with Apple Health", tint: .linePink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            revealedWelcomeHighlights = 0
            for count in 1...5 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(count == 1 ? 180 : 145))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    revealedWelcomeHighlights = count
                }
            }
        }
    }

    private func welcomeHighlight(
        _ index: Int,
        _ icon: String,
        _ title: String,
        tint: Color
    ) -> some View {
        HStack(spacing: LineType.size(10)) {
            Image(systemName: icon)
                .font(.system(size: LineType.size(17), weight: .bold))
                .foregroundStyle(tint)
                .frame(width: LineType.size(32), height: LineType.size(32))
                .background(Color.white.opacity(0.76), in: Circle())

            Text(title)
                .font(.app(size: LineType.size(17), weight: .bold))
                .foregroundStyle(Color.lineNavy.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LineType.size(12))
        .frame(maxWidth: .infinity, minHeight: LineType.size(46), alignment: .leading)
        .background(tint.opacity(0.085), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.74), lineWidth: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(revealedWelcomeHighlights > index ? 1 : 0)
        .offset(x: revealedWelcomeHighlights > index ? 0 : 24)
    }

    private var welcomeActions: some View {
        // Setup is the main path; scanning straight away stays possible
        // for someone holding a test right now, but as a quieter link.
        VStack(spacing: 10) {
            Button("Set Up Timing") {
                move(to: .name)
            }
            .buttonStyle(.primaryLine)
            .accessibilityIdentifier("onboarding-start-setup")

            Button("Just scan a test") {
                complete(.skipSetup)
            }
            .font(.app(.subheadline, weight: .semibold))
            .foregroundStyle(Color.lineNavy.opacity(0.6))
            .frame(minHeight: 40)
            .accessibilityIdentifier("onboarding-scan-now")
        }
    }

    private var namePage: some View {
        VStack(spacing: 24) {
            pageIntro(
                eyebrow: "Let’s meet",
                title: "What should we call you?",
                subtitle: "Your name helps MenoPlan and Luna feel a little more personal. It stays with your app data."
            )

            VStack(alignment: .leading, spacing: 9) {
                Text("First name")
                    .font(.app(size: LineType.size(15), weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.72))

                TextField("Your name", text: $userName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($nameFieldFocused)
                    .font(.app(size: LineType.size(20), weight: .semibold))
                    .foregroundStyle(Color.lineNavy)
                    .padding(.horizontal, 16)
                    .frame(minHeight: LineType.size(58))
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.linePurple.opacity(nameIsValid ? 0.32 : 0.12), lineWidth: 1.5)
                    }
                    .onSubmit {
                        advanceFromName()
                    }
                    .accessibilityIdentifier("onboarding-name-field")
            }
            .padding(18)
            .background(Color.linePurpleSoft.opacity(0.62), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Spacer(minLength: 12)
        }
        .frame(maxWidth: 640)
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            nameFieldFocused = true
        }
    }

    private var nameIsValid: Bool {
        userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var goalPage: some View {
        VStack(spacing: 24) {
            LottieView(name: "calendar - woman")
                .loopMode(.loop)
                .frame(width: heroSize(270), height: heroSize(160))
                .clipped()

            pageIntro(
                eyebrow: userName.isEmpty ? "Nice to meet you" : "Nice to meet you, \(userName)",
                title: "Where are you now?",
                subtitle: "This tailors what MenoPlan shows first. It isn't a diagnosis, and you can change it anytime in Settings."
            )

            VStack(spacing: 12) {
                ForEach(MenopauseStage.allCases) { option in
                    goalChoice(option, title: option.title, symbol: option.symbol)
                }
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: 640)
    }

    /// Pinned to Home's daily check-in and leading the appointment summary.
    private var focusPage: some View {
        ScrollView {
            VStack(spacing: 22) {
                pageIntro(
                    eyebrow: "Your check-in",
                    title: "What's affecting you most?",
                    subtitle: "Pick up to five. These become your one-tap daily check-in and lead your appointment summary."
                )
                FocusSymptomPicker(selection: $focusSymptoms)
            }
            .frame(maxWidth: 640)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func goalChoice(_ choice: MenopauseStage, title: String, symbol: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { stage = choice }
            // Cycle dates are only asked for (and used) while periods continue.
            if !choice.tracksCycle { includeCycleDetails = false }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: LineType.size(17), weight: .bold))
                    .foregroundStyle(stage == choice ? .white : Color.linePurple)
                    .frame(width: 44, height: 44)
                    .background(stage == choice ? Color.linePurple : Color.linePurple.opacity(0.12), in: Circle())

                Text(title)
                    .font(.app(size: LineType.size(16), weight: .bold))
                    .foregroundStyle(Color.lineNavy)

                Spacer()

                Image(systemName: stage == choice ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: LineType.size(20)))
                    .foregroundStyle(stage == choice ? Color.linePurple : Color.lineNavy.opacity(0.22))
            }
            .padding(16)
            .background(
                stage == choice ? Color.linePurpleSoft.opacity(0.7) : Color.white.opacity(0.82),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(stage == choice ? Color.linePurple.opacity(0.4) : Color.linePurple.opacity(0.12), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    /// The personalisation questions run as sub-steps of a single onboarding
    /// page, so the progress capsules stay short while each question still
    /// slides in on its own.
    private var aboutYouPage: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button("Skip") {
                    if quizQuestions.indices.contains(quizIndex) {
                        quizQuestions[quizIndex].clear(&quizAnswers)
                    }
                    navigationPrimaryAction()
                }
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.45))
            }
            .frame(maxWidth: 640)

            ZStack {
                if quizQuestions.indices.contains(quizIndex) {
                    PersonalizationQuestionView(question: quizQuestions[quizIndex], answers: $quizAnswers)
                        .id(quizQuestions[quizIndex])
                        .transition(.asymmetric(
                            insertion: .move(edge: quizMovingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: quizMovingForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func stepQuiz(_ delta: Int) {
        quizMovingForward = delta > 0
        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.88)) {
            quizIndex = min(max(0, quizIndex + delta), quizQuestions.count - 1)
        }
    }

    private var ovulationContextPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                LottieView(name: "calendar - woman")
                    .loopMode(.loop)
                    .frame(width: heroSize(270), height: heroSize(160))
                    .clipped()
                    .frame(maxWidth: .infinity)

                stageIntro(
                    step: "CYCLE BASICS",
                    title: "When did your last period start?",
                    subtitle: "Add it so MenoPlan can track how your cycle is changing."
                )

                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: $includeCycleDetails) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Use my cycle dates")
                                .font(.app(size: LineType.size(15), weight: .bold))
                            Text("Optional · you can still scan tests without them")
                                .font(.app(size: LineType.size(11)))
                                .foregroundStyle(Color.lineNavy.opacity(0.56))
                        }
                    }
                    .tint(Color.linePurple)

                    if includeCycleDetails {
                        DatePicker("Last period started", selection: $lastPeriodStartDate, in: earliestReasonableOnboardingCycleDate...Date.now, displayedComponents: .date)
                            .tint(Color.linePurple)
                        cycleLengthSteppers
                        Text("Estimates get better as you log more periods.")
                            .font(.app(size: LineType.size(12)))
                            .foregroundStyle(Color.lineNavy.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)

                        Divider().opacity(0.5)

                        previousPeriodsDisclosure
                    }
                }
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(Color.linePurple.opacity(0.16), lineWidth: 1) }

            }
            .frame(maxWidth: 640)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .onChange(of: includeCycleDetails) { _, hasDates in
            if !hasDates { autoReminders = false }
        }
    }

    /// Both cycle-basics pages ask the same two lengths: the cycle length
    /// sets ovulation and the next period until logged history takes over,
    /// the period length sets how many days a forecast period is drawn for.
    private var cycleLengthSteppers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper(value: $averageCycleLength, in: FertilityWindowCalculator.plausibleCycleLengthRange) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usual cycle length: \(averageCycleLength) days")
                        .font(.app(size: LineType.size(15), weight: .bold))
                    Text("First day of one period to the first day of the next")
                        .font(.app(size: LineType.size(11)))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                }
            }
            Stepper(value: $periodLength, in: FertilityWindowCalculator.plausiblePeriodLengthRange) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usual period length: \(periodLength) days")
                        .font(.app(size: LineType.size(15), weight: .bold))
                    Text("How many days you usually bleed")
                        .font(.app(size: LineType.size(11)))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                }
            }
        }
        .tint(Color.linePurple)
        .foregroundStyle(Color.lineNavy)
    }

    private var previousPeriodsDisclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isAddingPeriodHistory.toggle()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                    .font(.app(.subheadline, weight: .bold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add previous periods")
                                        .font(.app(.subheadline, weight: .bold))
                                    Text(previousPeriodStarts.isEmpty ? "Optional · improves predictions straight away" : "\(previousPeriodStarts.count) previous start \(previousPeriodStarts.count == 1 ? "date" : "dates") added")
                                        .font(.app(.caption))
                                        .foregroundStyle(Color.lineNavy.opacity(0.56))
                                }
                                Spacer(minLength: 8)
                                Image(systemName: isAddingPeriodHistory ? "chevron.up" : "chevron.down")
                                    .font(.app(.caption, weight: .bold))
                            }
                            .foregroundStyle(Color.lineBlue)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isAddingPeriodHistory {
                            periodHistoryEditor
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
        }
    }

    private var remindersPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                LottieView(name: "calendar - woman")
                    .loopMode(.loop)
                    .frame(width: heroSize(270), height: heroSize(160))
                    .clipped()
                    .frame(maxWidth: .infinity)

                stageIntro(
                    step: "REMINDERS",
                    title: "Never miss the right moment",
                    subtitle: "Would you like reminders based on your cycle?"
                )

                Toggle(isOn: $autoReminders) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remind me automatically")
                            .font(.app(size: LineType.size(16), weight: .bold))
                            .foregroundStyle(Color.lineNavy)
                        Text(includeCycleDetails
                             ? "A heads-up before your next period and a check-in if it's late. Change these any time in Settings."
                             : "Add cycle dates on the previous step to schedule these.")
                            .font(.app(size: LineType.size(12)))
                            .foregroundStyle(Color.lineNavy.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Color.linePurple)
                .disabled(!includeCycleDetails)
                .opacity(includeCycleDetails ? 1 : 0.55)
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.linePurple.opacity(0.16), lineWidth: 1) }
                .onChange(of: autoReminders) { _, isOn in
                    guard isOn else { return }
                    Task {
                        let granted = await NotificationService().requestPermission()
                        await MainActor.run {
                            allowNotifications = granted
                            settings?.notificationsEnabled = granted
                        }
                    }
                }
            }
            .frame(maxWidth: 640)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    private var appleHealthPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: LineType.size(56), weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.linePink, .linePurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                stageIntro(
                    step: "APPLE HEALTH",
                    title: "Let your data do the work",
                    subtitle: "Connect Apple Health and MenoPlan fills in your calendar and spots patterns for you."
                )

                VStack(alignment: .leading, spacing: 14) {
                    healthBenefit("calendar", "Periods and symptoms appear in your calendar")
                    healthBenefit("thermometer.sun", "Overnight wrist temperature and heart rate can show night sweats and hot flushes")
                    healthBenefit("bed.double", "Sleep, weight and heart data help explain how you're feeling")
                    healthBenefit("arrow.triangle.2.circlepath", "Weight and water you log here are saved back to Health")
                }
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.linePurple.opacity(0.16), lineWidth: 1) }

                if settings?.healthKitSyncEnabled == true {
                    Label("Apple Health connected", systemImage: "checkmark.circle.fill")
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(Color.linePurple)
                        .frame(maxWidth: .infinity)
                } else {
                    Button {
                        guard let settings else { return }
                        isConnectingHealth = true
                        Task {
                            _ = await HealthKitConnection.connect(settings: settings, context: modelContext, source: "onboarding", syncNow: false)
                            isConnectingHealth = false
                        }
                    } label: {
                        Label(isConnectingHealth ? "Connecting…" : "Connect Apple Health", systemImage: "heart.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryLine)
                    .disabled(isConnectingHealth)
                    Text("You choose each category, and you can change it any time in Settings.")
                        .font(.app(size: LineType.size(12)))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 640)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    private func healthBenefit(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: LineType.size(15), weight: .bold))
                .foregroundStyle(Color.linePurple)
                .frame(width: 30, height: 30)
                .background(Color.linePurple.opacity(0.1), in: Circle())
            Text(text)
                .font(.app(size: LineType.size(14), weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var finishPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                LottieView(name: "check")
                    .loopMode(.playOnce)
                    .frame(width: heroSize(190), height: heroSize(115))
                    .clipped()
                    .frame(maxWidth: .infinity)

                stageIntro(
                    step: "READY",
                    title: userName.isEmpty ? "You’re ready to start" : "You’re ready, \(userName)",
                    subtitle: "Here’s your setup. You can change it later in Calendar."
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text("YOUR SETUP")
                        .font(.app(size: LineType.size(11), weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color.linePurple)
                        .padding(.top, 18)
                    summaryRow("Name", value: userName)
                    Divider().opacity(0.35)
                    summaryRow("Last period", value: includeCycleDetails ? DateFormatting.shortDate.string(from: lastPeriodStartDate) : "Not added")
                    if includeCycleDetails {
                        Divider().opacity(0.35)
                        summaryRow("Usual cycle", value: "\(averageCycleLength) days")
                        Divider().opacity(0.35)
                        summaryRow("Usual period", value: "\(periodLength) days")
                    }
                    Divider().opacity(0.35)
                    summaryRow("Previous periods", value: !includeCycleDetails || previousPeriodStarts.isEmpty ? "None added" : "\(previousPeriodStarts.count) added")
                    Divider().opacity(0.35)
                    summaryRow("Cycle reminders", value: includeCycleDetails && autoReminders ? "On" : "Off")
                    if HealthKitService.shared.isAvailable {
                        Divider().opacity(0.35)
                        summaryRow("Apple Health", value: settings?.healthKitSyncEnabled == true ? "Connected" : "Not connected")
                    }
                }
                .padding(.horizontal, 18)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(Color.linePurple.opacity(0.14), lineWidth: 1) }
            }
            .frame(maxWidth: 640)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    private var periodHistoryEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the first day of each period you remember. MenoPlan uses the gaps between them to learn your cycle.")
                .font(.app(.caption))
                .foregroundStyle(Color.lineNavy.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                DatePicker(
                    "Previous period",
                    selection: $historyDate,
                    in: ...Calendar.current.date(byAdding: .day, value: -1, to: lastPeriodStartDate)!,
                    displayedComponents: .date
                )
                .labelsHidden()

                Button("Add") {
                    addHistoryDate()
                }
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 42)
                .background(Color.lineBlue, in: Capsule())
                .buttonStyle(.plain)
                .disabled(previousPeriodStarts.count >= 12)
                .opacity(previousPeriodStarts.count >= 12 ? 0.45 : 1)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(previousPeriodStarts, id: \.self) { date in
                HStack(spacing: 10) {
                    Image(systemName: "drop.fill")
                        .font(.app(.caption))
                        .foregroundStyle(Color.linePink)
                    Text(DateFormatting.shortDate.string(from: date))
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(Color.lineNavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Button {
                        previousPeriodStarts.removeAll { Calendar.current.isDate($0, inSameDayAs: date) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.lineNavy.opacity(0.34))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove period starting \(DateFormatting.shortDate.string(from: date))")
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 42)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func addHistoryDate() {
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: historyDate)
        guard date < calendar.startOfDay(for: lastPeriodStartDate),
              !previousPeriodStarts.contains(where: { calendar.isDate($0, inSameDayAs: date) }) else { return }
        previousPeriodStarts.append(date)
        previousPeriodStarts.sort(by: >)
        let earliest = previousPeriodStarts.min() ?? date
        historyDate = calendar.date(byAdding: .day, value: -averageCycleLength, to: earliest) ?? earliest
    }

    private var onboardingNavigation: some View {
        HStack(spacing: 12) {
            Button(navigationSecondaryTitle) {
                navigationSecondaryAction()
            }
            .buttonStyle(.secondaryLine)

            Button(navigationPrimaryTitle) {
                navigationPrimaryAction()
            }
            .buttonStyle(.primaryLine)
            .disabled(currentPage == .name && !nameIsValid)
            .opacity(currentPage == .name && !nameIsValid ? 0.48 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.32)
        }
    }

    private var navigationSecondaryTitle: String {
        "Back"
    }

    private var navigationPrimaryTitle: String {
        currentPage == .finish ? "Start using MenoPlan" : "Continue"
    }

    private func navigationSecondaryAction() {
        switch currentPage {
        case .welcome:
            break
        case .name:
            move(to: .welcome, forward: false)
        case .goal:
            move(to: .name, forward: false)
        case .focus:
            move(to: .goal, forward: false)
        case .aboutYou:
            if quizIndex > 0 {
                stepQuiz(-1)
            } else {
                move(to: .focus, forward: false)
            }
        case .cycleDetails:
            quizIndex = max(0, quizQuestions.count - 1)
            move(to: .aboutYou, forward: false)
        case .reminders:
            if stage.tracksCycle {
                move(to: .cycleDetails, forward: false)
            } else {
                quizIndex = max(0, quizQuestions.count - 1)
                move(to: .aboutYou, forward: false)
            }
        case .appleHealth:
            move(to: .reminders, forward: false)
        case .finish:
            move(to: HealthKitService.shared.isAvailable ? .appleHealth : .reminders, forward: false)
        }
    }

    private func navigationPrimaryAction() {
        switch currentPage {
        case .welcome:
            break
        case .name:
            advanceFromName()
        case .goal:
            move(to: .focus)
        case .focus:
            quizIndex = 0
            move(to: .aboutYou)
        case .aboutYou:
            if quizIndex < quizQuestions.count - 1 {
                stepQuiz(1)
            } else {
                move(to: stage.tracksCycle ? .cycleDetails : .reminders)
            }
        case .cycleDetails:
            move(to: .reminders)
        case .reminders:
            move(to: HealthKitService.shared.isAvailable ? .appleHealth : .finish)
        case .appleHealth:
            move(to: .finish)
        case .finish:
            // Saved once, here, rather than on leaving Reminders: going Back
            // and changing the last-period date after an earlier save used
            // to leave the first date behind as a second, phantom period.
            persistSettings()
            scheduleAutoRemindersIfNeeded()
            // Health permission was granted on its own step; the first import
            // waits until now so Health periods merge with the dates just
            // saved instead of racing them.
            if let settings, settings.healthKitSyncEnabled {
                Task { _ = try? await HealthKitSyncService.sync(settings: settings, context: modelContext) }
            }
            appState.paywallSource = "onboarding"
            showPaywall = true
        }
    }

    private func advanceFromName() {
        guard nameIsValid else { return }
        nameFieldFocused = false
        move(to: .goal)
    }

    private var pageTransition: AnyTransition {
        let insertionEdge: Edge = isMovingForward ? .trailing : .leading
        let removalEdge: Edge = isMovingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func pageIntro(eyebrow: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(eyebrow)
                .font(.app(size: LineType.size(12), weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.linePurple)

            Text(title)
                .font(.app(size: LineType.size(34), weight: .heavy))
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.app(size: LineType.size(16), weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.64))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func stageIntro(step: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Text(step)
                .font(.app(size: LineType.size(11), weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Color.linePurple)
            Text(title)
                .font(.app(size: LineType.size(30), weight: .heavy))
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.app(size: LineType.size(14), weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.64))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.app(size: LineType.size(15), weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.58))
            Spacer()
            Text(value)
                .font(.app(size: LineType.size(15), weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
    }

    private func animateContentIn() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.easeOut(duration: 0.42)) {
                contentVisible = true
            }
        }
    }

    private func move(to page: Page, forward: Bool = true) {
        previousPage = currentPage
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.14)) {
            currentPage = page
        }
    }

    private func persistSettings() {
        guard let settings else { return }
        settings.userName = userName
        settings.menopauseStage = stage
        if !focusSymptoms.isEmpty { settings.focusSymptoms = focusSymptoms }
        quizAnswers.apply(to: settings, context: modelContext)

        settings.expectedPeriodDate = nil
        settings.knownOvulationDate = nil

        if includeCycleDetails {
            settings.averageCycleLength = averageCycleLength
            settings.periodLength = periodLength
            var importedRecords = cycleRecords
            var importedPeriods = periodEvents
            var currentCycle: CycleRecord?
            let starts = (previousPeriodStarts + [lastPeriodStartDate])
                .map { Calendar.current.startOfDay(for: $0) }
                .reduce(into: [Date]()) { dates, date in
                    if !dates.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
                        dates.append(date)
                    }
                }
                .sorted()

            for start in starts {
                let cycle = CycleTrackingService.recordPeriodStart(start, settings: settings, records: importedRecords, periods: importedPeriods, context: modelContext)
                if !importedRecords.contains(where: { $0.id == cycle.id }) {
                    importedRecords.append(cycle)
                    importedPeriods.append(PeriodEvent(startDate: start, cycleRecordID: cycle.id))
                }
                if Calendar.current.isDate(start, inSameDayAs: lastPeriodStartDate) {
                    currentCycle = cycle
                }
            }

            let cycle = currentCycle ?? CycleTrackingService.recordPeriodStart(lastPeriodStartDate, settings: settings, records: importedRecords, periods: importedPeriods, context: modelContext)
            cycle.lutealPhaseLengthAtStart = settings.lutealPhaseLength
            cycle.confirmedOvulationDate = nil
            cycle.ovulationSource = nil
            settings.autoRemindersEnabled = autoReminders
            latestCycleForReminders = cycle
        } else {
            settings.lastPeriodStartDate = nil
            settings.autoRemindersEnabled = false
        }
        settings.trackingFocus = .ovulation
        try? modelContext.save()
    }

    /// Set by persistSettings() so the one-time reminder sync on actual
    /// completion doesn't need to redo the whole cycle lookup, and so it
    /// can't fire from the earlier "Continue" tap that also calls
    /// persistSettings() (which would double-create auto reminders).
    @State private var latestCycleForReminders: CycleRecord?

    private func scheduleAutoRemindersIfNeeded() {
        guard autoReminders, let settings, let cycle = latestCycleForReminders else { return }
        let window = CycleTrackingService.window(records: cycleRecords, periods: periodEvents, settings: settings)
        guard let window else { return }
        Task {
            await ReminderAutomationService.syncPredictedReminders(
                cycle: cycle,
                window: window,
                settings: settings,
                existingReminders: [],
                context: modelContext
            )
        }
    }

    private func syncFromSettings() {
        guard let settings else { return }
        userName = settings.userName
        stage = settings.menopauseStage
        focusSymptoms = settings.hasChosenFocusSymptoms ? settings.focusSymptoms : []
        quizAnswers = PersonalizationAnswers(settings: settings)
        includeCycleDetails = settings.lastPeriodStartDate != nil
        lastPeriodStartDate = settings.lastPeriodStartDate ?? lastPeriodStartDate
        averageCycleLength = settings.averageCycleLength
        periodLength = settings.periodLength
        autoReminders = settings.autoRemindersEnabled
        allowNotifications = settings.notificationsEnabled
    }
}

private struct OnboardingCapsuleProgress: View {
    let activeIndex: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= activeIndex ? Color.lineBlue : Color.lineBlue.opacity(0.14))
                    .frame(width: index == activeIndex ? 34 : 16, height: 8)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: activeIndex)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct WelcomeLayoutMetrics {
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let heroWidth: CGFloat
    let heroHeight: CGFloat
    let heroBottomPadding: CGFloat
    let eyebrowSize: CGFloat
    let titleSize: CGFloat
    let subtitleSize: CGFloat
    let subtitleLineSpacing: CGFloat
    let introSpacing: CGFloat
    let highlightTopSpacing: CGFloat
    let actionTopSpacing: CGFloat

    init(availableHeight: CGFloat, availableWidth: CGFloat, dynamicTypeSize: DynamicTypeSize, compact: Bool = false) {
        let isAccessibility = dynamicTypeSize.isAccessibilitySize
        let isNarrow = availableWidth < 410
        let isTall = availableHeight >= 840
        let isShort = availableHeight < 780

        if isAccessibility {
            heroHeight = compact ? 210 : min(max(availableHeight * 0.24, 220), 270)
        } else if compact || isShort {
            heroHeight = min(max(availableHeight * 0.30, 240), isNarrow ? 300 : 280)
        } else if isNarrow {
            heroHeight = min(max(availableHeight * 0.42, 345), 370)
        } else if isTall {
            heroHeight = min(max(availableHeight * 0.38, 320), 390)
        } else {
            heroHeight = min(max(availableHeight * 0.30, 250), 300)
        }

        heroWidth = heroHeight * 1.25
        topPadding = isTall && !compact && !isNarrow ? 10 : 2
        bottomPadding = isTall && !compact && !isNarrow ? 24 : 16
        heroBottomPadding = isTall && !compact ? 8 : 2
        eyebrowSize = compact || isShort ? 12 : 13
        titleSize = compact || isShort || isNarrow ? 36 : (isTall ? 43 : 40)
        subtitleSize = compact || isShort || isNarrow ? 15 : (isTall ? 16 : 15.5)
        subtitleLineSpacing = compact || isShort ? 1 : 2
        introSpacing = compact || isShort ? 8 : 10
        highlightTopSpacing = compact || isShort ? 22 : (isTall ? 36 : 28)
        actionTopSpacing = compact || isShort ? 28 : (isTall ? 56 : 40)
    }
}

