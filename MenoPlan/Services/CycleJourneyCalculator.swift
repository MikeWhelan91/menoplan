import Foundation

/// The single "what's next" message Home leads with - one number and one
/// action, derived from the same fertility window every other screen uses.
struct HomeCountdown: Equatable {
    enum Stage: Equatable {
        case beforeOvulationTesting
        case ovulationTesting
        case fertile
        case ovulationDay
        case waitingToTest
        case earlyTesting
        case periodDue
        case periodLate
    }

    var stage: Stage
    /// Small line above the headline, e.g. "Time for a pregnancy test in".
    var caption: String
    /// The big figure. `value` drives the numeric text transition when it is a
    /// count; otherwise `headline` is shown verbatim ("Today").
    var value: Int?
    var unit: String?
    var headline: String
    /// Supporting line under the figure.
    var footnote: String
    /// The test that makes most sense for the quick "Test" action right now.
    var suggestedTest: TestType

    var isPregnancyPhase: Bool {
        [.waitingToTest, .earlyTesting, .periodDue, .periodLate].contains(stage)
    }
}

/// Every date in the "if you conceive this cycle" story, calculated once so
/// the story cards and Home card can't disagree with each other.
struct ConceptionTimeline: Equatable {
    var cycleStart: Date
    var cycleDay: Int
    var cycleLength: Int
    var ovulationDate: Date
    var ovulationIsConfirmed: Bool
    var fertileStart: Date
    var fertileEnd: Date
    var opkStart: Date
    var implantationStart: Date
    var implantationEnd: Date
    /// Around 10 DPO - early-result tests can sometimes show a line.
    var earliestTestDate: Date
    /// The expected period - a negative from here on is much more meaningful.
    var reliableTestDate: Date
    var dueDate: Date
}

/// Gestational age and milestones once a pregnancy is confirmed.
struct PregnancyProgress: Equatable {
    var gestationalDays: Int
    var dueDate: Date
    /// True once the user has corrected the due date themselves (e.g. after
    /// a dating scan), rather than us deriving it from cycle data.
    var isManualDueDate: Bool = false
    var weeks: Int { gestationalDays / 7 }
    var days: Int { gestationalDays % 7 }
    var trimester: Int {
        switch weeks {
        case ..<14: 1
        case 14..<28: 2
        default: 3
        }
    }
    var fractionComplete: Double { min(max(Double(gestationalDays) / 280.0, 0), 1) }
    var daysToGo: Int { max(0, 280 - gestationalDays) }
    var sizeComparison: String? { PregnancySizeGuide.comparison(forWeek: weeks) }

    var ageLabel: String {
        let weekPart = weeks == 1 ? "1 week" : "\(weeks) weeks"
        guard days > 0 else { return weekPart }
        return "\(weekPart), \(days) \(days == 1 ? "day" : "days")"
    }
}

enum CycleJourneyCalculator {
    /// Standard obstetric convention: 266 days from a known conception
    /// (ovulation) date, otherwise 280 days from the LMP adjusted for cycle
    /// length (Naegele's rule).
    static let ovulationToDueDateDays = 266
    static let lmpToDueDateDays = 280
    static let implantationDaysAfterOvulation = 6...10
    static let earlyTestDaysBeforePeriod = 4

    /// `tryingToConceive: false` is the "Track my cycle" mode: the same dates,
    /// but framed around the next period rather than when to test.
    static func countdown(
        on date: Date = .now,
        window: FertilityWindow,
        tryingToConceive: Bool = true,
        calendar: Calendar = .current
    ) -> HomeCountdown {
        let today = calendar.startOfDay(for: date)
        let opk = calendar.startOfDay(for: window.opkStartDate)
        let fertileStart = calendar.startOfDay(for: window.fertileStartDate)
        let ovulation = calendar.startOfDay(for: window.predictedOvulationDate)
        let period = calendar.startOfDay(for: window.nextPeriodDate)
        let earlyTest = calendar.date(byAdding: .day, value: -earlyTestDaysBeforePeriod, to: period) ?? period
        let fertileEnd = calendar.startOfDay(for: window.fertileEndDate)

        func days(to target: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: target).day ?? 0
        }
        func short(_ date: Date) -> String { DateFormatting.shortDate.string(from: date) }

        /// A widened range exists because ovulation may come after the
        /// estimate, so the days after it are still "possible fertile days"
        /// - the countdown must not move on to pregnancy testing yet, or it
        /// contradicts the calendar that still shows them as fertile.
        func stillPossiblyFertile() -> HomeCountdown? {
            guard window.isWidened, today > ovulation, today <= fertileEnd else { return nil }
            let count = days(to: fertileEnd)
            return HomeCountdown(
                stage: .fertile,
                caption: count == 0 ? "Last possible fertile day" : "Possible fertile days end in",
                value: count == 0 ? nil : count, unit: count == 0 ? nil : (count == 1 ? "Day" : "Days"),
                headline: count == 0 ? "Today" : "\(count) \(count == 1 ? "Day" : "Days")",
                footnote: window.profileWidening == nil
                    ? "Your cycles have varied, so ovulation may still be ahead. Keep ovulation testing"
                    : "Ovulation may still be ahead while MenoPlan learns your cycle. Keep ovulation testing",
                suggestedTest: .ovulation
            )
        }

        if !tryingToConceive {
            if today < fertileStart {
                let count = days(to: fertileStart)
                return HomeCountdown(stage: .beforeOvulationTesting, caption: "Fertile window in", value: count, unit: count == 1 ? "Day" : "Days",
                                     headline: "\(count) \(count == 1 ? "Day" : "Days")", footnote: "Next period expected \(short(period))", suggestedTest: .ovulation)
            }
            if today <= ovulation {
                let count = days(to: ovulation)
                return HomeCountdown(stage: count == 0 ? .ovulationDay : .fertile, caption: count == 0 ? "Estimated ovulation" : "Estimated ovulation in",
                                     value: count == 0 ? nil : count, unit: count == 0 ? nil : (count == 1 ? "Day" : "Days"),
                                     headline: count == 0 ? "Today" : "\(count) \(count == 1 ? "Day" : "Days")",
                                     footnote: "You’re in your estimated fertile window", suggestedTest: .ovulation)
            }
            if let possiblyFertile = stillPossiblyFertile() { return possiblyFertile }
            if today < period {
                let count = days(to: period)
                return HomeCountdown(stage: .waitingToTest, caption: "Next period in", value: count, unit: count == 1 ? "Day" : "Days",
                                     headline: "\(count) \(count == 1 ? "Day" : "Days")", footnote: "Expected \(short(period))", suggestedTest: .pregnancy)
            }
            if today == period {
                return HomeCountdown(stage: .periodDue, caption: "Period expected", value: nil, unit: nil, headline: "Today",
                                     footnote: "Log it when it starts to keep predictions accurate", suggestedTest: .pregnancy)
            }
            let late = -days(to: period)
            return HomeCountdown(stage: .periodLate, caption: "Your period is", value: late, unit: late == 1 ? "Day Late" : "Days Late",
                                 headline: "\(late) \(late == 1 ? "Day Late" : "Days Late")",
                                 footnote: "Cycles vary. If there’s a chance you’re pregnant, a test gives a clear answer", suggestedTest: .pregnancy)
        }

        if today < opk {
            let count = days(to: opk)
            return HomeCountdown(
                stage: .beforeOvulationTesting,
                caption: "Start ovulation tests in",
                value: count, unit: count == 1 ? "Day" : "Days",
                headline: "\(count) \(count == 1 ? "Day" : "Days")",
                footnote: "Your estimated fertile window starts \(short(fertileStart))",
                suggestedTest: .ovulation
            )
        }
        if today < fertileStart {
            let count = days(to: fertileStart)
            return HomeCountdown(
                stage: .ovulationTesting,
                caption: "Fertile window in",
                value: count, unit: count == 1 ? "Day" : "Days",
                headline: "\(count) \(count == 1 ? "Day" : "Days")",
                footnote: "Take an ovulation test today to catch your LH rise early",
                suggestedTest: .ovulation
            )
        }
        if today < ovulation {
            let count = days(to: ovulation)
            return HomeCountdown(
                stage: .fertile,
                caption: "Estimated ovulation in",
                value: count, unit: count == 1 ? "Day" : "Days",
                headline: "\(count) \(count == 1 ? "Day" : "Days")",
                footnote: "High fertility. Testing twice a day helps you catch your peak",
                suggestedTest: .ovulation
            )
        }
        if today == ovulation {
            return HomeCountdown(
                stage: .ovulationDay,
                caption: "Estimated ovulation",
                value: nil, unit: nil,
                headline: "Today",
                footnote: "Your estimated peak fertility day",
                suggestedTest: .ovulation
            )
        }
        if let possiblyFertile = stillPossiblyFertile() { return possiblyFertile }
        if today < earlyTest {
            let count = days(to: earlyTest)
            let untilPeriod = days(to: period)
            return HomeCountdown(
                stage: .waitingToTest,
                caption: "Time for a pregnancy test in",
                value: count, unit: count == 1 ? "Day" : "Days",
                headline: "\(count) \(count == 1 ? "Day" : "Days")",
                footnote: "Unless your period starts in \(untilPeriod) \(untilPeriod == 1 ? "day" : "days")",
                suggestedTest: .pregnancy
            )
        }
        if today < period {
            let untilPeriod = days(to: period)
            return HomeCountdown(
                stage: .earlyTesting,
                caption: "You can take an early test",
                value: nil, unit: nil,
                headline: "Today",
                footnote: "Most reliable from \(short(period)), in \(untilPeriod) \(untilPeriod == 1 ? "day" : "days")",
                suggestedTest: .pregnancy
            )
        }
        if today == period {
            return HomeCountdown(
                stage: .periodDue,
                caption: "Period expected",
                value: nil, unit: nil,
                headline: "Today",
                footnote: "If it doesn’t arrive, a test today gives a reliable answer",
                suggestedTest: .pregnancy
            )
        }
        let late = -days(to: period)
        return HomeCountdown(
            stage: .periodLate,
            caption: "Your period is",
            value: late, unit: late == 1 ? "Day Late" : "Days Late",
            headline: "\(late) \(late == 1 ? "Day Late" : "Days Late")",
            footnote: "A pregnancy test now gives a reliable answer",
            suggestedTest: .pregnancy
        )
    }

    /// Lets Home's countdown react to what CycleSignalsEngine found. The
    /// dates and the big number never change here - they come from the same
    /// prediction as the calendar - only the caption, the line underneath and
    /// the suggested test, when a signal changes what's worth doing today.
    /// One signal wins, in order of how much it changes the advice.
    static func reacting(_ countdown: HomeCountdown, to signals: [CycleSignal], tryingToConceive: Bool = true) -> HomeCountdown {
        var result = countdown
        func has(_ id: String) -> CycleSignal? { signals.first { $0.id == id } }
        let afterOvulation: Set<HomeCountdown.Stage> = [.waitingToTest, .earlyTesting, .periodDue, .periodLate]
        let dueOrLate: Set<HomeCountdown.Stage> = [.periodDue, .periodLate]

        if has("hormonalContraception") != nil {
            result.footnote = "Contraception is recorded, so these dates may not match your natural cycle"
            return result
        }
        if has("breastfeeding") != nil {
            result.footnote = "Breastfeeding can delay ovulation, so treat these dates as a rough guide"
            return result
        }
        guard tryingToConceive else { return result }

        if let high = has("sustainedHighTemperature"), afterOvulation.contains(countdown.stage) {
            result.footnote = "\(high.title). A pregnancy test now gives a clear answer"
            result.suggestedTest = .pregnancy
            return result
        }
        if let heart = has("restingHeartRateUp"), heart.tone == .attention, dueOrLate.contains(countdown.stage) {
            result.footnote = "Your resting heart rate is up too. A pregnancy test now gives a clear answer"
            return result
        }
        if let mucus = has("fertileMucus") {
            switch countdown.stage {
            case .beforeOvulationTesting:
                // Mucus before the calendar expects it: start testing today.
                result.caption = "Fertile mucus spotted"
                result.value = nil
                result.unit = nil
                result.headline = "Test Today"
                result.footnote = "It often comes before ovulation, so start ovulation tests now"
                result.suggestedTest = .ovulation
                return result
            case .ovulationTesting, .fertile, .ovulationDay:
                result.footnote = "Fertile-quality mucus logged. Ovulation is likely close"
                return result
            case .waitingToTest where mucus.title == "Fertile mucus later than expected",
                 .earlyTesting where mucus.title == "Fertile mucus later than expected":
                // A pregnancy-test countdown contradicts "ovulation may not
                // have happened yet", so both stages switch to Still Early.
                return ovulationMayBeLater(result, reason: "You logged fertile mucus after the estimate")
            default:
                break
            }
        }
        if has("healthLHSurge") != nil, [.ovulationTesting, .fertile, .ovulationDay].contains(countdown.stage) {
            result.footnote = "LH surge recorded in Apple Health. Ovulation is likely within 1-2 days"
            return result
        }
        if has("noTemperatureShiftYet") != nil, [.waitingToTest, .earlyTesting].contains(countdown.stage) {
            return ovulationMayBeLater(result, reason: "There's no temperature rise yet")
        }
        if has("temperatureShift") != nil, [.waitingToTest, .earlyTesting].contains(countdown.stage) {
            result.footnote = "Your temperature rise backs up this timing. " + countdown.footnote
            return result
        }
        return result
    }

    /// "You can take an early test / Today" contradicts a sign that ovulation
    /// hasn't happened yet, so the headline changes along with the footnote.
    private static func ovulationMayBeLater(_ countdown: HomeCountdown, reason: String) -> HomeCountdown {
        var result = countdown
        // Calm on purpose: "not yet", not a warning.
        result.caption = "Ovulation may be a little later"
        result.value = nil
        result.unit = nil
        result.headline = "Still Early"
        result.footnote = "\(reason), so an early pregnancy test may be too soon. Ovulation tests will show when it's close"
        result.suggestedTest = .ovulation
        return result
    }

    static func conceptionTimeline(
        window: FertilityWindow,
        cycle: CycleRecord?,
        calendar: Calendar = .current
    ) -> ConceptionTimeline {
        let start = calendar.startOfDay(for: window.cycleStart)
        let ovulation = calendar.startOfDay(for: window.predictedOvulationDate)
        let period = calendar.startOfDay(for: window.nextPeriodDate)
        let confirmed = cycle?.confirmedOvulationDate != nil && cycle?.ovulationSource != nil
        // Same dating rule as pregnancyProgress: any recorded ovulation (a
        // confirmed date or a Peak test) dates from ovulation, so the story's
        // "baby may be born around" matches the pregnancy screen later on.
        let datesFromOvulation = cycle?.ovulationSource != nil
        func add(_ days: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
        let length = max(1, calendar.dateComponents([.day], from: start, to: period).day ?? 28)
        return ConceptionTimeline(
            cycleStart: start,
            cycleDay: window.cycleDay,
            cycleLength: length,
            ovulationDate: ovulation,
            ovulationIsConfirmed: confirmed,
            fertileStart: calendar.startOfDay(for: window.fertileStartDate),
            fertileEnd: calendar.startOfDay(for: window.fertileEndDate),
            opkStart: calendar.startOfDay(for: window.opkStartDate),
            implantationStart: add(implantationDaysAfterOvulation.lowerBound, to: ovulation),
            implantationEnd: add(implantationDaysAfterOvulation.upperBound, to: ovulation),
            earliestTestDate: add(-earlyTestDaysBeforePeriod, to: period),
            reliableTestDate: period,
            dueDate: datesFromOvulation
                ? add(ovulationToDueDateDays, to: ovulation)
                : add(lmpToDueDateDays + (length - 28), to: start)
        )
    }

    /// Dating prefers a recorded ovulation (confirmed or Peak-supported);
    /// otherwise it's Naegele's rule from the LMP, shifted by however much
    /// this cycle differs from 28 days.
    static func pregnancyProgress(
        on date: Date = .now,
        cycle: CycleRecord,
        fallbackCycleLength: Int = 28,
        fallbackLutealLength: Int = 14,
        calendar: Calendar = .current
    ) -> PregnancyProgress {
        let today = calendar.startOfDay(for: date)
        let lmp = calendar.startOfDay(for: cycle.startDate)
        let dueDate: Date = {
            if let manual = cycle.manualDueDateOverride {
                return calendar.startOfDay(for: manual)
            }
            if cycle.ovulationSource != nil, let recorded = cycle.effectiveOvulationDate {
                let ovulation = calendar.startOfDay(for: recorded)
                return calendar.date(byAdding: .day, value: ovulationToDueDateDays, to: ovulation) ?? ovulation
            }
            let length = cycle.averageCycleLengthAtStart > 0 ? cycle.averageCycleLengthAtStart : fallbackCycleLength
            return calendar.date(byAdding: .day, value: lmpToDueDateDays + (length - 28), to: lmp) ?? lmp
        }()
        let daysUntilDue = calendar.dateComponents([.day], from: today, to: dueDate).day ?? 0
        return PregnancyProgress(
            gestationalDays: max(0, 280 - daysUntilDue),
            dueDate: dueDate,
            isManualDueDate: cycle.manualDueDateOverride != nil
        )
    }

    /// Short, cautious milestone notes for the pregnancy details sheet. These
    /// are user-ticked checkboxes, not date-derived: whether an appointment
    /// happened is something only the user knows, not something we can infer
    /// from gestational age.
    static func milestones(for _: PregnancyProgress) -> [(title: String, detail: String)] {
        return [
            ("First appointment", "Many people book a first antenatal or booking appointment between 8 and 12 weeks."),
            ("End of first trimester", "The first trimester ends at 13 weeks + 6 days."),
            ("Anatomy scan", "A detailed mid-pregnancy scan is commonly offered between 18 and 21 weeks."),
            ("Third trimester", "The third trimester begins at 28 weeks."),
            ("Full term", "Babies are considered full term from 37 weeks.")
        ]
    }
}
