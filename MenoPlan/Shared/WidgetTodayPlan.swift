import Foundation

/// The "Today's Plan" widget answers one question - "should I test
/// today, and why?" - then lists the next few dates that matter. Testing guidance mirrors the app: ovulation tests start 7 days
/// before estimated ovulation, and a pregnancy test is possible from 4 days
/// before the expected period and most accurate from the period date itself.
struct WidgetTodayPlan: Equatable {
    enum Phase: Equatable { case idle, beforeTesting, ovulationTesting, twoWeekWait, periodDue }
    enum Action: Equatable { case ovulationTest, pregnancyTest }

    /// A date coming up, e.g. "Earliest Test" on Wed 1.
    struct Stop: Equatable {
        var title: String
        var date: Date
    }

    var phase: Phase
    /// Small-caps context, e.g. "Cycle day 24".
    var label: String
    /// The answer, e.g. "Test from tomorrow".
    var headline: String
    /// The reason, e.g. "About 10 days past ovulation · period due Tuesday".
    var detail: String
    /// Short version of `detail` for the small widget.
    var compactDetail: String
    /// One practical tip, shown when there's no action to take.
    var tip: String?
    /// Only set when testing today is actually sensible.
    var action: Action?
    /// Today's test is done - the headline gets a tick.
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
        func start(_ date: Date) -> Date { calendar.startOfDay(for: date) }
        func days(to other: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: start(other)).day ?? 0
        }
        func shift(_ date: Date, _ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: start(date)) ?? date
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
        func testedToday(_ result: WidgetSnapshot.LatestTest?) -> String? {
            result.flatMap { calendar.isDate($0.date, inSameDayAs: today) ? $0.resultRaw : nil }
        }

        let cycleDay = max(1, -days(to: cycle.cycleStart) + 1)
        let toOPK = days(to: cycle.opkStart)
        let toFertile = days(to: cycle.fertileStart)
        let toOvulation = days(to: cycle.ovulation)
        let toPeriod = days(to: cycle.nextPeriod)
        let ovulationTitle = cycle.ovulationConfirmed ? "Ovulation" : "Likely Ovulation"
        let earliest = shift(cycle.nextPeriod, -4)
        // Future dates only, one per day (the earlier entry wins a tie).
        var upcoming: [Stop] = []
        for (title, date) in [
            ("Ovulation Tests Start", cycle.opkStart), ("Fertile Days Begin", cycle.fertileStart),
            (ovulationTitle, cycle.ovulation), ("Earliest Pregnancy Test", earliest), ("Period Due", cycle.nextPeriod),
        ] where days(to: date) > 0 && !upcoming.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            upcoming.append(Stop(title: title, date: start(date)))
        }
        upcoming.sort { $0.date < $1.date }
        let stops = Array(upcoming.prefix(3))
        // An irregular cycle can widen the fertile days past the estimate;
        // until they end (or a test confirms ovulation) keep testing, as Home does.
        let widenedPastOvulation = !cycle.ovulationConfirmed
            && calendar.dateComponents([.day], from: start(cycle.ovulation), to: start(cycle.fertileEnd)).day ?? 0 > 1
            && days(to: cycle.fertileEnd) >= 0

        // MARK: Before ovulation testing

        if toOPK > 0 {
            return WidgetTodayPlan(
                phase: .beforeTesting,
                label: "Cycle day \(cycleDay)",
                headline: toOPK == 1 ? "Start Ovulation Tests Tomorrow" : "No Test Needed Today",
                detail: toOPK == 1 ? "Test in the afternoon for the clearest line" : "Ovulation tests start \(friendly(cycle.opkStart))",
                compactDetail: toOPK == 1 ? "Afternoon works best" : "Tests start \(friendly(cycle.opkStart))",
                tip: nil, action: nil, isDone: false, stops: stops
            )
        }

        // MARK: Ovulation testing window

        if toOvulation >= 0 || widenedPastOvulation {
            let windowSoFar = (0..<max(0, -toOPK)).map { WidgetSnapshot.dayKey(shift(cycle.opkStart, $0), calendar: calendar) }
            let testedBefore = windowSoFar.filter { snapshot.ovulationTestDays.contains($0) }.count
            let record = windowSoFar.isEmpty ? "First day of testing" : "Tested \(testedBefore) of the last \(windowSoFar.count) days"
            let ovulationText: String = switch toOvulation {
            case ..<0: "Ovulation may be a little later"
            case 0: "Ovulation estimated today"
            case 1: "Ovulation estimated tomorrow"
            default: "Ovulation estimated in \(toOvulation) days"
            }
            let label = toOvulation < 0 ? "Possible fertile days" : (toFertile <= 0 ? "Fertile window" : "Ovulation testing")
            let base = WidgetTodayPlan(
                phase: .ovulationTesting, label: label, headline: "", detail: "", compactDetail: ovulationText,
                tip: nil, action: nil, isDone: false, stops: stops
            )

            guard let result = testedToday(snapshot.latestOvulationTest) else {
                var plan = base
                plan.headline = toOvulation == 0 ? "Ovulation Likely Today" : "Take Today's Ovulation Test"
                plan.detail = "\(ovulationText) · \(record)"
                plan.action = .ovulationTest
                return plan
            }
            switch result {
            case "peak", "high":
                var plan = base
                plan.headline = "Ovulation Is Close"
                plan.detail = "Your test shows a surge · likely within 1-2 days"
                plan.compactDetail = "Ovulation likely soon"
                plan.tip = "Today and tomorrow are your most fertile days"
                plan.isDone = true
                return plan
            default:
                var plan = base
                plan.headline = "Today's Test Is Done"
                plan.detail = "\(ovulationText) · next test tomorrow"
                plan.tip = "Tip: test at the same time each day to compare lines"
                plan.isDone = true
                return plan
            }
        }

        // MARK: After ovulation

        let dpo = -toOvulation
        let pastOvulation = cycle.ovulationConfirmed ? "\(dpo) DPO" : "About \(dpo) DPO"
        let isLate = toPeriod <= 0
        let label: String = switch toPeriod {
        case 1...: "Cycle day \(cycleDay)"
        case 0: "Period due today"
        case -1: "Period 1 day late"
        default: "Period \(-toPeriod) days late"
        }
        let base = WidgetTodayPlan(
            phase: isLate ? .periodDue : .twoWeekWait, label: label, headline: "", detail: "", compactDetail: "",
            tip: nil, action: nil, isDone: false, stops: stops
        )
        let retestDay = friendly(shift(today, 2))

        switch testedToday(snapshot.latestPregnancyTest) {
        case "faintLineDetected":
            var plan = base
            plan.headline = "Faint Line Today"
            plan.detail = "Retest \(retestDay) to see if the line gets darker"
            plan.compactDetail = "Retest \(retestDay)"
            plan.tip = "Faint lines are common in the first days"
            plan.isDone = true
            return plan
        case "appearsPositive":
            var plan = base
            plan.headline = "Positive Test Today"
            plan.detail = "Retest \(retestDay) to watch the line darken"
            plan.compactDetail = "Retest \(retestDay)"
            plan.tip = "When you're ready, let your GP or midwife know"
            plan.isDone = true
            return plan
        case .some:
            var plan = base
            plan.headline = "Today's Test Is Done"
            if isLate {
                plan.detail = "No period yet? Test again \(retestDay)"
                plan.compactDetail = "Test again \(retestDay)"
            } else {
                plan.detail = "\(pastOvulation) · most accurate \(friendly(cycle.nextPeriod))"
                plan.compactDetail = "Most accurate \(friendly(cycle.nextPeriod))"
            }
            plan.tip = "An early negative can still turn positive"
            plan.isDone = true
            return plan
        case .none:
            break
        }

        var plan = base
        if isLate || toPeriod == 0 {
            plan.headline = "Take a Pregnancy Test"
            plan.detail = "A test now gives a reliable result"
            plan.compactDetail = "Result will be reliable"
            plan.action = .pregnancyTest
        } else if days(to: earliest) > 0 {
            // "Test from Tomorrow" already names the day, so the reason line
            // moves on to the period date instead of repeating it.
            let fromTomorrow = days(to: earliest) == 1
            plan.headline = fromTomorrow ? "Test from Tomorrow" : "Too Early to Test"
            plan.detail = fromTomorrow
                ? "\(pastOvulation) · period due \(friendly(cycle.nextPeriod))"
                : "\(pastOvulation) · earliest test \(friendly(earliest))"
            plan.compactDetail = fromTomorrow ? "Period due \(friendly(cycle.nextPeriod))" : "Earliest test \(friendly(earliest))"
            plan.tip = "Testing too early can miss a pregnancy"
        } else {
            plan.headline = "You Can Test Today"
            plan.detail = "\(pastOvulation) · most accurate \(friendly(cycle.nextPeriod))"
            plan.compactDetail = "Most accurate \(friendly(cycle.nextPeriod))"
            plan.action = .pregnancyTest
        }
        return plan
    }
}
