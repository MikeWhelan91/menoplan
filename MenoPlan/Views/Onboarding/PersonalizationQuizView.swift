import SwiftData
import SwiftUI

/// Working copy of the quiz answers. Kept as a value type so onboarding and
/// the standalone sheet can both edit freely and only write to `UserSettings`
/// when the person finishes.
struct PersonalizationAnswers: Equatable {
    var birthYear: Int?
    var regularity: CycleRegularity?
    var conditions: Set<ReproductiveCondition> = []
    var noConditions = false
    var birthControl: BirthControlRecency?
    var otherCondition = ""
    var heightCm: Double?
    var weightKg: Double?
    var weightUnit: WeightUnit = .localeDefault
    var heightUnit: BodyMeasurementUnit = .localeDefault
    /// Only edited from the standalone About you sheet; onboarding asks for
    /// the name on its own page, so apply(to:) never writes it.
    var name = ""

    init() {}

    init(settings: UserSettings) {
        birthYear = settings.birthYearValue
        regularity = settings.cycleRegularity
        conditions = settings.reproductiveConditions
        // "" (rather than nil) records an explicit "none of these".
        noConditions = settings.reproductiveConditionsRaw == ""
        birthControl = settings.birthControlRecency
        otherCondition = settings.otherConditionTextValue ?? ""
        heightCm = settings.heightCmValue
        weightKg = settings.weightKgValue
        weightUnit = settings.weightUnit
        name = settings.userName
        heightUnit = settings.heightUnit
    }

    /// `context` lets a new weight also land in today's daily log (and Apple
    /// Health when connected), so the calendar starts with a first weigh-in.
    @MainActor
    func apply(to settings: UserSettings, context: ModelContext? = nil) {
        settings.birthYearValue = birthYear
        settings.cycleRegularity = regularity
        settings.reproductiveConditions = conditions
        if noConditions { settings.reproductiveConditionsRaw = "" }
        let trimmedOther = otherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.otherConditionTextValue = conditions.contains(.other) && !trimmedOther.isEmpty ? String(trimmedOther.prefix(80)) : nil
        settings.birthControlRecency = birthControl
        settings.weightUnit = weightUnit
        settings.heightUnit = heightUnit
        if let heightCm, heightCm != settings.heightCmValue {
            BodyMeasurementStore.recordHeight(heightCm, settings: settings)
        }
        if let weightKg, weightKg != settings.weightKgValue {
            if let context {
                BodyMeasurementStore.recordWeight(weightKg, on: .now, settings: settings, context: context)
            } else {
                settings.weightKgValue = weightKg
            }
        }
        settings.hasCompletedPersonalization = true
        // A new answer can re-open the doctor note if the situation changed.
        if !settings.healthProfile.shouldSuggestDoctor() { settings.dismissedDoctorSuggestion = false }

        AppAnalytics.log("linecheck_personalization_saved", [
            "regularity": regularity?.rawValue ?? "none",
            "has_conditions": conditions.isEmpty ? "false" : "true",
            "has_body_measurements": heightCm != nil && weightKg != nil ? "true" : "false"
        ])
    }
}

enum PersonalizationQuestion: Int, CaseIterable, Identifiable {
    case birthYear, bodyMeasurements, regularity, conditions, birthControl
    /// Standalone About you sheet only - onboarding has its own name page.
    case name
    var id: Int { rawValue }

    /// Asking about period regularity only makes sense while periods continue.
    static func sequence(for stage: MenopauseStage) -> [PersonalizationQuestion] {
        allCases.filter { $0 != .name && ($0 != .regularity || stage.tracksCycle) }
    }

    var title: String {
        switch self {
        case .name: "What should we call you?"
        case .birthYear: "What year were you born?"
        case .bodyMeasurements: "How tall are you, and what do you weigh?"
        case .regularity: "How have your periods been lately?"
        case .conditions: "Anything a doctor would want to know?"
        case .birthControl: "Do you use hormonal contraception?"
        }
    }

    var subtitle: String? {
        switch self {
        case .name: "Luna and MenoPlan use your first name. It stays with your app data."
        case .birthYear: "Age changes when it’s worth checking in with a doctor, so we only use it for that."
        case .bodyMeasurements: "Weight changes are common through menopause. You can update it any day in the calendar."
        case .regularity: "Think about the gap between periods over the last year."
        case .conditions: "Some of these change which treatments suit you or what bleeding means. Choose any that apply."
        case .birthControl: "Including a hormonal coil. These can change bleeding and affect home FSH tests."
        }
    }

    func isAnswered(_ answers: PersonalizationAnswers) -> Bool {
        switch self {
        case .name: !answers.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .birthYear: answers.birthYear != nil
        case .bodyMeasurements: answers.heightCm != nil && answers.weightKg != nil
        case .regularity: answers.regularity != nil
        case .conditions: !answers.conditions.isEmpty || answers.noConditions
        case .birthControl: answers.birthControl != nil
        }
    }

    func clear(_ answers: inout PersonalizationAnswers) {
        switch self {
        case .name: break
        case .birthYear: answers.birthYear = nil
        case .bodyMeasurements: answers.heightCm = nil; answers.weightKg = nil
        case .regularity: answers.regularity = nil
        case .conditions: answers.conditions = []; answers.noConditions = false; answers.otherCondition = ""
        case .birthControl: answers.birthControl = nil
        }
    }
}

// MARK: - One question

struct PersonalizationQuestionView: View {
    let question: PersonalizationQuestion
    @Binding var answers: PersonalizationAnswers

    @State private var pickerYear = Calendar.current.component(.year, from: .now) - 30
    @State private var showOtherPrompt = false
    @State private var otherDraft = ""

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        return Array((current - 60)...(current - 16)).reversed()
    }

    var body: some View {
        if question == .birthYear {
            birthYearLayout
        } else if question == .name {
            nameLayout
        } else if question == .bodyMeasurements {
            BodyMeasurementsQuestion(answers: $answers, header: AnyView(header))
        } else {
            standardLayout
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(question.title)
                .font(.app(size: LineType.size(27), weight: .heavy))
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = question.subtitle {
                Text(subtitle)
                    .font(.app(size: LineType.size(15), weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var age: Int? {
        answers.birthYear.map { Calendar.current.component(.year, from: .now) - $0 }
    }

    private var nameLayout: some View {
        VStack(spacing: 24) {
            header
                .padding(.top, 12)
            // Equal space above and below puts the field about halfway down.
            Spacer()
            TextField("First name", text: $answers.name)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.app(size: LineType.size(24), weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .padding(.horizontal, 16)
                .frame(minHeight: LineType.size(62))
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: QuizStyle.cornerRadius, style: .continuous))
                .frame(maxWidth: 420)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The year question fills the page: a tall wheel of large years, with
    /// the resulting age shown live above it.
    private var birthYearLayout: some View {
        VStack(spacing: 14) {
            header
                .padding(.top, 12)

            if let age {
                // Stacked so the number itself sits on the page's centre line.
                VStack(spacing: 0) {
                    Text("\(age)")
                        .font(.app(size: LineType.size(40), weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.linePink)
                        .contentTransition(.numericText(value: Double(age)))
                    Text("years old")
                        .font(.app(size: LineType.size(13), weight: .bold))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.lineNavy.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: age)
            }

            BirthYearWheel(years: years, selection: Binding(
                get: { answers.birthYear ?? pickerYear },
                set: { answers.birthYear = $0 }
            ))
            .frame(maxWidth: 520)
            .frame(maxHeight: .infinity)
            .onAppear { if answers.birthYear == nil { answers.birthYear = pickerYear } }

            Group {
                if let age, age >= 35 {
                    QuizNote(text: "From 35, doctors suggest a check-up after 6 months of trying rather than 12. We’ll keep that in mind.")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Text("Scroll to pick your year")
                        .font(.app(size: LineType.size(14), weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.4))
                }
            }
            .frame(minHeight: 44)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: (age ?? 0) >= 35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
    }

    // MARK: Standard questions

    private struct QuizOption: Identifiable {
        let id: String
        let title: String
        let response: String?
        let isSelected: Bool
        let action: () -> Void
    }

    private var quizOptions: [QuizOption] {
        switch question {
        case .birthYear, .bodyMeasurements, .name:
            return []
        case .regularity:
            return CycleRegularity.allCases.map { option in
                QuizOption(id: option.rawValue, title: option.title, response: option.response, isSelected: answers.regularity == option) { answers.regularity = option }
            }
        case .conditions:
            var options = ReproductiveCondition.allCases.map { option in
                let typed = answers.otherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = option == .other && answers.conditions.contains(.other) && !typed.isEmpty ? typed : option.shortTitle
                return QuizOption(id: option.rawValue, title: title, response: option.response, isSelected: answers.conditions.contains(option)) {
                    answers.noConditions = false
                    if answers.conditions.contains(option) {
                        answers.conditions.remove(option)
                        if option == .other { answers.otherCondition = "" }
                    } else {
                        answers.conditions.insert(option)
                        // Ask what it is, so "something else" is useful to Luna.
                        if option == .other {
                            otherDraft = answers.otherCondition
                            showOtherPrompt = true
                        }
                    }
                }
            }
            options.append(QuizOption(id: "none", title: "None of these", response: nil, isSelected: answers.noConditions) {
                answers.noConditions.toggle()
                if answers.noConditions { answers.conditions = [] }
            })
            return options
        case .birthControl:
            return BirthControlRecency.allCases.map { option in
                QuizOption(id: option.rawValue, title: option.title, response: option.response, isSelected: answers.birthControl == option) { answers.birthControl = option }
            }
        }
    }

    /// The note for whatever's picked (the last selected option that has
    /// something to say).
    private var note: String? {
        quizOptions.last { $0.isSelected && $0.response != nil }?.response
    }

    /// Same spec as the year page: header, a vertically centred block of big
    /// centred choices, and a centred note underneath.
    private var standardLayout: some View {
        let options = quizOptions
        let hasSelection = options.contains(where: \.isSelected)
        let rowHeight: CGFloat = switch options.count {
        case ...3: 80
        case 4...5: 64
        case 6: 52
        default: 46
        }
        return VStack(spacing: 14) {
            header
                .padding(.top, 12)

            Spacer(minLength: 8)

            VStack(spacing: options.count > 6 ? 6 : options.count > 5 ? 8 : 10) {
                ForEach(options) { option in
                    QuizChoiceRow(
                        title: option.title,
                        isSelected: option.isSelected,
                        isDimmed: hasSelection && !option.isSelected && question != .conditions,
                        height: rowHeight,
                        action: option.action
                    )
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                if let note {
                    QuizNote(text: note)
                        .id(note)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if !hasSelection {
                    Text(question == .conditions ? "Tap any that apply" : "Tap to choose")
                        .font(.app(size: LineType.size(14), weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.4))
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 44)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: note)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: answers.conditions)
        .alert("What’s the condition?", isPresented: $showOtherPrompt) {
            TextField("e.g. Hashimoto’s", text: $otherDraft)
                .textInputAutocapitalization(.sentences)
            Button("Save") { answers.otherCondition = String(otherDraft.prefix(80)) }
            Button("Skip", role: .cancel) {}
        } message: {
            Text("Optional. Luna can take it into account when explaining your results.")
        }
    }
}

/// Shared look for every quiz page, taken from the year wheel.
enum QuizStyle {
    static let cornerRadius: CGFloat = 22
    static let band = LinearGradient(
        colors: [Color.linePink, Color(red: 0.93, green: 0.30, blue: 0.62)],
        startPoint: .leading, endPoint: .trailing
    )
}

/// One choice: big centred type; picked, it becomes the pink band from the
/// year wheel and the others step back.
private struct QuizChoiceRow: View {
    let title: String
    let isSelected: Bool
    let isDimmed: Bool
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { action() }
        } label: {
            Text(title)
                .font(.app(size: LineType.size(height < 50 ? (isSelected ? 21 : 19) : height > 70 ? (isSelected ? 27 : 24) : (isSelected ? 24 : 21)), weight: .heavy))
                .foregroundStyle(isSelected ? Color.white : Color.lineNavy.opacity(isDimmed ? 0.3 : 0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background {
                    RoundedRectangle(cornerRadius: QuizStyle.cornerRadius, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(QuizStyle.band) : AnyShapeStyle(Color.white.opacity(isDimmed ? 0.35 : 0.7)))
                        .shadow(color: isSelected ? Color.linePink.opacity(0.22) : .clear, radius: 6, y: 3)
                }
                .padding(.horizontal, isSelected ? 0 : 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The centred purple note used under every question.
struct QuizNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.app(size: LineType.size(14), weight: .semibold))
            .foregroundStyle(Color.linePurple)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

/// A tall, snapping year wheel: the centred year is large and sits on a
/// pink band; neighbours shrink, tilt and fade away toward the edges.
struct BirthYearWheel: View {
    let years: [Int]
    @Binding var selection: Int

    @State private var scrolledYear: Int?
    private let rowHeight: CGFloat = 66

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: QuizStyle.cornerRadius, style: .continuous)
                    .fill(QuizStyle.band)
                    .frame(height: rowHeight)
                    .shadow(color: Color.linePink.opacity(0.22), radius: 6, y: 3)
                    .padding(.horizontal, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(years, id: \.self) { year in
                            let isSelected = year == (scrolledYear ?? selection)
                            Text(String(year))
                                .font(.app(size: LineType.size(44), weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Color.white : Color.lineNavy)
                                .frame(maxWidth: .infinity)
                                .frame(height: rowHeight)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { scrolledYear = year }
                                }
                                .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                    content
                                        .scaleEffect(1 - min(abs(phase.value), 1) * 0.45)
                                        .opacity(1 - min(abs(phase.value), 1) * 0.8)
                                        .rotation3DEffect(.degrees(phase.value * -40), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                                }
                                .id(year)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.vertical, max(0, (proxy.size.height - rowHeight) / 2), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledYear, anchor: .center)
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .frame(minHeight: 260)
        .onAppear { scrolledYear = selection }
        .onChange(of: scrolledYear) { _, year in
            guard let year, year != selection else { return }
            selection = year
        }
        .sensoryFeedback(.selection, trigger: scrolledYear)
        .accessibilityElement()
        .accessibilityLabel("Year of birth")
        .accessibilityValue(String(selection))
        .accessibilityAdjustableAction { direction in
            guard let index = years.firstIndex(of: selection) else { return }
            let next = direction == .increment ? index - 1 : index + 1
            if years.indices.contains(next) { scrolledYear = years[next] }
        }
    }
}

// MARK: - Standalone sheet

/// The same questions, reachable after onboarding from Home or Settings.
struct PersonalizationQuizSheet: View {
    let settings: UserSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var answers: PersonalizationAnswers
    @State private var index = 0
    @State private var forward = true
    @State private var finished = false
    private let questions: [PersonalizationQuestion]

    init(settings: UserSettings) {
        self.settings = settings
        _answers = State(initialValue: PersonalizationAnswers(settings: settings))
        questions = [.name] + PersonalizationQuestion.sequence(for: settings.menopauseStage)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    if index == 0 || finished { dismiss() } else { go(-1) }
                } label: {
                    Image(systemName: index == 0 || finished ? "xmark" : "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.lineNavy)
                        .frame(width: 36, height: 36)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(index == 0 ? "Close" : "Back")

                QuizProgressBar(fraction: finished ? 1 : Double(index + 1) / Double(questions.count + 1))

                Button("Skip") {
                    questions[index].clear(&answers)
                    advance()
                }
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.45))
                .opacity(finished ? 0 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ZStack {
                if finished {
                    QuizCompleteView(profile: previewProfile)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                } else {
                    PersonalizationQuestionView(question: questions[index], answers: $answers)
                        .id(questions[index])
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity, alignment: .top)

            Button(finished ? "Done" : "Next") {
                if finished {
                    settings.userName = answers.name
                    answers.apply(to: settings, context: modelContext)
                    try? modelContext.save()
                    dismiss()
                } else {
                    advance()
                }
            }
            .buttonStyle(.primaryLine)
            .disabled(!finished && !questions[index].isAnswered(answers))
            .opacity(!finished && !questions[index].isAnswered(answers) ? 0.45 : 1)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .animation(.easeOut(duration: 0.2), value: answers)
        }
        .background { LineCheckBrandBackdrop() }
        .interactiveDismissDisabled(index > 0 && !finished)
    }

    private var previewProfile: HealthProfile {
        HealthProfile(birthYear: answers.birthYear, regularity: answers.regularity, conditions: answers.conditions, birthControl: answers.birthControl, heightCm: answers.heightCm, weightKg: answers.weightKg)
    }

    private func advance() {
        if index < questions.count - 1 {
            go(1)
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { finished = true }
        }
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.88)) { index += delta }
    }
}

struct QuizProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Color.lineNavy.opacity(0.1))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [.linePurple, .linePink], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * fraction)
                }
        }
        .frame(height: 5)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
    }
}

/// A short recap of what the answers changed, so the questions feel worth it.
struct QuizCompleteView: View {
    let profile: HealthProfile
    @State private var shown = 0

    private var changes: [(String, String)] {
        var items: [(String, String)] = []
        if profile.predictionsLessCertain {
            items.append(("calendar.badge.exclamationmark", "Cycle dates will be shown as a wider estimate"))
        }
        if profile.shouldSuggestDoctor() {
            items.append(("stethoscope", "We’ll suggest when it may help to talk to a doctor"))
        }
        if items.isEmpty {
            items.append(("sparkles", "Your tips and timing are tailored to your answers"))
        }
        items.append(("lock.fill", "Your answers stay private in your MenoPlan data"))
        return items
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.linePurple, .linePink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.bounce, value: shown > 0)
                .padding(.top, 40)
            Text("Thanks, that’s everything")
                .font(.app(size: LineType.size(28), weight: .heavy))
                .foregroundStyle(Color.lineNavy)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(changes.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: item.0)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.linePurple)
                            .frame(width: 34, height: 34)
                            .background(Color.linePurple.opacity(0.1), in: Circle())
                        Text(item.1)
                            .font(.app(size: LineType.size(15), weight: .semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(shown > index ? 1 : 0)
                    .offset(x: shown > index ? 0 : 20)
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .task {
            for count in 1...changes.count {
                try? await Task.sleep(for: .milliseconds(count == 1 ? 250 : 120))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown = count }
            }
        }
    }
}


// MARK: - Height & weight

/// Height and weight as two wheels, each with its own unit switch so people
/// can mix units (pounds with centimetres, say). Values are held metric.
struct BodyMeasurementsQuestion: View {
    @Binding var answers: PersonalizationAnswers
    let header: AnyView

    var body: some View {
        VStack(spacing: 14) {
            header
                .padding(.top, 12)

            VStack(spacing: 6) {
                measurementLabel("HEIGHT", switch: UnitSwitch(selection: $answers.heightUnit, options: [(.metric, "cm"), (.imperial, "ft")]))
                BodyHeightPicker(heightCm: Binding(
                    get: { answers.heightCm ?? 165 },
                    set: { answers.heightCm = $0 }
                ), unit: answers.heightUnit)
                .frame(height: 120)
            }

            VStack(spacing: 6) {
                measurementLabel("WEIGHT", switch: UnitSwitch(selection: $answers.weightUnit, options: WeightUnit.allCases.map { ($0, $0.shortTitle) }))
                BodyWeightPicker(weightKg: Binding(
                    get: { answers.weightKg ?? 65 },
                    set: { answers.weightKg = $0 }
                ), unit: answers.weightUnit)
                .frame(height: 120)
            }

            Group {
                if let category = previewCategory, let bmi = previewBMI {
                    QuizNote(text: "BMI \(String(format: "%.1f", bmi)) · \(category.title)")
                } else {
                    Text("Scroll to set each value")
                        .font(.app(size: LineType.size(14), weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.4))
                }
            }
            .frame(minHeight: 44)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 8)
        .onAppear {
            // Showing a value that isn't saved would be misleading, so the
            // defaults become the answer as soon as the page is on screen.
            if answers.heightCm == nil { answers.heightCm = 165 }
            if answers.weightKg == nil { answers.weightKg = 65 }
        }
        .animation(.snappy, value: answers.weightUnit)
        .animation(.snappy, value: answers.heightUnit)
    }

    /// "HEIGHT  cm | ft" - the label with its own small unit switch.
    private func measurementLabel<Unit: Hashable>(_ title: String, switch unitSwitch: UnitSwitch<Unit>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.app(size: LineType.size(12), weight: .heavy))
                .tracking(1.1)
                .foregroundStyle(Color.lineNavy.opacity(0.45))
            unitSwitch
        }
    }

    private var previewBMI: Double? {
        HealthProfile(conditions: [], heightCm: answers.heightCm, weightKg: answers.weightKg).bmi
    }
    private var previewCategory: BMICategory? { previewBMI.map(BMICategory.init(bmi:)) }
}

/// A compact unit switch ("cm | ft", "kg | lb | st").
struct UnitSwitch<Unit: Hashable>: View {
    @Binding var selection: Unit
    let options: [(Unit, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let (unit, title) = options[index]
                Button {
                    withAnimation(.snappy) { selection = unit }
                } label: {
                    Text(title)
                        .font(.app(size: LineType.size(12), weight: .bold))
                        .foregroundStyle(selection == unit ? Color.white : Color.lineNavy.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selection == unit ? Color.linePurple : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == unit ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.lineNavy.opacity(0.06), in: Capsule())
    }
}

/// Height as one wheel - "165 cm" or "5′ 5″" - so there's a single
/// selection band rather than separate feet and inches wheels.
struct BodyHeightPicker: View {
    @Binding var heightCm: Double
    let unit: BodyMeasurementUnit

    var body: some View {
        Group {
            if unit == .metric {
                Picker("Height", selection: Binding(
                    get: { min(220, max(120, Int(heightCm.rounded()))) },
                    set: { heightCm = Double($0) }
                )) {
                    ForEach(120...220, id: \.self) { Text("\($0) cm").tag($0) }
                }
            } else {
                Picker("Height", selection: Binding(
                    get: { min(84, max(48, Int((heightCm / BodyMeasurementUnit.centimetresPerInch).rounded()))) },
                    set: { heightCm = Double($0) * BodyMeasurementUnit.centimetresPerInch }
                )) {
                    ForEach(48...84, id: \.self) { inches in
                        Text("\(inches / 12)′ \(inches % 12)″").tag(inches)
                    }
                }
            }
        }
        .pickerStyle(.wheel)
        .accessibilityLabel("Height")
    }
}

/// Weight as one wheel: whole kilograms, whole pounds, or stone and pounds
/// ("10 st 3 lb"). The daily log takes decimals; a starting weight doesn't
/// need them.
struct BodyWeightPicker: View {
    @Binding var weightKg: Double
    let unit: WeightUnit

    /// The wheel works in whole kg, or whole pounds for both lb and stone.
    private var range: ClosedRange<Int> { unit == .kilograms ? 30...250 : 66...550 }

    private var selected: Int {
        let value = unit == .kilograms ? weightKg : weightKg * BodyMeasurementUnit.poundsPerKilogram
        return min(range.upperBound, max(range.lowerBound, Int(value.rounded())))
    }

    private func label(_ value: Int) -> String {
        switch unit {
        case .kilograms: "\(value) kg"
        case .pounds: "\(value) lb"
        case .stone: "\(value / 14) st \(value % 14) lb"
        }
    }

    var body: some View {
        Picker("Weight", selection: Binding(
            get: { selected },
            set: { weightKg = unit == .kilograms ? Double($0) : Double($0) / BodyMeasurementUnit.poundsPerKilogram }
        )) {
            ForEach(range, id: \.self) { Text(label($0)).tag($0) }
        }
        .pickerStyle(.wheel)
        .accessibilityLabel("Weight")
    }
}
