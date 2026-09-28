import Foundation

/// The one-page appointment summary, as data. Led by the person's top three
/// concerns with how often and how badly each showed up, then the effect on
/// daily life, sleep, bleeding, treatment and their own questions. Everything
/// is self-reported and described, never interpreted as a diagnosis.
struct AppointmentSummary: Equatable {
    struct Concern: Equatable {
        /// The symptom as logged ("Sleep"), for picking concerns.
        var key: String
        /// As printed ("Broken or poor sleep").
        var name: String
        var daysPresent: Int
        /// Most common rating on days it was rated, e.g. "moderate".
        var usualSeverity: String?
        var worstSeverity: String?
        /// Hot flushes / night sweats: total counted in the period.
        var total: Int?
    }

    var start: Date
    var end: Date
    var totalDays: Int
    var loggedDays: Int
    var stage: MenopauseStage
    var age: Int?
    var concerns: [Concern]
    var otherSymptoms: [(name: String, days: Int)]
    var impactNotAtAll: Int
    var impactSome: Int
    var impactLots: Int
    var badSleepNights: Int
    var sleepLoggedNights: Int
    var bleedingDays: Int
    var lastPeriodStart: Date?
    var recentCycleLengths: [Int]
    var hrtRegimen: [String]
    var hrtDose: String?
    var hrtStarted: Date?
    var hrtLastChanged: Date?
    var hrtTakenDays: Int
    var supplements: [String]
    var homeTests: [(date: Date, result: String)]
    var conditions: [String]

    static func == (lhs: AppointmentSummary, rhs: AppointmentSummary) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end && lhs.loggedDays == rhs.loggedDays
            && lhs.concerns == rhs.concerns && lhs.otherSymptoms.map(\.name) == rhs.otherSymptoms.map(\.name)
            && lhs.impactLots == rhs.impactLots && lhs.bleedingDays == rhs.bleedingDays && lhs.hrtTakenDays == rhs.hrtTakenDays
    }

    /// Whether there's enough in the log to be worth printing.
    var isEmpty: Bool { loggedDays == 0 }
}

enum AppointmentSummaryBuilder {
    static let concernCount = 3

    /// - Parameter pinned: the person's own top concerns if they've chosen
    ///   them for this summary; otherwise their check-in symptoms lead, then
    ///   whatever they logged most.
    static func build(
        days: Int,
        logs: [DailyFertilityLog],
        settings: UserSettings,
        periodStarts: [Date],
        tests: [(date: Date, result: String)],
        pinned: [String]? = nil,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> AppointmentSummary {
        let end = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        var byDay: [Date: DailyFertilityLog] = [:]
        for log in logs where log.hasContent {
            let day = calendar.startOfDay(for: log.date)
            if day >= start && day <= end { byDay[day] = log }
        }
        let window = Array(byDay.values)

        // Every symptom seen, with how many days it appeared.
        var names = Set<String>()
        for log in window {
            names.formUnion(log.symptoms)
            if (log.hotFlushCount ?? 0) > 0 { names.insert(FocusSymptoms.hotFlushes) }
            if (log.nightSweatCount ?? 0) > 0 { names.insert(FocusSymptoms.nightSweats) }
            if log.sleepQuality == .broken || log.sleepQuality == .poor { names.insert(FocusSymptoms.sleep) }
        }
        func daysPresent(_ name: String) -> Int { window.filter { FocusSymptoms.isPresent(name, in: $0) }.count }
        let ranked = names.sorted { daysPresent($0) == daysPresent($1) ? $0 < $1 : daysPresent($0) > daysPresent($1) }

        let leading: [String]
        if let pinned, !pinned.isEmpty {
            leading = Array(pinned.prefix(concernCount))
        } else {
            let focus = settings.focusSymptoms.filter { daysPresent($0) > 0 }
                .sorted { daysPresent($0) > daysPresent($1) }
            leading = Array((focus + ranked.filter { !focus.contains($0) }).prefix(concernCount))
        }
        let concerns = leading.map { concern(named: $0, in: window) }
        let others = ranked.filter { !leading.contains($0) }.map { (name: $0, days: daysPresent($0)) }

        let hrtTakenDays = window.filter { !$0.hrtTaken.isEmpty }.count
        let supplements = Set(window.flatMap(\.supplements)).sorted()

        let cycle = CycleChangeCalculator.summary(periodStarts: periodStarts, on: date, calendar: calendar)

        return AppointmentSummary(
            start: start,
            end: end,
            totalDays: days,
            loggedDays: window.count,
            stage: settings.menopauseStage,
            age: settings.healthProfile.age(on: date, calendar: calendar),
            concerns: concerns,
            otherSymptoms: others,
            impactNotAtAll: window.filter { $0.dayImpact == .notAtAll }.count,
            impactSome: window.filter { $0.dayImpact == .some }.count,
            impactLots: window.filter { $0.dayImpact == .lots }.count,
            badSleepNights: window.filter { $0.sleepQuality == .broken || $0.sleepQuality == .poor }.count,
            sleepLoggedNights: window.filter { $0.sleepQuality != nil }.count,
            bleedingDays: window.filter { $0.flowIntensity != nil }.count,
            lastPeriodStart: cycle.lastPeriodStart,
            recentCycleLengths: cycle.recentCycleLengths,
            hrtRegimen: settings.hrtRegimen,
            hrtDose: settings.hrtDoseText,
            hrtStarted: settings.hrtStartDate,
            hrtLastChanged: settings.hrtLastChangedDate,
            hrtTakenDays: hrtTakenDays,
            supplements: supplements,
            homeTests: tests.filter { calendar.startOfDay(for: $0.date) >= start && calendar.startOfDay(for: $0.date) <= end }
                .sorted { $0.date < $1.date },
            conditions: settings.healthProfile.conditions.filter { $0 != .other }.map(\.title).sorted()
                + [settings.healthProfile.otherCondition].compactMap { $0?.isEmpty == false ? $0 : nil }
                + [settings.healthProfile.birthControl].compactMap { method in
                    guard let method, method.mayAffectRecentCycles else { return nil }
                    return "Hormonal contraception: \(method.title.prefix(1).lowercased() + method.title.dropFirst())"
                }
        )
    }

    private static func concern(named name: String, in window: [DailyFertilityLog]) -> AppointmentSummary.Concern {
        let present = window.filter { FocusSymptoms.isPresent(name, in: $0) }
        switch FocusSymptoms.kind(of: name) {
        case .counter:
            let total = present.reduce(0) { $0 + (FocusSymptoms.count(name, in: $1) ?? 0) }
            let severities = present.compactMap(\.vasomotorSeverity)
            return .init(key: name, name: name, daysPresent: present.count, usualSeverity: mode(severities)?.title.lowercased(),
                         worstSeverity: severities.max { $0.level < $1.level }?.title.lowercased(), total: total)
        case .sleep:
            let poor = present.filter { $0.sleepQuality == .poor }.count
            return .init(key: name, name: "Broken or poor sleep", daysPresent: present.count,
                         usualSeverity: present.isEmpty ? nil : (poor * 2 > present.count ? "poor" : "broken"),
                         worstSeverity: poor > 0 ? "poor" : nil, total: nil)
        case .severity:
            let severities = present.compactMap { $0.severity(of: name) }
            return .init(key: name, name: name, daysPresent: present.count, usualSeverity: mode(severities)?.title.lowercased(),
                         worstSeverity: severities.max { $0.level < $1.level }?.title.lowercased(), total: nil)
        }
    }

    private static func mode(_ values: [SymptomSeverity]) -> SymptomSeverity? {
        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        return counts.max { $0.value == $1.value ? $0.key.level < $1.key.level : $0.value < $1.value }?.key
    }
}
