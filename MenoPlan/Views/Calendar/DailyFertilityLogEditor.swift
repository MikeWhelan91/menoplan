import SwiftData
import SwiftUI

/// Wraps its children left-to-right, moving to a new line once a row runs out of width -
/// used wherever a set of chips/tags is variable in count and width and can't fit a fixed
/// HStack or grid (symptom/mood pickers here, and the symptom/mood frequency clouds on the
/// Test Trends page).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width.map { $0.isFinite ? $0 : .greatestFiniteMagnitude } ?? 320; var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var widest: CGFloat = 0; var points: [CGPoint] = []
        for view in subviews { let size = view.sizeThatFits(.unspecified); if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }; points.append(CGPoint(x: x, y: y)); widest = max(widest, x + size.width); x += size.width + spacing; rowHeight = max(rowHeight, size.height) }
        // An unlimited proposal gets the chips' real width, not infinity - claiming
        // it widened a whole ScrollView column and let the page pan sideways.
        let reported = width == .greatestFiniteMagnitude ? widest : width
        return (CGSize(width: reported, height: y + rowHeight), points)
    }
}

/// Sections of the daily log, so callers (e.g. Home's quick actions) can open
/// the sheet already scrolled to the part they care about.
enum DailyLogSection: String, CaseIterable, Identifiable {
    case day, flushes, sleep, symptoms, mood, hrt, flow, body, supplements, notes
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Your Day"
        case .flushes: "Flushes & Sweats"
        case .sleep: "Sleep"
        case .flow: "Period & Bleeding"
        case .body: "Weight & Body"
        case .symptoms: "Symptoms"
        case .mood: "Mood"
        case .hrt: "HRT"
        case .supplements: "Supplements"
        case .notes: "Notes"
        }
    }

    var symbol: String {
        switch self {
        case .day: "sun.haze.fill"
        case .flushes: "thermometer.sun.fill"
        case .sleep: "bed.double.fill"
        case .flow: "drop.circle.fill"
        case .body: "scalemass.fill"
        case .symptoms: "waveform.path.ecg"
        case .mood: "face.smiling"
        case .hrt: "cross.vial.fill"
        case .supplements: "pills.fill"
        case .notes: "square.and.pencil"
        }
    }

    var tint: Color {
        switch self {
        case .flushes: .orange
        case .day: .linePurple
        case .flow, .symptoms: .linePink
        case .supplements, .body: .lineBlue
        case .sleep, .hrt: .linePurple
        case .mood: .orange
        case .notes: .lineNavy
        }
    }

    /// The order sections appear in. Bleeding leads while periods are still
    /// being tracked; otherwise it sits after the symptoms.
    static func ordered(for stage: MenopauseStage) -> [DailyLogSection] {
        stage.tracksCycle
            ? [.day, .flow, .symptoms, .flushes, .sleep, .mood, .hrt, .body, .supplements, .notes]
            : [.day, .symptoms, .flushes, .sleep, .mood, .hrt, .flow, .body, .supplements, .notes]
    }
}

/// Everything the editor lets you change for one day, as a value so the sheet
/// can move between days and tell whether anything was edited.
private struct DailyLogForm: Equatable {
    static let suggestedSymptoms = ["Anxiety", "Irritability", "Low Mood", "Mood Swings", "Brain Fog", "Joint Pain", "Fatigue", "Headache", "Palpitations", "Vaginal Dryness", "Low Libido", "Bladder Leaks", "Breast Tenderness", "Pelvic Pain", "Bloating", "Dizziness", "Dry Skin", "Hair Thinning"]
    static let moodOptions = ["Calm", "Happy", "Energetic", "Tearful", "Overwhelmed", "Low Confidence"]
    static let supplementOptions = ["Vitamin D", "Calcium", "Magnesium", "Omega-3", "Iron", "Vitamin B12", "Probiotic"]

    var symptoms: Set<String> = []
    var customSymptomsText = ""
    var moods: Set<String> = []
    var supplements: Set<String> = []
    var flow: FlowIntensity?
    var impact: DayImpact?
    /// Ratings from Home's check-in, kept for symptoms that stay selected.
    var severities: [String: SymptomSeverity] = [:]
    var hotFlushes: Int?
    var nightSweats: Int?
    var severity: SymptomSeverity?
    var sleep: SleepQuality?
    var hrtTaken: Set<String> = []
    var weightKg: Double?
    var waterMl: Double?
    var notes = ""

    init(_ log: DailyFertilityLog?) {
        guard let log else { return }
        symptoms = Set(log.symptoms.filter(Self.suggestedSymptoms.contains))
        customSymptomsText = log.symptoms.filter { !Self.suggestedSymptoms.contains($0) }.joined(separator: ", ")
        moods = Set(log.moods)
        supplements = Set(log.supplements)
        flow = log.flowIntensity
        impact = log.dayImpact
        severities = log.symptomSeverities
        hotFlushes = log.hotFlushCount
        nightSweats = log.nightSweatCount
        severity = log.vasomotorSeverity
        sleep = log.sleepQuality
        hrtTaken = Set(log.hrtTaken)
        weightKg = log.weightKg
        waterMl = log.waterMl
        notes = log.notes
    }

    var isEmpty: Bool { self == DailyLogForm(nil) }
}

struct DailyFertilityLogEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsQuery: [UserSettings]
    @Query(sort: \CycleRecord.startDate) private var cycleRecords: [CycleRecord]
    @Query(sort: \PeriodEvent.startDate) private var periodEvents: [PeriodEvent]
    @Query(sort: \DailyFertilityLog.date) private var allLogs: [DailyFertilityLog]
    @Query(sort: \DailyHealthMetrics.date) private var healthMetrics: [DailyHealthMetrics]

    var initialSection: DailyLogSection?

    @State private var date: Date
    @State private var form: DailyLogForm
    @State private var baseline: DailyLogForm
    @State private var movingForward = true
    @State private var searchText = ""
    @State private var askToStartPeriod = false
    /// Where to go once the "is this a new period?" question is answered.
    /// nil means the question came from Save, so the sheet closes afterwards.
    @State private var pendingDate: Date?
    @State private var showHeightPicker = false
    @State private var healthConnectMessage: String?
    @AppStorage("dailyLogHealthBannerDismissed") private var healthBannerDismissed = false
    /// Weight typed as text so a half-entered "6" isn't reformatted mid-typing.
    /// For stone, `stoneText` holds the stone and `weightText` the pounds.
    @State private var weightText = ""
    @State private var stoneText = ""
    @FocusState private var isInputFocused: Bool

    init(date: Date, existing: DailyFertilityLog?, initialSection: DailyLogSection? = nil) {
        self.initialSection = initialSection
        let day = Calendar.current.startOfDay(for: date)
        _date = State(initialValue: day)
        _form = State(initialValue: DailyLogForm(existing))
        _baseline = State(initialValue: DailyLogForm(existing))
    }

    private var bodyUnit: BodyMeasurementUnit { settings?.bodyMeasurementUnit ?? .localeDefault }
    private var heightUnit: BodyMeasurementUnit { settings?.heightUnit ?? .localeDefault }
    private var weightUnit: WeightUnit { settings?.weightUnit ?? .localeDefault }
    private var metricsForDay: DailyHealthMetrics? {
        healthMetrics.last { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.hasContent }
    }

    private var settings: UserSettings? { UserSettings.canonical(from: settingsQuery) }
    private var realPeriods: [PeriodEvent] { periodEvents.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") } }
    private var existing: DailyFertilityLog? { allLogs.first { Calendar.current.isDate($0.date, inSameDayAs: date) } }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isDirty: Bool { form != baseline }

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private var cycleDayText: String? {
        guard let cycle = CycleTrackingService.activeCycle(on: date, records: cycleRecords.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }) else { return nil }
        return "Cycle day \(FertilityWindowCalculator.cycleDay(for: date, cycleStart: cycle.startDate))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayHeader
                searchField
                ScrollViewReader { reader in
                    ScrollView {
                        ZStack {
                            sections
                                .id(date)
                                .transition(.asymmetric(
                                    insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
                                ))
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        guard let initialSection else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.easeInOut(duration: 0.45)) { reader.scrollTo(initialSection, anchor: .top) }
                        }
                    }
                }
            }
            .background { LineCheckBrandBackdrop() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { prepareSave(thenGoTo: nil) }.fontWeight(.bold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isInputFocused = false }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.6, abs(value.translation.width) > 70 else { return }
                        value.translation.width < 0 ? step(1) : step(-1)
                    }
            )
        }
        .tint(Color.lineBlue)
        .confirmationDialog("Is this the first day of a new period?", isPresented: $askToStartPeriod, titleVisibility: .visible) {
            Button("Yes, start a new period") { save(startPeriod: true); finish() }
            Button("No, save flow only") { save(startPeriod: false); finish() }
            Button("Cancel", role: .cancel) { pendingDate = nil }
        } message: {
            Text("A new period updates cycle predictions. You can still save flow without starting a cycle.")
        }
    }

    // MARK: Header

    private var dayHeader: some View {
        HStack {
            arrowButton("chevron.left", label: "Previous day") { step(-1) }
            Spacer()
            VStack(spacing: 2) {
                Text(dayTitle)
                    .font(.app(size: LineType.size(18), weight: .heavy))
                    .foregroundStyle(Color.lineNavy)
                    .contentTransition(.interpolate)
                if let cycleDayText {
                    Text(cycleDayText)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.5))
                        .contentTransition(.numericText())
                }
            }
            .animation(.snappy, value: date)
            Spacer()
            arrowButton("chevron.right", label: "Next day") { step(1) }
                .opacity(isToday ? 0.25 : 1)
                .disabled(isToday)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func arrowButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.8), in: Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.lineNavy.opacity(0.45))
            TextField("Search symptoms, moods and more", text: $searchText)
                .focused($isInputFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { withAnimation(.snappy) { searchText = "" } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.lineNavy.opacity(0.35))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.app(.subheadline))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.lineNavy.opacity(0.06), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .animation(.snappy, value: searchText.isEmpty)
    }

    // MARK: Sections

    private var query: String { searchText.trimmingCharacters(in: .whitespaces).lowercased() }

    /// With a search active, a section shows if its title matches (all of its
    /// options) or only the options that match; otherwise it's hidden.
    private func visible(_ options: [String], in section: DailyLogSection) -> [String] {
        guard !query.isEmpty else { return options }
        if section.title.lowercased().contains(query) { return options }
        return options.filter { $0.lowercased().contains(query) }
    }

    private func sectionVisible(_ section: DailyLogSection, options: [String] = []) -> Bool {
        guard !query.isEmpty else { return true }
        return section.title.lowercased().contains(query) || !visible(options, in: section).isEmpty
    }

    private var stage: MenopauseStage { settings?.menopauseStage ?? .perimenopause }

    /// The person's own HRT if they've set it up in Settings, otherwise the
    /// common kinds, plus anything already ticked on this day.
    private var hrtOptions: [String] {
        let regimen = settings?.hrtRegimen ?? []
        let base = regimen.isEmpty ? HRTOptions.common : regimen
        return base + form.hrtTaken.filter { !base.contains($0) }.sorted()
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 18) {
            if query.isEmpty, !healthBannerDismissed, HealthKitConnection.canOffer(settings) {
                healthConnectBanner
            }
            ForEach(DailyLogSection.ordered(for: stage)) { section in
                if sectionVisible(section, options: optionsFor(section)) {
                    sectionView(section)
                }
                if section == .body, query.isEmpty, let metricsForDay {
                    HealthMetricsCard(metrics: metricsForDay, unit: weightUnit.distanceSystem)
                }
            }
            if !query.isEmpty && !DailyLogSection.allCases.contains(where: { sectionVisible($0, options: optionsFor($0)) }) {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 30)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: query)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: form)
    }

    @ViewBuilder
    private func sectionView(_ section: DailyLogSection) -> some View {
        switch section {
        case .day:
            LogSection(.day) {
                Text("How much did symptoms affect your day?")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.6))
                singleChips(visible(optionsFor(.day), in: .day), selection: Binding(
                    get: { form.impact?.title },
                    set: { title in form.impact = DayImpact.allCases.first { $0.title == title } }
                ), tint: DailyLogSection.day.tint)
            }
        case .flushes:
            LogSection(.flushes) { flushesContent }
        case .sleep:
            LogSection(.sleep) { sleepContent }
        case .flow:
            LogSection(.flow) {
                singleChips(visible(optionsFor(.flow), in: .flow), selection: flowTitleBinding, tint: DailyLogSection.flow.tint)
                if form.flow != nil, !stage.tracksCycle {
                    bleedingNotice
                }
            }
        case .body:
            LogSection(.body) { bodyContent }
        case .symptoms:
            LogSection(.symptoms) {
                multiChips(visible(DailyLogForm.suggestedSymptoms, in: .symptoms), selection: $form.symptoms, tint: DailyLogSection.symptoms.tint) { form.severities[$0]?.title }
                if query.isEmpty {
                    TextField("Other symptoms, separated by commas", text: $form.customSymptomsText, axis: .vertical)
                        .focused($isInputFocused)
                        .lineLimit(1...3)
                        .padding(12)
                        .background(Color.lineBackground, in: RoundedRectangle(cornerRadius: 12))
                    Text("Use this for anything not covered by the suggested symptoms above.")
                        .font(.app(.caption2))
                        .foregroundStyle(Color.lineNavy.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .mood:
            LogSection(.mood) {
                multiChips(visible(DailyLogForm.moodOptions, in: .mood), selection: $form.moods, tint: DailyLogSection.mood.tint)
            }
        case .hrt:
            LogSection(.hrt) {
                multiChips(visible(hrtOptions, in: .hrt), selection: $form.hrtTaken, tint: DailyLogSection.hrt.tint)
                if query.isEmpty {
                    Text(settings?.hrtRegimen.isEmpty ?? true
                         ? "Tick what you took today. Add your usual HRT in Settings to see just yours here."
                         : "Tick what you took today. Change your usual HRT in Settings.")
                        .font(.app(.caption2))
                        .foregroundStyle(Color.lineNavy.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .supplements:
            LogSection(.supplements) {
                multiChips(visible(DailyLogForm.supplementOptions, in: .supplements), selection: $form.supplements, tint: DailyLogSection.supplements.tint)
            }
        case .notes:
            LogSection(.notes) {
                TextField("Anything else you noticed today…", text: $form.notes, axis: .vertical)
                    .focused($isInputFocused)
                    .lineLimit(3...7).padding(14)
                    .background(Color.lineBackground, in: RoundedRectangle(cornerRadius: 15))
            }
        }
    }

    private var flushesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            counterRow("Hot flushes", symbol: "flame.fill", value: $form.hotFlushes)
            counterRow("Night sweats", symbol: "moon.stars.fill", value: $form.nightSweats)
            if (form.hotFlushes ?? 0) + (form.nightSweats ?? 0) > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How much did they bother you?")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.6))
                    singleChips(SymptomSeverity.allCases.map(\.title), selection: Binding(
                        get: { form.severity?.title },
                        set: { title in form.severity = SymptomSeverity.allCases.first { $0.title == title } }
                    ), tint: DailyLogSection.flushes.tint)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func counterRow(_ title: String, symbol: String, value: Binding<Int?>) -> some View {
        let count = value.wrappedValue ?? 0
        return HStack(spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(Color.lineNavy)
            Spacer()
            stepButton("minus", label: "One fewer \(title.lowercased())") {
                let next = max(0, count - 1)
                value.wrappedValue = next == 0 ? nil : next
            }
            .disabled(count == 0)
            .opacity(count == 0 ? 0.4 : 1)
            Text("\(count)")
                .font(.app(.title3, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color.lineNavy)
                .frame(minWidth: 36)
                .contentTransition(.numericText())
                .accessibilityLabel("\(count) \(title.lowercased())")
            stepButton("plus", label: "One more \(title.lowercased())") {
                value.wrappedValue = min(count + 1, 50)
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.orange)
                .frame(width: 36, height: 36)
                .background(Color.orange.opacity(0.12), in: Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }

    private var sleepContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            singleChips(visible(optionsFor(.sleep), in: .sleep), selection: Binding(
                get: { form.sleep?.title },
                set: { title in form.sleep = SleepQuality.allCases.first { $0.title == title } }
            ), tint: DailyLogSection.sleep.tint)
            if query.isEmpty, let hours = metricsForDay?.sleepHours, hours > 0 {
                let minutes = Int((hours * 60).rounded())
                Label("\(minutes / 60)h \(minutes % 60)m asleep, from Apple Health", systemImage: "heart.fill")
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(Color.linePurple.opacity(0.7))
            }
        }
    }

    /// Any bleeding once periods have stopped needs a clinician to look at it.
    private var bleedingNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "stethoscope")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.linePink)
            Text(stage == .postmenopause
                 ? "Bleeding after menopause should always be checked. Please contact your GP or clinician - it's often nothing serious, but it needs looking at."
                 : "Unexpected bleeding is worth mentioning to your GP or clinician, especially if it's new for you.")
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.linePink.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .transition(.opacity)
    }

    private func optionsFor(_ section: DailyLogSection) -> [String] {
        switch section {
        case .day: DayImpact.allCases.map(\.title)
        case .flushes: ["Hot flushes", "Night sweats", "Hot flashes"]
        case .sleep: SleepQuality.allCases.map(\.title)
        case .flow: FlowIntensity.allCases.map(\.title)
        case .body: Self.bodySearchTerms
        case .symptoms: DailyLogForm.suggestedSymptoms
        case .mood: DailyLogForm.moodOptions
        case .hrt: hrtOptions
        case .supplements: DailyLogForm.supplementOptions
        case .notes: []
        }
    }

    static let bodySearchTerms = ["weight", "height", "bmi", "water"]

    /// Shown until Apple Health is connected or the person dismisses it:
    /// the daily log is where typing symptoms, weight and water by hand hurts most.
    private var healthConnectBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.linePink)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fill this in automatically")
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                Text(healthConnectMessage ?? "Connect Apple Health for sleep, weight, hot flushes and more.")
                    .font(.app(.caption))
                    .foregroundStyle(Color.lineNavy.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Connect") {
                guard let settings else { return }
                Task { healthConnectMessage = await HealthKitConnection.connect(settings: settings, context: modelContext, source: "daily_log") }
            }
            .font(.app(.subheadline, weight: .bold))
            .foregroundStyle(Color.linePurple)
            Button {
                withAnimation(.snappy) { healthBannerDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.linePink.opacity(0.18)))
        .transition(.opacity)
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if existing?.weightSource == .healthKit, form.weightKg == baseline.weightKg, form.weightKg != nil {
                Label("Weight synced from Apple Health", systemImage: "heart.fill")
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(Color.linePurple.opacity(0.7))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Weight")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lineNavy)
                    Spacer()
                    if let settings {
                        UnitSwitch(selection: Binding(
                            get: { settings.weightUnit },
                            set: { settings.weightUnit = $0; try? modelContext.save() }
                        ), options: WeightUnit.allCases.map { ($0, $0.shortTitle) })
                    }
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if weightUnit == .stone {
                        weightField($stoneText, placeholder: "10", width: 64)
                        unitLabel("st")
                        weightField($weightText, placeholder: "3", width: 72)
                        unitLabel("lb")
                    } else {
                        weightField($weightText, placeholder: weightUnit == .kilograms ? "65.0" : "143.0", width: 110)
                        unitLabel(weightUnit.shortTitle)
                    }
                }
            }

            HStack(spacing: 10) {
                Text("Height")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy)
                Spacer()
                Button { showHeightPicker = true } label: {
                    Text(settings?.heightCmValue.map(heightUnit.formattedHeight) ?? "Add")
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(Color.lineBlue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.lineBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            if let bmi = HealthProfile(conditions: [], heightCm: settings?.heightCmValue, weightKg: form.weightKg ?? settings?.weightKgValue).bmi {
                let category = BMICategory(bmi: bmi)
                VStack(alignment: .leading, spacing: 3) {
                    Text("BMI \(String(format: "%.1f", bmi)) · \(category.title)")
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.7))
                }
            }

            Rectangle().fill(Color.lineNavy.opacity(0.06)).frame(height: 1)

            HStack(spacing: 12) {
                Label("Water", systemImage: "drop.fill")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy)
                Spacer()
                waterButton("minus", delta: -1)
                    .disabled((form.waterMl ?? 0) <= 0)
                Text(form.waterMl.map(bodyUnit.formattedWater) ?? bodyUnit.formattedWater(0))
                    .font(.app(.subheadline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.lineNavy)
                    .frame(minWidth: 80)
                    .contentTransition(.numericText())
                waterButton("plus", delta: 1)
            }
            if existing?.waterSource == .healthKit, form.waterMl == baseline.waterMl, form.waterMl != nil {
                Text("Includes water logged in other apps via Apple Health.")
                    .font(.app(.caption2))
                    .foregroundStyle(Color.lineNavy.opacity(0.5))
            }
        }
        .onAppear(perform: syncWeightText)
        .onChange(of: date) { _, _ in syncWeightText() }
        .onChange(of: weightUnit) { _, _ in syncWeightText() }
        .sheet(isPresented: $showHeightPicker) { heightSheet }
    }

    /// One glass: 250 ml, or 8 fl oz for imperial.
    private var waterStepMl: Double { bodyUnit == .metric ? 250 : 8 * BodyMeasurementUnit.millilitresPerFluidOunce }

    private func waterButton(_ symbol: String, delta: Double) -> some View {
        Button {
            let next = max(0, (form.waterMl ?? 0) + delta * waterStepMl)
            withAnimation(.snappy) { form.waterMl = next == 0 ? nil : next }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.lineBlue)
                .frame(width: 36, height: 36)
                .background(Color.lineBlue.opacity(0.10), in: Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(delta > 0 ? "Add a glass of water" : "Remove a glass of water")
    }

    private var heightSheet: some View {
        NavigationStack {
            BodyHeightPicker(
                heightCm: Binding(
                    get: { settings?.heightCmValue ?? 165 },
                    set: { value in
                        guard let settings else { return }
                        BodyMeasurementStore.recordHeight(value, settings: settings)
                    }
                ),
                unit: heightUnit
            )
            .padding()
            .safeAreaInset(edge: .top) {
                if let settings {
                    UnitSwitch(selection: Binding(
                        get: { settings.heightUnit },
                        set: { settings.heightUnit = $0; try? modelContext.save() }
                    ), options: [(BodyMeasurementUnit.metric, "cm"), (.imperial, "ft")])
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let settings, settings.heightCmValue == nil { settings.heightCmValue = 165 }
                        try? modelContext.save()
                        showHeightPicker = false
                    }
                }
            }
        }
        .presentationDetents([.height(340)])
    }

    private func weightField(_ text: Binding<String>, placeholder: String, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .focused($isInputFocused)
            .frame(width: width)
            .padding(.vertical, 10)
            .background(Color.lineBackground, in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: text.wrappedValue) { _, _ in updateWeightFromText() }
    }

    private func unitLabel(_ title: String) -> some View {
        Text(title)
            .font(.app(.subheadline, weight: .bold))
            .foregroundStyle(Color.lineNavy.opacity(0.55))
    }

    /// The text the fields show for a weight, as (stone, main) - main is kg,
    /// lb, or the pounds part of stone.
    private func weightTexts(_ kilograms: Double?) -> (stone: String, main: String) {
        guard let kilograms else { return ("", "") }
        switch weightUnit {
        case .kilograms: return ("", String(format: "%.1f", kilograms))
        case .pounds: return ("", String(format: "%.1f", kilograms * BodyMeasurementUnit.poundsPerKilogram))
        case .stone:
            let (stone, pounds) = WeightUnit.stoneAndPounds(kilograms)
            return ("\(stone)", pounds.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", pounds) : String(format: "%.1f", pounds))
        }
    }

    private func updateWeightFromText() {
        // syncWeightText's own rounding must not count as an edit, or viewing
        // a Health-synced day would claim that weight as typed.
        let current = weightTexts(form.weightKg)
        guard stoneText != current.stone || weightText != current.main else { return }
        func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
        switch weightUnit {
        case .kilograms:
            form.weightKg = number(weightText)
        case .pounds:
            form.weightKg = number(weightText).map { $0 / BodyMeasurementUnit.poundsPerKilogram }
        case .stone:
            let stone = number(stoneText), pounds = number(weightText)
            form.weightKg = stone == nil && pounds == nil ? nil : WeightUnit.kilograms(stone: stone ?? 0, pounds: pounds ?? 0)
        }
    }

    private func syncWeightText() {
        let texts = weightTexts(form.weightKg)
        stoneText = texts.stone
        weightText = texts.main
    }

    private var flowTitleBinding: Binding<String?> {
        Binding<String?>(
            get: { form.flow?.title },
            set: { newTitle in form.flow = FlowIntensity.allCases.first { $0.title == newTitle } }
        )
    }

    private func multiChips(_ values: [String], selection: Binding<Set<String>>, tint: Color, detail: @escaping (String) -> String? = { _ in nil }) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(values, id: \.self) { value in
                let selected = selection.wrappedValue.contains(value)
                LogChip(title: selected ? detail(value).map { "\(value) · \($0)" } ?? value : value, symbol: LogChip.symbol(for: value), tint: tint, selected: selected) {
                    if selection.wrappedValue.contains(value) { selection.wrappedValue.remove(value) } else { selection.wrappedValue.insert(value) }
                }
            }
        }
    }

    private func singleChips(_ values: [String], selection: Binding<String?>, tint: Color) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(values, id: \.self) { value in
                LogChip(title: value, symbol: LogChip.symbol(for: value), tint: tint, selected: selection.wrappedValue == value) {
                    selection.wrappedValue = selection.wrappedValue == value ? nil : value
                }
            }
        }
    }

    // MARK: Day navigation & saving

    private func step(_ delta: Int) {
        let calendar = Calendar.current
        guard let target = calendar.date(byAdding: .day, value: delta, to: date),
              calendar.startOfDay(for: target) <= calendar.startOfDay(for: .now) else { return }
        prepareSave(thenGoTo: target)
    }

    /// Moving to another day keeps what you entered, the same as Save does.
    /// A logged period that this day continues: it ended yesterday or the day
    /// before and started recently enough that this is plausibly the same
    /// bleed. Logging flow on such a day extends the period instead of asking
    /// whether a brand-new one has started.
    private var periodThisDayContinues: PeriodEvent? {
        let calendar = Calendar.current
        return realPeriods.last { period in
            let start = calendar.startOfDay(for: period.startDate)
            // Open-ended periods display as five days (see periodEvent(containing:)).
            let end = period.endDate ?? calendar.date(byAdding: .day, value: 4, to: start) ?? start
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: end), to: date).day ?? 99
            let length = (calendar.dateComponents([.day], from: calendar.startOfDay(for: period.startDate), to: date).day ?? 99) + 1
            return (1...2).contains(gap) && length <= FertilityWindowCalculator.plausiblePeriodLengthRange.upperBound
        }
    }

    private func prepareSave(thenGoTo target: Date?) {
        pendingDate = target
        if isDirty, form.flow != nil, baseline.flow == nil, stage.tracksCycle, let continued = periodThisDayContinues {
            continued.endDate = date
            save(startPeriod: false)
            finish()
            return
        }
        if isDirty,
           form.flow != nil,
           form.flow != baseline.flow,
           date <= .now,
           CycleTrackingService.periodStartConflict(on: date, periods: realPeriods) == nil,
           stage.tracksCycle,
           settings != nil {
            askToStartPeriod = true
            return
        }
        if isDirty || (target == nil && existing == nil && !form.isEmpty) {
            save(startPeriod: false)
        }
        finish()
    }

    private func finish() {
        guard let target = pendingDate else {
            dismiss()
            return
        }
        pendingDate = nil
        let next = DailyLogForm(allLogs.first { Calendar.current.isDate($0.date, inSameDayAs: target) })
        movingForward = target > date
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            date = Calendar.current.startOfDay(for: target)
            form = next
            baseline = next
        }
    }

    private func save(startPeriod: Bool) {
        let log = existing ?? DailyFertilityLog(date: date)
        let customSymptoms = form.customSymptomsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        log.symptoms = Array(form.symptoms.union(customSymptoms)).sorted(); log.moods = form.moods.sorted(); log.supplements = form.supplements.sorted()
        log.notes = form.notes
        log.flowIntensity = form.flow
        log.dayImpact = form.impact
        // A rating only survives while its symptom is still ticked.
        log.symptomSeverities = form.severities.filter { log.symptoms.contains($0.key) }
        log.hotFlushCount = form.hotFlushes
        log.nightSweatCount = form.nightSweats
        log.vasomotorSeverity = (form.hotFlushes ?? 0) + (form.nightSweats ?? 0) > 0 ? form.severity : nil
        log.sleepQuality = form.sleep
        log.hrtTaken = form.hrtTaken.sorted()
        // Only what was changed here becomes
        // the person's own entry, and only that is written to Apple Health.
        let weightChanged = form.weightKg != baseline.weightKg
        let waterChanged = form.waterMl != baseline.waterMl
        if weightChanged {
            log.weightKg = form.weightKg
            log.weightSource = .userConfirmed
        }
        if waterChanged {
            log.waterMl = form.waterMl
            log.waterSource = .userConfirmed
        }
        if existing == nil { modelContext.insert(log) }
        if let settings {
            let day = date
            if weightChanged {
                BodyMeasurementStore.refreshProfileWeight(settings: settings, logs: allLogs + [log])
                BodyMeasurementStore.writeToHealth(settings: settings) { await $0.saveWeight(kilograms: form.weightKg, on: day) }
            }
            if waterChanged {
                let water = form.waterMl
                BodyMeasurementStore.writeToHealth(settings: settings) { await $0.saveWater(millilitres: water, on: day) }
            }
        }
        if startPeriod, let settings {
            _ = CycleTrackingService.recordPeriodStart(date, settings: settings, records: cycleRecords, periods: periodEvents, context: modelContext)
        }
        try? modelContext.save()
        baseline = form
    }
}

/// A pill with an icon; bounces a little when chosen.
private struct LogChip: View {
    let title: String
    let symbol: String
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark" : symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selected ? Color.white : tint)
                    .frame(width: 24, height: 24)
                    .background(selected ? tint : tint.opacity(0.14), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(selected ? tint : Color.lineNavy.opacity(0.78))
            }
            .padding(.leading, 5)
            .padding(.trailing, 13)
            .padding(.vertical, 5)
            .background(selected ? tint.opacity(0.14) : Color.lineBackground, in: Capsule())
            .overlay(Capsule().stroke(selected ? tint.opacity(0.7) : Color.clear, lineWidth: 1.2))
            .scaleEffect(selected ? 1.03 : 1)
        }
        .buttonStyle(PressScaleButtonStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func symbol(for option: String) -> String {
        switch option {
        case "Spotting": "circle.dotted"
        case "Light": "drop"
        case "Medium": "drop.halffull"
        case "Heavy": "drop.fill"
        case "Anxiety": "exclamationmark.bubble"
        case "Irritability": "bolt"
        case "Low Mood": "cloud"
        case "Not at all": "sun.max"
        case "A bit": "cloud.sun"
        case "A lot": "cloud.rain"
        case "Brain Fog": "cloud.fog"
        case "Joint Pain": "figure.walk"
        case "Fatigue": "battery.25percent"
        case "Headache": "brain.head.profile"
        case "Palpitations": "heart.text.square"
        case "Vaginal Dryness": "sun.dust"
        case "Low Libido": "heart.slash"
        case "Bladder Leaks": "drop.triangle"
        case "Breast Tenderness": "heart.circle"
        case "Pelvic Pain": "bolt.heart"
        case "Bloating": "circle.circle"
        case "Dizziness": "tornado"
        case "Dry Skin": "hand.raised"
        case "Hair Thinning": "comb"
        case "Mild": "gauge.with.dots.needle.0percent"
        case "Moderate": "gauge.with.dots.needle.50percent"
        case "Severe": "gauge.with.dots.needle.100percent"
        case "Slept Well": "moon.zzz.fill"
        case "Broken Sleep": "moon.haze"
        case "Poor Sleep": "eye"
        case "Happy": "face.smiling"
        case "Calm": "leaf"
        case "Energetic": "bolt"
        case "Tearful": "drop"
        case "Overwhelmed": "tornado"
        case "Mood Swings": "arrow.up.arrow.down"
        case "Low Confidence": "person.fill.questionmark"
        case "Oestrogen Gel": "hand.point.up.left"
        case "Oestrogen Patch": "bandage"
        case "Oestrogen Spray": "aqi.medium"
        case "Oestrogen Tablet", "Combined Tablet": "pills"
        case "Progesterone": "capsule"
        case "Vaginal Oestrogen": "cross.vial"
        case "Testosterone": "drop.halffull"
        case "Vitamin D": "sun.max"
        case "Calcium": "circle.hexagongrid"
        case "Magnesium": "sparkles"
        case "Omega-3": "fish"
        case "Iron": "bolt.circle"
        case "Vitamin B12": "b.circle"
        case "Probiotic": "leaf.circle"
        default: "circle"
        }
    }
}

private struct LogSection<Content: View>: View {
    let section: DailyLogSection
    @ViewBuilder let content: Content
    init(_ section: DailyLogSection, @ViewBuilder content: () -> Content) { self.section = section; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(section.title, systemImage: section.symbol).font(.app(.headline)).foregroundStyle(Color.lineNavy).symbolRenderingMode(.hierarchical).tint(section.tint)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.black.opacity(0.05)))
        .id(section)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }
}

/// That day's activity, sleep and heart data from Apple Health. Read-only:
/// it's shown for context next to the journal, never edited here.
private struct HealthMetricsCard: View {
    let metrics: DailyHealthMetrics
    let unit: BodyMeasurementUnit

    private var items: [(symbol: String, value: String, label: String)] {
        var items: [(String, String, String)] = []
        if let steps = metrics.steps { items.append(("figure.walk", steps.formatted(.number.precision(.fractionLength(0))), "steps")) }
        if let km = metrics.walkingRunningKm, km > 0 { items.append(("point.topleft.down.to.point.bottomright.curvepath", String(format: "%.1f", unit.displayDistance(km)), "\(unit.distanceSymbol) walked")) }
        if let sleep = metrics.sleepHours, sleep > 0 {
            let minutes = Int((sleep * 60).rounded())
            items.append(("bed.double.fill", "\(minutes / 60)h \(minutes % 60)m", "asleep"))
        }
        if let active = metrics.activeEnergyKcal, active > 0 { items.append(("flame.fill", "\(Int(active.rounded()))", "active kcal")) }
        if let exercise = metrics.exerciseMinutes, exercise > 0 { items.append(("figure.run", "\(Int(exercise.rounded()))", "exercise min")) }
        if let count = metrics.workoutCount, count > 0 {
            items.append(("dumbbell.fill", "\(count)", count == 1 ? "workout" : "workouts"))
        }
        if let resting = metrics.restingHeartRate { items.append(("heart.fill", "\(Int(resting.rounded()))", "resting bpm")) }
        if let hrv = metrics.heartRateVariabilityMs { items.append(("waveform.path.ecg", "\(Int(hrv.rounded()))", "ms HRV")) }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("From Apple Health", systemImage: "heart.text.square.fill")
                .font(.app(.headline))
                .foregroundStyle(Color.lineNavy)
                .symbolRenderingMode(.hierarchical)
                .tint(Color.linePink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(items, id: \.label) { item in
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.linePink)
                        Text(item.value)
                            .font(.app(.subheadline, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(Color.lineNavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(item.label)
                            .font(.app(.caption2, weight: .semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.lineBackground, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                }
            }
            Text("Synced read-only from Apple Health.")
                .font(.app(.caption2))
                .foregroundStyle(Color.lineNavy.opacity(0.45))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.black.opacity(0.05)))
        .transition(.opacity)
    }
}
