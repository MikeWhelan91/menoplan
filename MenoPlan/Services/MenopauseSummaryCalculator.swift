import Foundation

/// How someone's cycle has been changing, from the periods they've logged.
/// Descriptive only: the markers here (consecutive cycles differing by 7+
/// days, gaps of 60+ days, 12 months without a period) are the ones
/// clinicians use to describe perimenopause, but MenoPlan never tells anyone
/// which stage they're in.
struct CycleChangeSummary: Equatable {
    /// Completed cycle lengths in days, oldest first, at most `maximumCycles`.
    var recentCycleLengths: [Int]
    var lastPeriodStart: Date?
    var daysSinceLastPeriod: Int?

    static let maximumCycles = 6
    static let noticeableChangeDays = 7
    static let longGapDays = 60
    static let menopauseDays = 365

    /// Two cycles in a row differed by 7 days or more.
    var hasNoticeableChange: Bool {
        zip(recentCycleLengths, recentCycleLengths.dropFirst()).contains { abs($0 - $1) >= Self.noticeableChangeDays }
    }

    /// A logged cycle, or the current wait, ran 60 days or more.
    var hasLongGap: Bool {
        recentCycleLengths.contains { $0 >= Self.longGapDays } || (daysSinceLastPeriod ?? 0) >= Self.longGapDays
    }

    /// Past 60 days without a period, progress towards 12 months.
    var twelveMonthProgress: Double? {
        guard let days = daysSinceLastPeriod, days >= Self.longGapDays else { return nil }
        return min(Double(days) / Double(Self.menopauseDays), 1)
    }

    var reachedTwelveMonths: Bool { (daysSinceLastPeriod ?? 0) >= Self.menopauseDays }

    /// One plain sentence describing the pattern.
    var headline: String {
        if reachedTwelveMonths { return "It's been 12 months or more since your last period." }
        if hasLongGap { return "You've had a gap of 60 days or more between periods. Longer gaps are common later in perimenopause." }
        if hasNoticeableChange { return "Your cycle length has changed by 7 days or more from one cycle to the next. This is common as periods start to change." }
        if recentCycleLengths.count < 2 { return "Log a few more periods to see how your cycle lengths are changing." }
        return "Your recent cycles have been fairly steady."
    }
}

enum CycleChangeCalculator {
    static func summary(
        periodStarts: [Date],
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> CycleChangeSummary {
        let today = calendar.startOfDay(for: date)
        // Starts within a week of each other are one bleed logged twice
        // (a Health import and a manual entry, say), not a 3-day cycle.
        var starts: [Date] = []
        for start in Set(periodStarts.map { calendar.startOfDay(for: $0) }).sorted() where start <= today {
            if let last = starts.last, (calendar.dateComponents([.day], from: last, to: start).day ?? 0) < 8 { continue }
            starts.append(start)
        }
        let lengths = zip(starts, starts.dropFirst()).compactMap { calendar.dateComponents([.day], from: $0, to: $1).day }
        let last = starts.last
        return CycleChangeSummary(
            recentCycleLengths: Array(lengths.suffix(CycleChangeSummary.maximumCycles)),
            lastPeriodStart: last,
            daysSinceLastPeriod: last.flatMap { calendar.dateComponents([.day], from: $0, to: today).day }
        )
    }
}

/// One modest observation for Home: how often a pinned symptom showed up
/// recently, set against the fortnight before, with any recent HRT change
/// alongside. It never claims a cause, and stays hidden until there are
/// enough logged days to say anything.
struct RecentChange: Equatable {
    var title: String
    var detail: String?
}

enum RecentChangeCalculator {
    static let windowDays = 14
    static let minimumLoggedDays = 7
    static let meaningfulDifference = 3

    static func observation(
        logs: [DailyFertilityLog],
        focus: [String],
        hrtChanged: Date? = nil,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> RecentChange? {
        let today = calendar.startOfDay(for: date)
        func window(_ offset: Int) -> [DailyFertilityLog] {
            guard let end = calendar.date(byAdding: .day, value: -offset * windowDays, to: today),
                  let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: end) else { return [] }
            var byDay: [Date: DailyFertilityLog] = [:]
            for log in logs where log.hasContent {
                let day = calendar.startOfDay(for: log.date)
                if day >= start && day <= end { byDay[day] = log }
            }
            return Array(byDay.values)
        }
        let recent = window(0)
        guard recent.count >= minimumLoggedDays else { return nil }
        let earlier = window(1)

        struct Candidate { var name: String; var now: Int; var before: Int? }
        let candidates = focus.map { name in
            Candidate(
                name: name,
                now: recent.filter { FocusSymptoms.isPresent(name, in: $0) }.count,
                before: earlier.count >= minimumLoggedDays ? earlier.filter { FocusSymptoms.isPresent(name, in: $0) }.count : nil
            )
        }

        let title: String
        if let change = candidates
            .filter({ $0.before != nil && abs($0.now - ($0.before ?? 0)) >= meaningfulDifference })
            .max(by: { abs($0.now - ($0.before ?? 0)) < abs($1.now - ($1.before ?? 0)) }),
           let before = change.before {
            title = "\(label(change.name)) on \(change.now) of your last \(recent.count) logged days, \(change.now > before ? "up" : "down") from \(before) the fortnight before."
        } else if let common = candidates.max(by: { $0.now < $1.now }), common.now * 2 >= recent.count, common.now > 0 {
            title = "\(label(common.name)) on \(common.now) of your last \(recent.count) logged days."
        } else {
            let rough = recent.filter { $0.dayImpact == .lots }.count
            guard rough > 0 else { return nil }
            title = "Symptoms affected your day a lot on \(rough) of your last \(recent.count) logged days."
        }

        var detail: String?
        if let hrtChanged {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: hrtChanged), to: today).day ?? 0
            if (0...42).contains(days) {
                detail = days == 0 ? "You changed your HRT today." : "You changed your HRT \(days) \(days == 1 ? "day" : "days") ago."
            }
        }
        return RecentChange(title: title, detail: detail)
    }

    /// Sentence-case name for the start of an observation.
    static func label(_ name: String) -> String {
        switch FocusSymptoms.kind(of: name) {
        case .sleep: return "Broken or poor sleep"
        default:
            let lower = name.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
    }
}
