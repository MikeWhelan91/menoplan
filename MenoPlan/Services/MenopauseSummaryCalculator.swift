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

/// The last seven days of the daily log, against the seven before, for
/// Home. Days with nothing logged are left out rather than counted as
/// symptom-free.
struct SymptomWeekSummary: Equatable {
    var hotFlushes: Int
    var previousHotFlushes: Int?
    var nightSweats: Int
    var previousNightSweats: Int?
    var badSleepNights: Int
    var hrtDays: Int
    var loggedDays: Int
    /// Most-logged symptoms this week, most frequent first.
    var topSymptoms: [String]

    var isEmpty: Bool { loggedDays == 0 }
}

enum SymptomWeekCalculator {
    static func summary(
        logs: [DailyFertilityLog],
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> SymptomWeekSummary {
        let today = calendar.startOfDay(for: date)
        func days(_ offset: Int) -> [DailyFertilityLog] {
            guard let end = calendar.date(byAdding: .day, value: -offset * 7, to: today),
                  let start = calendar.date(byAdding: .day, value: -6, to: end) else { return [] }
            return logs.filter { log in
                let day = calendar.startOfDay(for: log.date)
                return day >= start && day <= end && log.hasContent
            }
        }
        let week = days(0)
        let previous = days(1)
        func flushes(_ logs: [DailyFertilityLog]) -> Int { logs.reduce(0) { $0 + ($1.hotFlushCount ?? 0) } }
        let sweats: Int = week.reduce(0) { $0 + ($1.nightSweatCount ?? 0) }
        let badSleep = week.filter { $0.sleepQuality == .broken || $0.sleepQuality == .poor }.count
        let loggedDays = Set(week.map { calendar.startOfDay(for: $0.date) }).count
        var counts: [String: Int] = [:]
        for log in week { for symptom in log.symptoms { counts[symptom, default: 0] += 1 } }
        let ranked = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return SymptomWeekSummary(
            hotFlushes: flushes(week),
            previousHotFlushes: previous.isEmpty ? nil : flushes(previous),
            nightSweats: sweats,
            previousNightSweats: previous.isEmpty ? nil : previous.reduce(0) { $0 + ($1.nightSweatCount ?? 0) },
            badSleepNights: badSleep,
            hrtDays: week.filter { !$0.hrtTaken.isEmpty }.count,
            loggedDays: loggedDays,
            topSymptoms: ranked.prefix(3).map { $0.key }
        )
    }

}
