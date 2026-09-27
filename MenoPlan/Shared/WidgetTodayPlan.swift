import Foundation

/// The "Today's Plan" widget answers one question - "where am I in my
/// cycle?" - then lists the next date that matters. Cycles often lengthen
/// and vary in perimenopause, so a late period is framed as expected news.
struct WidgetTodayPlan: Equatable {
    enum Phase: Equatable { case idle, upcoming, periodDue }
    enum Action: Equatable { case logPeriod }

    /// A date coming up, e.g. "Period Due" on Wed 1.
    struct Stop: Equatable {
        var title: String
        var date: Date
    }

    var phase: Phase
    /// Small-caps context, e.g. "Cycle day 24".
    var label: String
    /// The answer, e.g. "Period due Friday".
    var headline: String
    /// The reason, e.g. "Expected Fri 3 Oct".
    var detail: String
    /// Short version of `detail` for the small widget.
    var compactDetail: String
    /// One practical tip, shown when there's no action to take.
    var tip: String?
    /// Only set when there's something worth doing today.
    var action: Action?
    /// Today's job is done - the headline gets a tick.
    var isDone: Bool
    /// The next key dates after today, soonest first (at most 3).
    var stops: [Stop]

    static let idle = WidgetTodayPlan(
        phase: .idle, label: "", headline: "", detail: "", compactDetail: "", tip: nil,
        action: nil, isDone: false, stops: []
    )

    static func make(for snapshot: WidgetSnapshot, on date: Date, calendar: Calendar = .current) -> WidgetTodayPlan {
        guard snapshot.cycleState == .tracking, let cycle = snapshot.cycle else { return .idle }

        let today = calendar.startOfDay(for: date)
        func days(to other: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: other)).day ?? 0
        }
        /// "today", "tomorrow", "Friday" within the week, otherwise "Fri 3 Oct".
        func friendly(_ date: Date) -> String {
            switch days(to: date) {
            case 0: return "today"
            case 1: return "tomorrow"
            case 2...6: return date.formatted(.dateTime.weekday(.wide))
            default: return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
        }

        let cycleDay = max(1, -days(to: cycle.cycleStart) + 1)
        let toPeriod = days(to: cycle.nextPeriod)
        let stops = toPeriod > 0 ? [Stop(title: "Period Due", date: calendar.startOfDay(for: cycle.nextPeriod))] : []

        if toPeriod > 0 {
            return WidgetTodayPlan(
                phase: .upcoming,
                label: "Cycle day \(cycleDay)",
                headline: toPeriod == 1 ? "Period Due Tomorrow" : "Period Due \(friendly(cycle.nextPeriod).capitalized)",
                detail: cycle.isIrregular ? "Your cycles vary, so this is an estimate" : "Expected \(friendly(cycle.nextPeriod))",
                compactDetail: "Expected \(friendly(cycle.nextPeriod))",
                tip: "Logging symptoms daily makes patterns easier to spot",
                action: nil, isDone: false, stops: stops
            )
        }
        let late = -toPeriod
        return WidgetTodayPlan(
            phase: .periodDue,
            label: late == 0 ? "Period due today" : (late == 1 ? "Period 1 day late" : "Period \(late) days late"),
            headline: late == 0 ? "Period Due Today" : "Period Is Late",
            detail: "Log it when it starts to keep your timeline accurate",
            compactDetail: "Log it when it starts",
            tip: "Cycles often vary more in perimenopause",
            action: .logPeriod, isDone: false, stops: []
        )
    }
}
