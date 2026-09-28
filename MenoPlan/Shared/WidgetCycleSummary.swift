import Foundation

/// The words the widgets show on a given day, derived from the snapshot's
/// facts. No predicted or "late" dates: while periods continue it counts from
/// the last one; otherwise it shows how the log is going.
struct WidgetCycleSummary: Equatable {
    enum State: Equatable { case notSetUp, needsPeriod, sinceLastPeriod, logging }

    var state: State
    var label: String
    var headline: String
    var detail: String
    /// Short one-liner for the inline lock-screen widget.
    var inline: String
    /// Number and caption for the circular lock-screen widget.
    var circularValue: String
    var circularCaption: String

    static func make(for snapshot: WidgetSnapshot, on date: Date, calendar: Calendar = .current) -> WidgetCycleSummary {
        let checkIn = WidgetCheckIn.make(for: snapshot, on: date, calendar: calendar)
        guard snapshot.isSetUp else {
            return WidgetCycleSummary(state: .notSetUp, label: "MenoPlan", headline: "Get Started", detail: "Open MenoPlan to set up",
                                      inline: "Set up MenoPlan", circularValue: "–", circularCaption: "Setup")
        }
        if snapshot.tracksCycle {
            guard let last = snapshot.lastPeriodStart else {
                return WidgetCycleSummary(state: .needsPeriod, label: "Your cycle", headline: "Add Period", detail: "Log your last period to see how your cycle is changing",
                                          inline: "Add your last period", circularValue: "–", circularCaption: "Cycle")
            }
            let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: date)).day ?? 0)
            return WidgetCycleSummary(
                state: .sinceLastPeriod,
                label: "Last period",
                headline: days == 0 ? "Today" : days == 1 ? "1 Day Ago" : "\(days) Days Ago",
                detail: "Started \(last.formatted(.dateTime.day().month(.abbreviated)))",
                inline: days == 0 ? "Period started today" : "Last period \(days) \(days == 1 ? "day" : "days") ago",
                circularValue: "\(days)", circularCaption: "Days"
            )
        }
        let month = calendar.dateInterval(of: .month, for: date)
        let loggedThisMonth = snapshot.loggedDays.filter { key in
            guard let month, let day = WidgetCheckIn.date(fromKey: key, calendar: calendar) else { return false }
            return month.contains(day) && day <= date
        }.count
        return WidgetCycleSummary(
            state: .logging,
            label: "This month",
            headline: loggedThisMonth == 1 ? "1 Day Logged" : "\(loggedThisMonth) Days Logged",
            detail: checkIn.loggedToday ? "Checked in today" : "Tap to check in today",
            inline: checkIn.loggedToday ? "Checked in today" : "Check in today",
            circularValue: "\(loggedThisMonth)", circularCaption: "Logged"
        )
    }
}

/// The check-in widget: has today been logged, which symptoms to rate, and
/// the last seven days at a glance. No streaks - a gap is just a gap.
struct WidgetCheckIn: Equatable {
    struct Day: Equatable {
        var date: Date
        var logged: Bool
    }

    var loggedToday: Bool
    var headline: String
    var detail: String
    var focus: [String]
    var week: [Day]

    static func make(for snapshot: WidgetSnapshot, on date: Date, calendar: Calendar = .current) -> WidgetCheckIn {
        let today = calendar.startOfDay(for: date)
        let loggedToday = snapshot.isLogged(today, calendar: calendar)
        let week = (0..<7).reversed().compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(date: day, logged: snapshot.isLogged(day, calendar: calendar))
        }
        let focus = Array(snapshot.focus.prefix(3))
        return WidgetCheckIn(
            loggedToday: loggedToday,
            headline: loggedToday ? "Logged Today" : "How's Today?",
            detail: loggedToday ? "Tap to add or change anything" : (focus.isEmpty ? "A tap or two is enough" : focus.joined(separator: " · ")),
            focus: focus,
            week: week
        )
    }

    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
