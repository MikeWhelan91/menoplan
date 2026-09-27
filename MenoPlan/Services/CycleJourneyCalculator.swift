import Foundation

/// The single "what's next" message Home leads with - one number and one
/// line of context, derived from the same cycle estimate every other screen
/// uses. MenoPlan frames it around the next period only: cycles often
/// lengthen and vary in perimenopause, so a late period is expected news,
/// not an alarm.
struct HomeCountdown: Equatable {
    enum Stage: Equatable {
        case periodUpcoming
        case periodDue
        case periodLate
        /// A long wait: counted from the last period instead of as "late".
        case sinceLastPeriod
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
}

enum CycleJourneyCalculator {
    /// How long past the estimate a period counts as "late" before Home
    /// switches to counting days since the last one.
    static let lateWindowDays = 14

    static func countdown(
        on date: Date = .now,
        window: FertilityWindow,
        calendar: Calendar = .current
    ) -> HomeCountdown {
        let today = calendar.startOfDay(for: date)
        let period = calendar.startOfDay(for: window.nextPeriodDate)
        let toPeriod = calendar.dateComponents([.day], from: today, to: period).day ?? 0

        if toPeriod > 0 {
            return HomeCountdown(
                stage: .periodUpcoming,
                caption: "Next period in",
                value: toPeriod, unit: toPeriod == 1 ? "Day" : "Days",
                headline: "\(toPeriod) \(toPeriod == 1 ? "Day" : "Days")",
                footnote: "Expected \(DateFormatting.shortDate.string(from: period))"
            )
        }
        if toPeriod == 0 {
            return HomeCountdown(
                stage: .periodDue,
                caption: "Period expected",
                value: nil, unit: nil,
                headline: "Today",
                footnote: "Log it when it starts to keep your timeline accurate"
            )
        }
        let late = -toPeriod
        // Weeks past the estimate, "N days late" stops meaning much: in
        // perimenopause a long gap is expected, so count from the last period.
        if late > lateWindowDays {
            let since = calendar.dateComponents([.day], from: calendar.startOfDay(for: window.cycleStart), to: today).day ?? 0
            return HomeCountdown(
                stage: .sinceLastPeriod,
                caption: "Since your last period",
                value: since, unit: since == 1 ? "Day" : "Days",
                headline: "\(since) \(since == 1 ? "Day" : "Days")",
                footnote: "Longer gaps between periods are common in perimenopause"
            )
        }
        return HomeCountdown(
            stage: .periodLate,
            caption: "Your period is",
            value: late, unit: late == 1 ? "Day Late" : "Days Late",
            headline: "\(late) \(late == 1 ? "Day Late" : "Days Late")",
            footnote: "Cycles often vary more in perimenopause"
        )
    }

    /// Lets Home's countdown react to what CycleSignalsEngine found. The
    /// dates and the big number never change here - they come from the same
    /// estimate as the calendar - only the line underneath.
    static func reacting(_ countdown: HomeCountdown, to signals: [CycleSignal]) -> HomeCountdown {
        var result = countdown
        if signals.contains(where: { $0.id == "hormonalContraception" }) {
            result.footnote = "Hormonal contraception is recorded, so these dates may not match your natural cycle"
        }
        return result
    }
}
