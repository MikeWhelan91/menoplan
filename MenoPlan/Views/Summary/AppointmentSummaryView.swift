import SwiftData
import SwiftUI

// MARK: - Printable page

/// The one-page summary as it prints: A4, white, led by the top concerns.
struct AppointmentSummaryPage: View {
    static let size = CGSize(width: 595, height: 842)

    let summary: AppointmentSummary
    let name: String
    let impactNote: String
    let questions: [String]

    private func date(_ value: Date) -> String { value.formatted(.dateTime.day().month(.abbreviated).year()) }

    private var stageText: String {
        switch summary.stage {
        case .perimenopause: "Still having periods"
        case .postmenopause: "No period for 12+ months"
        case .unsure: "Stage unclear (e.g. hysterectomy, hormonal coil or continuous HRT)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            section("Main concerns") {
                if summary.concerns.isEmpty {
                    body("No symptoms logged in this period.")
                }
                ForEach(Array(summary.concerns.enumerated()), id: \.offset) { index, concern in
                    concernRow(index + 1, concern)
                }
            }
            section("Effect on daily life") {
                let rated = summary.impactNotAtAll + summary.impactSome + summary.impactLots
                if rated > 0 {
                    body(impactSentence)
                }
                if !impactNote.isEmpty {
                    body("In my words: \(impactNote)").italic()
                }
                if rated == 0 && impactNote.isEmpty {
                    body("Not recorded.")
                }
            }
            if !summary.otherSymptoms.isEmpty {
                section("Also logged") {
                    body(summary.otherSymptoms.prefix(8).map { "\($0.name) (\($0.days) \(plural($0.days, "day")))" }.joined(separator: ", "))
                }
            }
            HStack(alignment: .top, spacing: 18) {
                section("Sleep") {
                    body(summary.sleepLoggedNights == 0 ? "Not recorded." : "Broken or poor on \(summary.badSleepNights) of \(summary.sleepLoggedNights) nights recorded.")
                }
                section("Periods and bleeding") { periodsText }
            }
            section("Treatment") { treatmentText }
            if !summary.conditions.isEmpty {
                section("Other health") { body(summary.conditions.joined(separator: ", ")) }
            }
            if !summary.homeTests.isEmpty {
                section("Home FSH tests") {
                    body(summary.homeTests.suffix(4).map { "\(date($0.date)): \($0.result)" }.joined(separator: " · "))
                    small("FSH varies from day to day in perimenopause, so a single home result isn't diagnostic.")
                }
            }
            if !questions.isEmpty {
                section("Questions I'd like to ask") {
                    ForEach(Array(questions.prefix(6).enumerated()), id: \.offset) { index, question in
                        body("\(index + 1). \(question)")
                    }
                }
            }
            Spacer(minLength: 0)
            Divider()
            small("Recorded by the patient in MenoPlan on \(summary.loggedDays) of \(summary.totalDays) days. Self-reported symptoms, not a diagnosis. Generated \(date(.now)).")
        }
        .padding(36)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    /// "Symptoms affected the day a lot on 6 days and a bit on 18.", leaving out zeros.
    private var impactSentence: String {
        let parts = [
            summary.impactLots > 0 ? "a lot on \(summary.impactLots) \(plural(summary.impactLots, "day"))" : nil,
            summary.impactSome > 0 ? "a bit on \(summary.impactSome) \(plural(summary.impactSome, "day"))" : nil,
            summary.impactNotAtAll > 0 ? "not at all on \(summary.impactNotAtAll) \(plural(summary.impactNotAtAll, "day"))" : nil
        ].compactMap { $0 }
        let joined = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.joined()
        return "Symptoms affected the day \(joined)."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Menopause symptom summary")
                .font(.app(size: 22, weight: .heavy))
                .foregroundStyle(Color.lineNavy)
            Text([name.isEmpty ? nil : name, summary.age.map { "Age \($0)" }, stageText].compactMap { $0 }.joined(separator: " · "))
                .font(.app(size: 11, weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.75))
            Text("\(date(summary.start)) to \(date(summary.end)) · logged on \(summary.loggedDays) of \(summary.totalDays) days")
                .font(.app(size: 11))
                .foregroundStyle(Color.lineNavy.opacity(0.6))
            Rectangle()
                .fill(LinearGradient(colors: [Color.linePurple, Color.linePink], startPoint: .leading, endPoint: .trailing))
                .frame(height: 3)
                .padding(.top, 6)
        }
    }

    private func concernRow(_ number: Int, _ concern: AppointmentSummary.Concern) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.app(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.linePurple, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(concern.name)
                        .font(.app(size: 13, weight: .bold))
                        .foregroundStyle(Color.lineNavy)
                    Spacer()
                    Text("\(concern.daysPresent) of \(summary.loggedDays) logged days")
                        .font(.app(size: 11, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.7))
                }
                let details = [
                    concern.total.map { "\($0) counted in total" },
                    concern.usualSeverity.map { "usually \($0)" },
                    concern.worstSeverity.flatMap { $0 == concern.usualSeverity ? nil : "at worst \($0)" }
                ].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: ", "))
                        .font(.app(size: 11))
                        .foregroundStyle(Color.lineNavy.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var periodsText: some View {
        switch summary.stage {
        case .perimenopause:
            if let last = summary.lastPeriodStart {
                body("Last period started \(date(last)).")
            }
            if !summary.recentCycleLengths.isEmpty {
                body("Recent cycle lengths: \(summary.recentCycleLengths.map(String.init).joined(separator: ", ")) days.")
            }
            if summary.lastPeriodStart == nil {
                body("No periods recorded.")
            }
        case .postmenopause, .unsure:
            if summary.bleedingDays > 0 {
                body("Bleeding recorded on \(summary.bleedingDays) \(plural(summary.bleedingDays, "day")).")
                    .fontWeight(.bold)
                    .foregroundStyle(Color.linePink)
            } else {
                body("No bleeding recorded.")
            }
        }
    }

    @ViewBuilder
    private var treatmentText: some View {
        if summary.hrtRegimen.isEmpty {
            body("No HRT recorded.")
        } else {
            body("HRT: \(summary.hrtRegimen.joined(separator: ", "))\(summary.hrtDose.map { ", \($0)" } ?? "").")
            let dates = [summary.hrtStarted.map { "started \(date($0))" }, summary.hrtLastChanged.map { "last changed \(date($0))" }].compactMap { $0 }
            if !dates.isEmpty { body(dates.joined(separator: ", ").prefix(1).uppercased() + dates.joined(separator: ", ").dropFirst() + ".") }
            body("Marked as taken on \(summary.hrtTakenDays) of \(summary.loggedDays) logged days.")
        }
        if !summary.supplements.isEmpty {
            body("Supplements: \(summary.supplements.joined(separator: ", ")).")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.app(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Color.linePurple)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func body(_ text: String) -> Text {
        Text(text)
            .font(.app(size: 12))
            .foregroundStyle(Color.lineNavy)
    }

    private func small(_ text: String) -> some View {
        Text(text)
            .font(.app(size: 9))
            .foregroundStyle(Color.lineNavy.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func plural(_ count: Int, _ word: String) -> String { count == 1 ? word : word + "s" }
}

// MARK: - Editor

/// Builds, edits and shares the one-page summary.
struct AppointmentSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyFertilityLog.date) private var logs: [DailyFertilityLog]
    @Query(sort: \PeriodEvent.startDate) private var periodEvents: [PeriodEvent]
    @Query(sort: \CycleRecord.startDate) private var cycleRecords: [CycleRecord]
    @Query(sort: \Scan.createdAt) private var scans: [Scan]
    let settings: UserSettings

    @AppStorage("appointmentSummaryDays") private var days = 30
    @State private var shareItems: [Any]?
    @FocusState private var focusedField: Bool

    private static let sample = "[LineCheck Screenshot Sample]"

    private var periodStarts: [Date] {
        periodEvents.filter { !$0.notes.contains(Self.sample) }.map(\.startDate)
            + cycleRecords.filter { !$0.notes.contains(Self.sample) }.map(\.startDate)
    }

    private func summary(pinned: [String]?) -> AppointmentSummary {
        AppointmentSummaryBuilder.build(
            days: days,
            logs: logs.filter { !$0.notes.contains(Self.sample) },
            settings: settings,
            periodStarts: periodStarts,
            tests: scans.map { (date: $0.createdAt, result: $0.resultType.title) },
            pinned: pinned
        )
    }

    private var questions: [String] {
        (settings.appointmentQuestions ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var page: AppointmentSummaryPage {
        AppointmentSummaryPage(
            summary: summary(pinned: settings.appointmentConcerns),
            name: settings.userName,
            impactNote: (settings.appointmentImpactNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            questions: questions
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Period", selection: $days) {
                        Text("30 days").tag(30)
                        Text("60 days").tag(60)
                        Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)

                    editCard
                    preview
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { LineCheckBrandBackdrop() }
            .navigationTitle("Appointment summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .fontWeight(.bold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = false }
                }
            }
            .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
                if let shareItems {
                    ShareSheet(items: shareItems) { self.shareItems = nil }
                }
            }
        }
        .tint(Color.linePurple)
    }

    private var editCard: some View {
        let auto = summary(pinned: nil)
        let candidates = auto.concerns.map(\.key) + auto.otherSymptoms.map(\.name)
        let chosen = settings.appointmentConcerns ?? auto.concerns.map(\.key)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top concerns")
                        .font(.app(.headline, weight: .bold))
                        .foregroundStyle(Color.lineNavy)
                    Spacer()
                    if settings.appointmentConcerns != nil {
                        Button("Reset") {
                            settings.appointmentConcerns = nil
                            try? modelContext.save()
                        }
                        .font(.app(.caption, weight: .bold))
                    }
                }
                Text("Lead with up to three. A short, focused list is easier to cover in a short appointment.")
                    .font(.app(.caption))
                    .foregroundStyle(Color.lineNavy.opacity(0.6))
                if candidates.isEmpty {
                    Text("Log a few days first and your most frequent symptoms will appear here.")
                        .font(.app(.subheadline))
                        .foregroundStyle(Color.lineNavy.opacity(0.6))
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(candidates, id: \.self) { name in
                            concernChip(name, rank: chosen.firstIndex(of: name).map { $0 + 1 }, chosen: chosen)
                        }
                    }
                }
            }
            field(
                "How it's affecting my life",
                prompt: "e.g. I'm waking 3 times a night and struggling to concentrate at work",
                text: Binding(get: { settings.appointmentImpactNote ?? "" }, set: { settings.appointmentImpactNote = $0; try? modelContext.save() })
            )
            field(
                "Questions I'd like to ask",
                prompt: "One per line, e.g.\nCould this be perimenopause?\nIs HRT an option for me?",
                text: Binding(get: { settings.appointmentQuestions ?? "" }, set: { settings.appointmentQuestions = $0; try? modelContext.save() })
            )
        }
        .padding(16)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.black.opacity(0.05)))
    }

    private func concernChip(_ name: String, rank: Int?, chosen: [String]) -> some View {
        Button {
            var next = chosen
            if let index = next.firstIndex(of: name) {
                next.remove(at: index)
            } else if next.count < AppointmentSummaryBuilder.concernCount {
                next.append(name)
            } else {
                return
            }
            withAnimation(.snappy) { settings.appointmentConcerns = next }
            try? modelContext.save()
        } label: {
            HStack(spacing: 6) {
                if let rank {
                    Text("\(rank)")
                        .font(.app(.caption2, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.linePurple, in: Circle())
                }
                Text(name)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(rank == nil ? Color.lineNavy.opacity(0.78) : Color.linePurple)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(rank == nil ? Color.lineBackground : Color.linePurple.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(rank == nil ? Color.clear : Color.linePurple.opacity(0.6)))
        }
        .buttonStyle(PressScaleButtonStyle())
        .sensoryFeedback(.selection, trigger: rank)
    }

    private func field(_ title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(.headline, weight: .bold))
                .foregroundStyle(Color.lineNavy)
            TextField(prompt, text: text, axis: .vertical)
                .focused($focusedField)
                .lineLimit(3...8)
                .font(.app(.subheadline))
                .padding(12)
                .background(Color.lineBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.app(.headline, weight: .bold))
                .foregroundStyle(Color.lineNavy)
            GeometryReader { proxy in
                let scale = proxy.size.width / AppointmentSummaryPage.size.width
                page
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: proxy.size.width, height: AppointmentSummaryPage.size.height * scale, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .allowsHitTesting(false)
            }
            .aspectRatio(AppointmentSummaryPage.size.width / AppointmentSummaryPage.size.height, contentMode: .fit)
            Text("Self-reported and descriptive: it records what you logged, it doesn't diagnose.")
                .font(.app(.caption2))
                .foregroundStyle(Color.lineNavy.opacity(0.5))
        }
    }

    @MainActor
    private func share() {
        focusedField = false
        guard let url = Self.renderPDF(page) else { return }
        AppAnalytics.log("menoplan_appointment_summary_shared", ["days": days])
        shareItems = [url]
    }

    /// Vector PDF of the page, so text stays sharp when printed.
    @MainActor
    static func renderPDF(_ page: AppointmentSummaryPage) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "MenoPlan-Appointment-Summary.pdf")
        let renderer = ImageRenderer(content: page)
        var box = CGRect(origin: .zero, size: AppointmentSummaryPage.size)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
}
