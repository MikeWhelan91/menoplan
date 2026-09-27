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
        case periodDue
        case periodLate
    }

    var stage: Stage
    /// Small line above the headline, e.g. "Next period in".
    var caption: String
    /// The big figure. `value` drives the numeric text transition when it is a
    /// count; otherwise `headline` is shown verbatim ("Today").
    var value: Int?
    var unit: String?
    var headline: String
    /// Supporting line under the figure.
    var footnote: String
    /// The test that makes most sense for the quick "Test" action right now,
    /// if any.
    var suggestedTest: TestType?
}

enum CycleJourneyCalculator {
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
                                     headline: "\(count) \(count == 1 ? "Day" : "Days")", footnote: "Expected \(short(period))", suggestedTest: nil)
            }
            if today == period {
                return HomeCountdown(stage: .periodDue, caption: "Period expected", value: nil, unit: nil, headline: "Today",
                                     footnote: "Log it when it starts to keep predictions accurate", suggestedTest: nil)
            }
            let late = -days(to: period)
            return HomeCountdown(stage: .periodLate, caption: "Your period is", value: late, unit: late == 1 ? "Day Late" : "Days Late",
                                 headline: "\(late) \(late == 1 ? "Day Late" : "Days Late")",
                                 footnote: "Cycles often vary more in perimenopause", suggestedTest: nil)
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
        if today < period {
            let count = days(to: period)
            return HomeCountdown(
                stage: .waitingToTest,
                caption: "Next period in",
                value: count, unit: count == 1 ? "Day" : "Days",
                headline: "\(count) \(count == 1 ? "Day" : "Days")",
                footnote: "Expected \(short(period))",
                suggestedTest: nil
            )
        }
        if today == period {
            return HomeCountdown(
                stage: .periodDue,
                caption: "Period expected",
                value: nil, unit: nil,
                headline: "Today",
                footnote: "Log it when it starts to keep your timeline accurate",
                suggestedTest: nil
            )
        }
        let late = -days(to: period)
        return HomeCountdown(
            stage: .periodLate,
            caption: "Your period is",
            value: late, unit: late == 1 ? "Day Late" : "Days Late",
            headline: "\(late) \(late == 1 ? "Day Late" : "Days Late")",
            footnote: "Cycles often vary more in perimenopause",
            suggestedTest: nil
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
        let afterOvulation: Set<HomeCountdown.Stage> = [.waitingToTest, .periodDue, .periodLate]
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
            result.footnote = high.title
            result.suggestedTest = nil
            return result
        }
        if let heart = has("restingHeartRateUp"), heart.tone == .attention, dueOrLate.contains(countdown.stage) {
            result.footnote = "Your resting heart rate is up too"
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
            case .waitingToTest where mucus.title == "Fertile mucus later than expected":
                // A period countdown contradicts "ovulation may not have
                // happened yet", so it switches to Still Early.
                return ovulationMayBeLater(result, reason: "You logged fertile mucus after the estimate")
            default:
                break
            }
        }
        if has("healthLHSurge") != nil, [.ovulationTesting, .fertile, .ovulationDay].contains(countdown.stage) {
            result.footnote = "LH surge recorded in Apple Health. Ovulation is likely within 1-2 days"
            return result
        }
        if has("noTemperatureShiftYet") != nil, [.waitingToTest].contains(countdown.stage) {
            return ovulationMayBeLater(result, reason: "There's no temperature rise yet")
        }
        if has("temperatureShift") != nil, [.waitingToTest].contains(countdown.stage) {
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
        result.footnote = "\(reason). Ovulation tests will show when it's close"
        result.suggestedTest = .ovulation
        return result
    }

}
