import Foundation

/// The words a widget shows for a given day. Computed from the snapshot's
/// dates rather than stored, so the countdown keeps ticking at midnight even
/// when the app hasn't been opened. Wording follows Home's journey overview.
struct WidgetCycleSummary: Equatable {
    enum Tone: Equatable { case fertile, ovulation, period, neutral }

    var label: String
    var headline: String
    var detail: String
    var tone: Tone
    /// Short one-liner for the inline lock-screen widget.
    var inline: String
    var cycleDay: Int?
    var daysPastOvulation: Int?

    static func make(for snapshot: WidgetSnapshot, on date: Date, calendar: Calendar = .current) -> WidgetCycleSummary {
        switch snapshot.cycleState {
        case .notSetUp:
            return WidgetCycleSummary(label: "Your cycle", headline: "Set Up", detail: "Add your last period to see your timing",
                                      tone: .neutral, inline: "Set up your cycle in MenoPlan")
        case .pregnant:
            return WidgetCycleSummary(label: "Pregnancy", headline: "Confirmed", detail: "Cycle predictions are paused",
                                      tone: .period, inline: "Pregnancy confirmed")
        case .ended:
            return WidgetCycleSummary(label: "This cycle", headline: "Has Ended", detail: "Tap to start tracking a new cycle",
                                      tone: .neutral, inline: "Start tracking a new cycle")
        case .tracking:
            break
        }
        guard let cycle = snapshot.cycle else {
            return make(for: .empty, on: date, calendar: calendar)
        }

        let today = calendar.startOfDay(for: date)
        func days(to other: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: other)).day ?? 0
        }
        let cycleDay = -days(to: cycle.cycleStart) + 1
        let toOvulation = days(to: cycle.ovulation)
        let toFertile = days(to: cycle.fertileStart)
        let toPeriod = days(to: cycle.nextPeriod)
        let dpo = toOvulation < 0 ? -toOvulation : nil
        let estimate = cycle.isIrregular ? " · irregular cycle, so a wider estimate" : ""

        var summary: WidgetCycleSummary
        if toOvulation == 0 {
            summary = WidgetCycleSummary(label: "Ovulation", headline: "Today", detail: "Your most fertile day\(estimate)",
                                         tone: .ovulation, inline: "Estimated ovulation today")
        } else if toOvulation > 0 && toFertile <= 0 {
            summary = WidgetCycleSummary(label: "Ovulation", headline: titled(toOvulation),
                                         detail: "You're in your fertile window\(estimate)",
                                         tone: .fertile, inline: "Fertile window · ovulation \(countdown(toOvulation))")
        } else if toOvulation > 0 {
            let opkOpen = days(to: cycle.opkStart) <= 0
            summary = WidgetCycleSummary(label: "Fertile window", headline: titled(toFertile),
                                         detail: opkOpen ? "Time to start ovulation tests" : "Ovulation estimated \(shortDate(cycle.ovulation))",
                                         tone: .fertile, inline: "Fertile window \(countdown(toFertile))")
        } else if toPeriod > 0 {
            let dpoText = dpo.map { "\($0) DPO" } ?? "After ovulation"
            summary = WidgetCycleSummary(label: "Period", headline: titled(toPeriod),
                                         detail: toPeriod <= 4 ? "\(dpoText) · you can test now" : dpoText,
                                         tone: .period, inline: "Period \(countdown(toPeriod))")
        } else if toPeriod == 0 {
            summary = WidgetCycleSummary(label: "Period", headline: "Due Today", detail: "A pregnancy test today gives a reliable result",
                                         tone: .period, inline: "Period due today")
        } else {
            let late = -toPeriod
            let lateText = late == 1 ? "1 day late" : "\(late) days late"
            summary = WidgetCycleSummary(label: "Period", headline: late == 1 ? "1 Day Late" : "\(late) Days Late", detail: "Consider taking a pregnancy test",
                                         tone: .period, inline: "Period \(lateText)")
        }
        summary.cycleDay = cycleDay > 0 ? cycleDay : nil
        summary.daysPastOvulation = dpo
        return summary
    }

    private static func countdown(_ days: Int) -> String {
        switch days {
        case ...0: "today"
        case 1: "tomorrow"
        default: "in \(days) days"
        }
    }

    /// The big headline slot uses Title Case ("Tomorrow", "In 3 Days");
    /// sentences such as the inline widget keep `countdown`.
    private static func titled(_ days: Int) -> String {
        switch days {
        case ...0: "Today"
        case 1: "Tomorrow"
        default: "In \(days) Days"
        }
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
